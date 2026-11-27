import ComposableArchitecture
import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.network)

/// Sends rides to Strava (PRD §8.12 "Uploading", TCA.md §4.15), #630. App-lifetime, scoped on
/// `AppFeature`, so an upload outlives the screen that chose it.
///
/// A ride enters the queue only by the rider's choice (`enqueue`): S10's Sync To (#631), or a
/// Retry (#632). Each upload is a `RideSyncRecord` on the ride, written at every step, so a ride
/// left `pending`, `uploading` or `processing` by a quit is found again by `resume`, which runs at
/// launch, whenever the app becomes active, and when Strava becomes able to take uploads.
///
/// One ride: `pending` → `uploading` (the GPX goes up) → `processing` (Strava has the file; its
/// upload id is kept) → `synced` with the activity id, or `failed` with Strava's reason. Strava
/// rejecting the file as a duplicate is `synced` with the existing activity: many riders' Strava
/// app imports Apple Health. Anything that can pass (offline, the rate limit, an account that needs
/// reconnecting) leaves the record where it was, with the reason, for a later `resume`: on a backoff
/// timer for what passes by itself, when a 429 resets, or when the rider reconnects.
@Reducer
struct SyncQueueFeature {
    @Dependency(\.strava) var strava
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date) var date

    struct State: Equatable {
        @SharedReader(.appPreferences) var preferences
        /// Rides with a job running, so a `resume` landing beside an `enqueue` never sends one
        /// twice.
        var inFlight: Set<UUID> = []
        /// After Strava's 429: nothing calls it before this (`StravaError.rateLimited`). Saved, so
        /// a relaunch inside the window doesn't spend a request on another refusal.
        @Shared(.stravaUploadsHeldUntil) var heldUntil
        /// Backoff retries in a row that found something still waiting. A ride that settles starts
        /// it over: Strava is reachable again.
        var retryAttempt = 0
        /// A backoff retry is set and no `resume` has run since, so a batch of waiting rides sets
        /// one retry, not one each.
        var isRetryPending = false
    }

    /// How a ride's job ended, for what the queue does next.
    enum JobOutcome: Equatable, Sendable {
        /// `synced` or `failed`: nothing left to try.
        case settled
        /// Nothing was done: already on Strava, the ride gone, or stopped behind a 429.
        case skipped
        /// It can pass by itself (offline, 5xx, still processing): a backoff retry.
        case waiting
        /// Waits on the rider reconnecting, which resumes the queue itself (S12.1's `connected`).
        case waitingOnRider
        /// Strava's 429: resumed when it resets.
        case held(until: Date)
    }

    enum CancelID { case heldResume, retry }

    enum Action: Equatable {
        /// The rider chose to send this ride to Strava.
        case enqueue(rideId: UUID)
        /// Picks up every record left with work to do.
        case resume
        case owedFetched([OwedSync])
        case jobFinished(rideId: UUID, outcome: JobOutcome)
    }

    /// Waits before each backoff retry: 30 s, then 1, 2, 5 and 10 min, then every 15 min. A bike
    /// computer can stay in the foreground for hours, so `.active` alone would leave a ride offline
    /// at the café waiting until the rider next switches apps.
    static let retryDelays: [Duration] = [.seconds(30), .seconds(60), .seconds(120), .seconds(300), .seconds(600), .seconds(900)]

    /// Strava answers `POST /uploads` before it has processed the file: polled after 1, 2 and
    /// 4 s, then every 8 s, for two minutes (PRD §8.12). The last poll is at 119 s.
    static let pollDelays: [Duration] = {
        var delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]
        var elapsed: Duration = .seconds(7)
        while elapsed + .seconds(8) <= .seconds(120) {
            delays.append(.seconds(8))
            elapsed += .seconds(8)
        }
        return delays
    }()

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .enqueue(let rideId):
                guard !state.inFlight.contains(rideId) else { return .none }
                if let reason = holdReason(state) {
                    return .run { [persistenceClient] _ in
                        // Read first: a ride already on Strava keeps its synced record.
                        guard let record = await Self.startingRecord(rideId: rideId, persistenceClient: persistenceClient)
                        else { return }
                        logger.info("strava upload queued, held: \(reason, privacy: .public)")
                        try? await persistenceClient.saveSyncRecord(rideId, record.waiting(reason))
                    }
                }
                state.inFlight.insert(rideId)
                return upload([rideId])

            case .resume:
                state.isRetryPending = false
                // A hold saved before a relaunch: resumed when it resets, not on the next `.active`.
                if let heldUntil = state.heldUntil, heldUntil > date.now { return resume(after: heldUntil) }
                guard holdReason(state) == nil else { return .none }
                return .run { [persistenceClient] send in
                    do {
                        await send(.owedFetched(try await persistenceClient.fetchRidesOwedSync()))
                    } catch {
                        logger.error("strava resume couldn't read the queue: \(error.localizedDescription, privacy: .public)")
                    }
                }

            case .owedFetched(let owed):
                // Read again: the fetch was a suspension, and a 429 can have landed meanwhile.
                guard holdReason(state) == nil else { return .none }
                let rideIds = owed
                    .filter { $0.record.service == .strava && !state.inFlight.contains($0.rideId) }
                    .map(\.rideId)
                guard !rideIds.isEmpty else { return .none }
                logger.info("strava resume: \(rideIds.count, privacy: .public) upload(s)")
                state.inFlight.formUnion(rideIds)
                return upload(rideIds)

            case let .jobFinished(rideId, outcome):
                state.inFlight.remove(rideId)
                switch outcome {
                case .settled:
                    state.retryAttempt = 0
                    return .none
                case .skipped, .waitingOnRider:
                    return .none
                case .held(let until):
                    let heldUntil = max(state.heldUntil ?? until, until)
                    state.$heldUntil.withLock { $0 = heldUntil }
                    return resume(after: heldUntil)
                case .waiting:
                    guard !state.isRetryPending else { return .none }
                    let delay = Self.retryDelays[min(state.retryAttempt, Self.retryDelays.count - 1)]
                    state.retryAttempt += 1
                    state.isRetryPending = true
                    logger.info("strava retry in \(delay.components.seconds, privacy: .public) s")
                    return .run { [clock] send in
                        try await clock.sleep(for: delay)
                        await send(.resume)
                    }
                    .cancellable(id: CancelID.retry, cancelInFlight: true)
                }
            }
        }
    }

    /// Resumes once Strava's 429 has reset. A second after, so the resume doesn't land a moment
    /// early on a wall clock that disagrees with the continuous one, and find itself still held.
    private func resume(after heldUntil: Date) -> Effect<Action> {
        .run { [clock, date] send in
            try await clock.sleep(for: .seconds(max(0, heldUntil.timeIntervalSince(date.now))) + .seconds(1))
            await send(.resume)
        }
        .cancellable(id: CancelID.heldResume, cancelInFlight: true)
    }

    /// Why nothing can go to Strava now, or nil when it can.
    private func holdReason(_ state: State) -> String? {
        if let heldUntil = state.heldUntil, heldUntil > date.now { return SyncReason.rateLimited }
        guard let account = state.preferences.stravaAccount else { return SyncReason.notConnected }
        guard account.grantedScopes.contains(StravaConfig.uploadScope) else { return SyncReason.noUploadScope }
        return nil
    }

    /// Where a ride's upload starts, read as it starts: the record it's owed from, so an upload id
    /// carries on polling, or a fresh pending one. Nil for a ride already on Strava: Strava doesn't
    /// catch the same GPX sent twice, so a second upload would be a second activity. Nil too for a
    /// ride that's gone or can't be read.
    private static func startingRecord(rideId: UUID, persistenceClient: PersistenceClient) async -> RideSyncRecord? {
        let existing: RideSyncRecord?
        do {
            existing = try await persistenceClient.fetchSyncRecord(rideId, .strava)
        } catch {
            logger.notice("strava upload dropped: couldn't read the ride: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if let existing, existing.status == .synced {
            logger.info("strava upload skipped: the ride is already on Strava")
            return nil
        }
        if let existing, existing.status.isOwed { return existing }
        return RideSyncRecord(service: .strava, status: .pending)
    }

    /// Sends the rides one at a time, in the order given (`resume`'s is oldest first), so a 429
    /// stops the rest rather than each of them spending another request of the app's shared
    /// limit. Each starts from its record as it stands once the ride is in flight, not from what
    /// `resume` read: a job that settled the ride in between leaves it synced, and isn't repeated.
    private func upload(_ rideIds: [UUID]) -> Effect<Action> {
        .run { [strava, persistenceClient, clock, date] send in
            var isHeld = false
            for rideId in rideIds {
                var outcome = JobOutcome.skipped
                // After a 429 the rest only leave `inFlight`; their records wait for the hold to end.
                if !isHeld, let record = await Self.startingRecord(rideId: rideId, persistenceClient: persistenceClient) {
                    let job = StravaUploadJob(
                        rideId: rideId, strava: strava, persistenceClient: persistenceClient, clock: clock, now: { date.now }
                    )
                    outcome = await job.run(from: record)
                    if case .held = outcome { isHeld = true }
                }
                await send(.jobFinished(rideId: rideId, outcome: outcome))
            }
        }
    }
}

