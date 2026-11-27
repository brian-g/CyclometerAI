import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// The Strava upload queue (#630, PRD §8.12 "Uploading"): upload, poll, record, and what each
/// failure leaves for the next `resume`.
@MainActor
@Suite("SyncQueueFeature")
struct SyncQueueFeatureTests {
    static let rideId = UUID(uuidString: "00000000-0000-0000-0000-000000000630")!
    static let otherRideId = UUID(uuidString: "00000000-0000-0000-0000-000000000631")!
    static let now = Date(timeIntervalSince1970: 1_795_996_800)
    static let metadata = RideExportMetadata(title: "Morning Loop", startedAt: now, notes: "Headwind both ways")

    nonisolated static func account(scopes: Set<String> = Set(StravaConfig.requestedScopes), isDisconnected: Bool = false) -> ConnectedService {
        ConnectedService(
            serviceType: .strava,
            keychainIdentifier: StravaConfig.keychainAccount,
            athleteID: "134815",
            grantedScopes: scopes,
            connectedAt: now,
            isDisconnected: isDisconnected
        )
    }

    /// What the queue wrote, and what it sent Strava, in order.
    final class Log: Sendable {
        let records = LockIsolated<[RideSyncRecord]>([])
        let uploads = LockIsolated<[StravaUpload]>([])
        let polls = LockIsolated(0)
    }

