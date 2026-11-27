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
/// reconnecting) leaves the record where it was, with the reason, for the next `resume`.
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
        /// After Strava's 429: nothing calls it before this (`StravaError.rateLimited`).
        var heldUntil: Date?
    }

    enum Action: Equatable {
        /// The rider chose to send this ride to Strava.
        case enqueue(rideId: UUID)
        /// Picks up every record left with work to do.
        case resume
        case owedFetched([OwedSync])
        case jobFinished(rideId: UUID, heldUntil: Date?)
    }

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

            case let .jobFinished(rideId, heldUntil):
                state.inFlight.remove(rideId)
                if let heldUntil {
                    state.heldUntil = max(state.heldUntil ?? heldUntil, heldUntil)
                }
                return .none
            }
        }
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
                var heldUntil: Date?
                // After a 429 the rest only leave `inFlight`; their records wait for the next `resume`.
                if !isHeld, let record = await Self.startingRecord(rideId: rideId, persistenceClient: persistenceClient) {
                    let job = StravaUploadJob(
                        rideId: rideId, strava: strava, persistenceClient: persistenceClient, clock: clock, now: { date.now }
                    )
                    heldUntil = await job.run(from: record)
                    isHeld = heldUntil != nil
                }
                await send(.jobFinished(rideId: rideId, heldUntil: heldUntil))
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

    /// Runs to a settled record, or to one left waiting. Returns when Strava may next be called,
    /// after a 429.
    func run(from start: RideSyncRecord) async -> Date? {
        var record = start
        do {
            if record.remoteUploadId == nil {
                try await upload(&record)
            }
            try await poll(record)
            return nil
        } catch is CancellationError {
            // The record stands as last written; the next launch resumes it.
            return nil
        } catch PersistenceError.rideNotFound {
            logger.notice("strava upload dropped: the ride is gone")
            return nil
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
    private func poll(_ processing: RideSyncRecord) async throws {
        guard let rawID = processing.remoteUploadId else { return }
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
                return
            case .failed(let reason):
                record.status = .failed
                record.remoteUploadId = nil
                record.errorMessage = reason
                try await save(record)
                logger.notice("strava upload: failed: \(reason, privacy: .public)")
                return
            }
        }
        record.errorMessage = SyncReason.stillProcessing
        try await save(record)
        logger.notice("strava upload: still processing after two minutes")
    }

    /// Leaves the record for the next `resume`, or fails it when trying again can't help.
    private func recordWaiting(_ record: RideSyncRecord, after error: any Error) async -> Date? {
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
        return outcome.heldUntil
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