extension AppPreferences {
    /// Strava's account while it can sign requests: no record, or one Strava revoked, is nil.
    var stravaAccount: ConnectedService? {
        connectedServices.first { $0.serviceType == .strava && !$0.isDisconnected }
    }

    /// Strava can take uploads: connected, with the upload scope granted. `AppFeature` resumes the
    /// queue on `.active` only while this is true. A connect or a Reconnect resumes it through
    /// S12.1's `connected` delegate instead: `StravaSession` writes the record outside any
    /// reducer, where `.onChange` can't see this turn true.
    var canUploadToStrava: Bool {
        stravaAccount?.grantedScopes.contains(StravaConfig.uploadScope) ?? false
    }
}

/// What a record waiting on something says, in `RideSyncRecord.errorMessage`. A `failed` record
/// carries Strava's own text instead.
enum SyncReason {
    static let offline = "Offline"
    static let unreachable = "Couldn't reach Strava"
    static let unavailable = "Strava is unavailable"
    static let rateLimited = "Strava is busy; trying again later"
    static let notConnected = "Strava isn't connected"
    static let noUploadScope = "Uploads need “Upload your activities”"
    static let stillProcessing = "Still processing on Strava"
    static let uploadLost = "Strava lost the upload; sending it again"
    static let rideUnreadable = "Couldn't read the ride"
}