    private func makeStore(
        account: ConnectedService? = account(),
        strava: StravaClient,
        log: Log,
        owed: [OwedSync] = [],
        /// The records `startingRecord` reads. Defaults to `owed`'s, as the store would hold them.
        syncRecords: [UUID: [RideSyncRecord]]? = nil,
        clock: TestClock<Duration> = TestClock(),
        initialState: (inout SyncQueueFeature.State) -> Void = { _ in }
    ) -> TestStoreOf<SyncQueueFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock { $0.connectedServices = account.map { [$0] } ?? [] }
            var state = SyncQueueFeature.State()
            initialState(&state)
            return TestStore(initialState: state) {
                SyncQueueFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
                $0.continuousClock = clock
                $0.date = .constant(Self.now)
                $0.persistenceClient = .mock(
                    rideExportMetadata: [Self.rideId: Self.metadata, Self.otherRideId: Self.metadata],
                    ridesOwedSync: owed,
                    syncRecords: syncRecords ?? Dictionary(owed.map { ($0.rideId, [$0.record]) }, uniquingKeysWith: +),
                    onSaveSyncRecord: { _, record in log.records.withValue { $0.append(record) } }
                )
                $0.strava = strava
            }
        }
    }

    /// `StravaClient.mock`, with each upload and poll logged.
    private func strava(
        uploadID: String = "42",
        statuses: [StravaUploadStatus],
        log: Log,
        upload: (@Sendable () throws -> Void)? = nil
    ) -> StravaClient {
        var client = StravaClient.mock(
            uploadID: StravaUploadID(rawValue: uploadID),
            uploadStatuses: statuses,
            onUpload: { sent in log.uploads.withValue { $0.append(sent) } }
        )
        let poll = client.uploadStatus
        client.uploadStatus = { id in
            log.polls.withValue { $0 += 1 }
            return try await poll(id)
        }
        if let upload {
            let send = client.upload
            client.upload = { sent in
                try upload()
                return try await send(sent)
            }
        }
        return client
    }

    private static let uploading = RideSyncRecord(service: .strava, status: .uploading)
    private static func processing(_ uploadID: String = "42", reason: String? = nil) -> RideSyncRecord {
        RideSyncRecord(service: .strava, status: .processing, errorMessage: reason, remoteUploadId: uploadID)
    }
    private static func synced(_ activityID: String) -> RideSyncRecord {
        RideSyncRecord(service: .strava, status: .synced, syncedAt: now, remoteActivityId: activityID)
    }

    // MARK: - Uploading

    @Test("A ride uploads, is polled on schedule while Strava processes it, and is recorded synced with its activity")
    func uploadsAndSyncs() async throws {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(
            strava: strava(statuses: [.processing, .processing, .ready(activityID: "999")], log: log),
            log: log,
            clock: clock
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        #expect(log.polls.value == 1)
        await clock.advance(by: .seconds(2))
        #expect(log.polls.value == 2)
        await clock.advance(by: .seconds(3))
        #expect(log.polls.value == 2)
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.polls.value == 3)
        #expect(log.records.value == [Self.uploading, Self.processing(), Self.synced("999")])
        let upload = try #require(log.uploads.value.first)
        #expect(log.uploads.value.count == 1)
        #expect(upload.name == "Morning Loop")
        #expect(upload.description == "Headwind both ways")
        #expect(upload.externalID == Self.rideId.uuidString)
        #expect(String(decoding: upload.gpx, as: UTF8.self).contains("<gpx"))
    }

    @Test("A ride Strava already has (imported from Apple Health) is recorded synced with that activity")
    func duplicateIsSynced() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(strava: strava(statuses: [.duplicate(activityID: "123")], log: log), log: log, clock: clock)

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.records.value == [Self.uploading, Self.processing(), Self.synced("123")])
    }

    @Test("A file Strava couldn't process fails with Strava's reason, and waits for Retry")
    func processingFailureFails() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(strava: strava(statuses: [.failed(reason: "Improperly formatted data.")], log: log), log: log, clock: clock)

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.records.value.last == RideSyncRecord(service: .strava, status: .failed, errorMessage: "Improperly formatted data."))
    }

    @Test("Still processing after two minutes stays processing with its upload id, for the next resume")
    func processingTimeout() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(strava: strava(statuses: [.processing], log: log), log: log, clock: clock)

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(119))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.polls.value == SyncQueueFeature.pollDelays.count)
        #expect(log.records.value == [
            Self.uploading, Self.processing(), Self.processing(reason: SyncReason.stillProcessing),
        ])
    }

    @Test("The poll schedule is 1, 2, 4, then every 8 s, inside two minutes")
    func pollSchedule() {
        let delays = SyncQueueFeature.pollDelays
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4)] + Array(repeating: .seconds(8), count: 14))
        #expect(delays.reduce(.zero, +) <= .seconds(120))
    }

    // MARK: - Waiting

    @Test("Offline leaves the record pending with its reason")
    func offlineStaysPending() async {
        let log = Log()
        let store = makeStore(
            strava: strava(statuses: [], log: log) { throw URLError(.notConnectedToInternet) },
            log: log
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.records.value == [
            Self.uploading, RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.offline),
        ])
    }

    @Test("Offline while polling stays processing with its upload id")
    func offlineWhilePollingStaysProcessing() async {
        let log = Log()
        let clock = TestClock()
        var client = strava(statuses: [], log: log)
        client.uploadStatus = { _ in throw URLError(.networkConnectionLost) }
        let store = makeStore(
            strava: client,
            log: log,
            owed: [OwedSync(rideId: Self.rideId, record: Self.processing())],
            clock: clock
        )

        await store.send(.resume)
        await store.receive(\.owedFetched) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.isEmpty)
        #expect(log.records.value == [Self.processing(reason: SyncReason.unreachable)])
    }

    @Test("Strava's rate limit leaves the record pending, and holds the queue until it resets")
    func rateLimitHoldsQueue() async {
        let log = Log()
        let until = Self.now.addingTimeInterval(900)
        let store = makeStore(
            strava: strava(statuses: [], log: log) { throw StravaError.rateLimited(until: until) },
            log: log,
            owed: [OwedSync(rideId: Self.otherRideId, record: RideSyncRecord(service: .strava, status: .pending))]
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: until)) {
            $0.inFlight = []
            $0.heldUntil = until
        }
        #expect(log.records.value == [
            Self.uploading, RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.rateLimited),
        ])

        // Held: no fetch, no upload.
        await store.send(.resume)
        await store.send(.enqueue(rideId: Self.otherRideId))
        await store.finish()
        #expect(log.uploads.value.isEmpty)
        // The held enqueue writes its own waiting record, the same as the first ride's.
        let waiting = RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.rateLimited)
        #expect(log.records.value == [Self.uploading, waiting, waiting])
    }

    @Test("A poll Strava answers 404 drops the upload id and goes back to pending, to send again")
    func lostUploadIsSentAgain() async {
        let log = Log()
        let clock = TestClock()
        // The mock answers 404 for any upload id but its own.
        let store = makeStore(
            strava: strava(uploadID: "1", statuses: [.processing], log: log),
            log: log,
            owed: [OwedSync(rideId: Self.rideId, record: Self.processing("42"))],
            clock: clock
        )

        await store.send(.resume)
        await store.receive(\.owedFetched) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.records.value == [
            RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.uploadLost),
        ])
    }

    @Test("Not connected, or connected without the upload scope: nothing goes to Strava, and the record waits pending")
    func heldWithoutAccountOrScope() async {
        for (account, reason) in [
            (nil, SyncReason.notConnected),
            (Self.account(isDisconnected: true), SyncReason.notConnected),
            (Self.account(scopes: ["read", "activity:read_all"]), SyncReason.noUploadScope),
        ] as [(ConnectedService?, String)] {
            let log = Log()
            let store = makeStore(account: account, strava: strava(statuses: [], log: log), log: log)

            await store.send(.enqueue(rideId: Self.rideId))
            await store.send(.resume)
            await store.finish()

            #expect(log.uploads.value.isEmpty)
            #expect(log.records.value == [RideSyncRecord(service: .strava, status: .pending, errorMessage: reason)])
        }
    }

    // MARK: - A ride's existing record

    @Test("A ride already on Strava isn't sent again: Strava would make it a second activity")
    func syncedRideIsNotSentAgain() async {
        let log = Log()
        let store = makeStore(
            strava: strava(statuses: [], log: log), log: log,
            syncRecords: [Self.rideId: [Self.synced("555")]]
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.isEmpty)
        #expect(log.records.value.isEmpty)
    }

    @Test("Enqueued while held, a ride already on Strava keeps its synced record")
    func heldKeepsSyncedRecord() async {
        let log = Log()
        let store = makeStore(
            account: nil, strava: strava(statuses: [], log: log), log: log,
            syncRecords: [Self.rideId: [Self.synced("555")]]
        )

        await store.send(.enqueue(rideId: Self.rideId))
        await store.finish()

        #expect(log.records.value.isEmpty)
    }

    @Test("Enqueued while Strava still has its upload, a ride carries on polling rather than sending again")
    func owedRecordCarriesOn() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(
            strava: strava(statuses: [.ready(activityID: "555")], log: log), log: log,
            syncRecords: [Self.rideId: [Self.processing("42")]], clock: clock
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.isEmpty)
        #expect(log.records.value == [Self.synced("555")])
    }

    @Test("A ride whose upload failed is sent again from the start")
    func failedRecordIsSentAgain() async {
        let log = Log()
        let clock = TestClock()
        let failed = RideSyncRecord(service: .strava, status: .failed, errorMessage: "bad file")
        let store = makeStore(
            strava: strava(statuses: [.ready(activityID: "555")], log: log), log: log,
            syncRecords: [Self.rideId: [failed]], clock: clock
        )

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.count == 1)
        #expect(log.records.value == [Self.uploading, Self.processing("42"), Self.synced("555")])
    }

    // MARK: - Resuming

    @Test("At relaunch a pending record is uploaded and a processing one is only polled, one ride at a time")
    func relaunchResumes() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(
            strava: strava(uploadID: "7", statuses: [.ready(activityID: "555")], log: log),
            log: log,
            owed: [
                OwedSync(rideId: Self.rideId, record: RideSyncRecord(service: .strava, status: .uploading)),
                OwedSync(rideId: Self.otherRideId, record: Self.processing("7")),
            ],
            clock: clock
        )
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.resume)
        await store.receive(\.owedFetched) { $0.inFlight = [Self.rideId, Self.otherRideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil))
        #expect(log.polls.value == 1)
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.otherRideId, heldUntil: nil))

        #expect(store.state.inFlight.isEmpty)
        #expect(log.uploads.value.map(\.externalID) == [Self.rideId.uuidString])
        #expect(log.records.value.filter { $0.status == .synced } == [Self.synced("555"), Self.synced("555")])
    }

    @Test("A 429 during a resume stops the rides after it, which keep their records for the next resume")
    func resumeStopsAtRateLimit() async {
        let log = Log()
        let until = Self.now.addingTimeInterval(900)
        let pending = RideSyncRecord(service: .strava, status: .pending)
        let store = makeStore(
            strava: strava(statuses: [], log: log) { throw StravaError.rateLimited(until: until) },
            log: log,
            owed: [OwedSync(rideId: Self.rideId, record: pending), OwedSync(rideId: Self.otherRideId, record: pending)]
        )

        await store.send(.resume)
        await store.receive(\.owedFetched) { $0.inFlight = [Self.rideId, Self.otherRideId] }
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: until)) {
            $0.inFlight = [Self.otherRideId]
            $0.heldUntil = until
        }
        await store.receive(.jobFinished(rideId: Self.otherRideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.records.value == [
            Self.uploading, RideSyncRecord(service: .strava, status: .pending, errorMessage: SyncReason.rateLimited),
        ])
    }

    @Test("A ride a job settled after the resume read it isn't sent again")
    func resumeRereadsTheRecord() async {
        let log = Log()
        let store = makeStore(
            strava: strava(statuses: [], log: log), log: log,
            owed: [OwedSync(rideId: Self.rideId, record: RideSyncRecord(service: .strava, status: .pending))],
            syncRecords: [Self.rideId: [Self.synced("555")]]
        )

        await store.send(.resume)
        await store.receive(\.owedFetched) { $0.inFlight = [Self.rideId] }
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.isEmpty)
        #expect(log.records.value.isEmpty)
    }

    @Test("A synced record whose save fails stays processing with its upload id, to be polled, not sent, again")
    func failedSettleSaveKeepsUploadID() async {
        let log = Log()
        let clock = TestClock()
        let store = makeStore(strava: strava(statuses: [.ready(activityID: "999")], log: log), log: log, clock: clock)
        store.dependencies.persistenceClient.saveSyncRecord = { _, record in
            if record.status == .synced { throw CocoaError(.fileWriteOutOfSpace) }
            log.records.withValue { $0.append(record) }
        }

        await store.send(.enqueue(rideId: Self.rideId)) { $0.inFlight = [Self.rideId] }
        await clock.advance(by: .seconds(1))
        await store.receive(.jobFinished(rideId: Self.rideId, heldUntil: nil)) { $0.inFlight = [] }

        #expect(log.uploads.value.count == 1)
        #expect(log.records.value == [Self.uploading, Self.processing(), Self.processing(reason: SyncReason.rideUnreadable)])
    }

    @Test("A ride already in flight isn't run twice, by enqueue or resume")
    func inFlightRunsOnce() async {
        let log = Log()
        let store = makeStore(strava: strava(statuses: [], log: log), log: log) {
            $0.inFlight = [Self.rideId]
        }

        await store.send(.enqueue(rideId: Self.rideId))
        await store.send(.owedFetched([OwedSync(rideId: Self.rideId, record: RideSyncRecord(service: .strava, status: .pending))]))

        #expect(log.records.value.isEmpty)
        #expect(log.uploads.value.isEmpty)
    }

    // MARK: - Errors

    @Test("Each upload error waits, sends again, or fails, as PRD §8.12 has it")
    func failureClassification() {
        #expect(SyncFailure(URLError(.notConnectedToInternet), isPolling: false).action == .wait)
        #expect(SyncFailure(URLError(.timedOut), isPolling: false).reason == SyncReason.unreachable)
        #expect(SyncFailure(StravaError.unauthorized, isPolling: false).reason == SyncReason.noUploadScope)
        #expect(SyncFailure(StravaError.http(status: 503), isPolling: true).action == .wait)
        #expect(SyncFailure(StravaError.http(status: 404), isPolling: true).action == .reupload)
        #expect(SyncFailure(StravaError.http(status: 404), isPolling: false).action == .fail)
        #expect(SyncFailure(StravaError.http(status: 413), isPolling: false).action == .fail)
        #expect(SyncFailure(StravaError.invalidResponse, isPolling: false).action == .fail)
        #expect(SyncFailure(StravaAuthError.disconnected, isPolling: false) == SyncFailure(
            StravaAuthError.notConnected, isPolling: false
        ))
        #expect(SyncFailure(StravaAuthError.disconnected, isPolling: false).reason == SyncReason.notConnected)
        #expect(SyncFailure(StravaAuthError.tokenService(status: 502), isPolling: false).action == .wait)
    }
}