/// One ride's upload, from wherever its record stands. Every step is written before the next
/// starts, so a quit at any point leaves a record `resume` can carry on from.
private struct StravaUploadJob {
    let rideId: UUID
    let strava: StravaClient
    let persistenceClient: PersistenceClient
    let clock: any Clock<Duration>
    let now: @Sendable () -> Date

    /// Runs to a settled record, or to one left waiting, and says which.
    func run(from start: RideSyncRecord) async -> SyncQueueFeature.JobOutcome {
        var record = start
        do {
            if record.remoteUploadId == nil {
                try await upload(&record)
            }
            return try await poll(record) ? .settled : .waiting
        } catch is CancellationError {
            // The record stands as last written; the next launch resumes it.
            return .skipped
        } catch PersistenceError.rideNotFound {
            logger.notice("strava upload dropped: the ride is gone")
            return .skipped
        } catch {
            return await recordWaiting(record, after: error)
        }
    }

    /// `uploading`, the GPX up, then `processing` with Strava's upload id. The id is in `record`
    /// before it's saved, so a save that fails still leaves it for `recordWaiting`: Strava has the
    /// file, and sending it again would make a second activity.
    private func upload(_ record: inout RideSyncRecord) async throws {
        record.status = .uploading
        record.errorMessage = nil
        try await save(record)
        logger.info("strava upload: uploading")

        let inputs = try await GPXExporter.fetchInputs(rideId: rideId)
        let notes = inputs.ride.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let uploadID = try await strava.upload(StravaUpload(
            gpx: Data(GPXExporter.buildXML(inputs).utf8),
            name: inputs.ride.title,
            description: notes.isEmpty ? nil : notes,
            externalID: rideId.uuidString
        ))

        record.status = .processing
        record.remoteUploadId = uploadID.rawValue
        try await save(record)
        logger.info("strava upload: processing")
    }

    /// Polls until Strava settles the upload, or the two minutes run out. Out of time, the record
    /// stays `processing` with its upload id, polled again at the next `resume`. Settles a copy:
    /// when its save fails, `run` still holds the `processing` record and its upload id, so
    /// `recordWaiting` leaves it to be polled again rather than sent again.
    /// True once settled, false when still processing.
    private func poll(_ processing: RideSyncRecord) async throws -> Bool {
        guard let rawID = processing.remoteUploadId else { return true }
        var record = processing
        let uploadID = StravaUploadID(rawValue: rawID)
        for delay in SyncQueueFeature.pollDelays {
            try await clock.sleep(for: delay)
            let status = try await strava.uploadStatus(uploadID)
            switch status {
            case .processing:
                continue
            case .ready(let activityID), .duplicate(let activityID):
                record.status = .synced
                record.syncedAt = now()
                record.remoteActivityId = activityID
                record.remoteUploadId = nil
                record.errorMessage = nil
                try await save(record)
                if case .duplicate = status {
                    logger.info("strava upload: synced, as a duplicate of an activity Strava had")
                } else {
                    logger.info("strava upload: synced")
                }
                return true
            case .failed(let reason):
                record.status = .failed
                record.remoteUploadId = nil
                record.errorMessage = reason
                try await save(record)
                logger.notice("strava upload: failed: \(reason, privacy: .public)")
                return true
            }
        }
        record.errorMessage = SyncReason.stillProcessing
        try await save(record)
        logger.notice("strava upload: still processing after two minutes")
        return false
    }

    /// Leaves the record for the next `resume`, or fails it when trying again can't help.
    private func recordWaiting(_ record: RideSyncRecord, after error: any Error) async -> SyncQueueFeature.JobOutcome {
        let outcome = SyncFailure(error, isPolling: record.remoteUploadId != nil)
        var record = record
        switch outcome.action {
        case .wait:
            record = record.waiting(outcome.reason)
        case .reupload:
            record.status = .pending
            record.remoteUploadId = nil
            record.errorMessage = outcome.reason
        case .fail:
            record.status = .failed
            record.remoteUploadId = nil
            record.errorMessage = outcome.reason
        }
        logger.notice("strava upload: \(record.status.rawValue, privacy: .public): \(outcome.reason, privacy: .public)")
        try? await save(record)
        return outcome.outcome
    }

    private func save(_ record: RideSyncRecord) async throws {
        try await persistenceClient.saveSyncRecord(rideId, record)
    }
}

/// What an error during an upload means for its record.
struct SyncFailure: Equatable {
    enum Action: Equatable {
        /// It can pass: the record keeps its place (`pending`, or `processing` with its upload id).
        case wait
        /// Strava doesn't know the upload id: sent again from `pending`. A second copy of a file
        /// Strava did process answers as a duplicate, which ends `synced`.
        case reupload
        /// Trying again won't help; the rider's Retry (#632) can.
        case fail
    }

    var action: Action
    var reason: String
    var heldUntil: Date?
    /// Only the rider reconnecting can clear it, so retrying on a timer would only spend requests.
    var waitsOnRider = false

    /// What the queue does next.
    var outcome: SyncQueueFeature.JobOutcome {
        switch action {
        case .fail: .settled
        case .reupload: .waiting
        case .wait:
            if let heldUntil { .held(until: heldUntil) } else if waitsOnRider { .waitingOnRider } else { .waiting }
        }
    }

    init(_ error: any Error, isPolling: Bool) {
        switch error {
        case let error as URLError:
            action = .wait
            reason = [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
                ? SyncReason.offline : SyncReason.unreachable
        case StravaError.rateLimited(let until):
            action = .wait
            reason = SyncReason.rateLimited
            heldUntil = until
        case StravaError.unauthorized:
            // A 401 after a refresh: the upload scope is most likely missing (#627).
            action = .wait
            reason = SyncReason.noUploadScope
            waitsOnRider = true
        case StravaError.http(status: 404) where isPolling:
            action = .reupload
            reason = SyncReason.uploadLost
        case StravaError.http(let status) where status >= 500 || status == 408:
            action = .wait
            reason = SyncReason.unavailable
        case StravaError.http(let status):
            action = .fail
            reason = "Strava refused the upload (HTTP \(status))"
        case StravaError.invalidResponse:
            action = .fail
            reason = "Strava's answer couldn't be read"
        case StravaAuthError.notConnected, StravaAuthError.disconnected:
            // PRD §8.12: uploads waiting on Strava stay pending until the rider reconnects.
            action = .wait
            reason = SyncReason.notConnected
            waitsOnRider = true
        case is StravaAuthError:
            // The token service: a refresh that couldn't run.
            action = .wait
            reason = SyncReason.unreachable
        default:
            // The ride couldn't be read (a store error, not a missing ride).
            action = .wait
            reason = SyncReason.rideUnreadable
        }
    }
}

private extension RideSyncRecord {
    /// Left for the next `resume`: `pending` unless Strava already has the file, in which case it
    /// stays `processing` with its upload id.
    func waiting(_ reason: String) -> RideSyncRecord {
        var record = self
        record.status = remoteUploadId == nil ? .pending : .processing
        record.errorMessage = reason
        return record
    }
}

extension SharedKey where Self == FileStorageKey<Date?>.Default {
    /// `SyncQueueFeature`'s hold after Strava's 429 (#630). A file of its own: it's the queue's
    /// state, not a preference.
    static var stravaUploadsHeldUntil: Self {
        Self[.fileStorage(.documentsDirectory.appending(component: "strava-uploads-held-until.json")), default: nil]
    }
}
