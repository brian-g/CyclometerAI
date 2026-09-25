import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S10 — Ride Summary (#249): waits for the ride's finalize, then shows the persisted ride,
/// with a default name for one the rider hasn't named.
@MainActor
@Suite("RideSummaryFeature")
struct RideSummaryFeatureTests {

    // MARK: Harness

    /// 08:00 UTC — a morning ride under `calendar` below.
    private static let startedAt = Date(timeIntervalSince1970: 1_700_035_200)

    private static let summary = RideListSummary(
        id: UUID(), title: "", startedAt: startedAt, distanceMeters: 1_100, durationSeconds: 100
    )

    private static let stats = RideStats(
        averageSpeedMPS: 6, maxSpeedMPS: 11, averageCadenceRPM: 90, maxCadenceRPM: 104, vehiclePassCount: 2
    )

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeStore(
        persistenceClient: PersistenceClient,
        geocodingClient: GeocodingClient = .testValue,
        clock: TestClock<Duration> = TestClock()
    ) -> TestStoreOf<RideSummaryFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            TestStore(initialState: RideSummaryFeature.State(rideId: Self.summary.id)) {
                RideSummaryFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.healthKitClient = .testValue
                $0.geocodingClient = geocodingClient
                $0.continuousClock = clock
                $0.calendar = Self.calendar
                $0.date = .constant(Date(timeIntervalSince1970: 1_750_000_000))
                $0.defaultFileStorage = storage
            }
        }
    }

    /// `count` seconds heading north, about 11 m a second — one way, never back to the start.
    nonisolated static func track(count: Int = 100, heartRate: (Int) -> Int? = { 120 + $0 % 60 }) -> [TrackPointDTO] {
        (0..<count).map { second in
            TrackPointDTO(
                rideId: summary.id,
                timestamp: startedAt.addingTimeInterval(Double(second)),
                latitude: 45 + Double(second) * 0.0001,
                longitude: -93,
                altitudeMeters: 250 + Double(second),
                horizontalAccuracyMeters: 5,
                speedMPS: 11,
                speedSource: .gps,
                heartRateBPM: heartRate(second),
                heartRateSource: heartRate(second) == nil ? .none : .bleHR,
                cadenceRPM: 90
            )
        }
    }

    private func load(_ store: TestStoreOf<RideSummaryFeature>) async {
        store.exhaustivity = .off
        await store.send(.task)
        await store.finish()
        await store.skipReceivedActions()
    }

    // MARK: Waiting for the finalize

    /// The screen opens on the action that starts the finalize, so the first reads miss the
    /// ride. It must not show the checkpoint's numbers in the meantime.
    @Test("task waits for the ride's finalize before reading anything")
    func waitsForFinalize() async {
        let clock = TestClock()
        let finalized = LockIsolated(false)
        let statsReads = LockIsolated(0)
        var client = PersistenceClient.mock(trackPoints: [Self.summary.id: Self.track()])
        client.fetchRides = { finalized.value ? [Self.summary] : [] }
        client.fetchRideStats = { _ in
            statsReads.withValue { $0 += 1 }
            return Self.stats
        }
        let store = makeStore(persistenceClient: client, clock: clock)
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.healthProfileFetched)
        #expect(store.state.load == .waiting)
        #expect(statsReads.value == 0)

        finalized.setValue(true)
        await clock.advance(by: .seconds(1))
        await store.receive(\.loaded)

        #expect(store.state.load == .loaded)
        #expect(store.state.summary == Self.summary)
        #expect(store.state.stats == Self.stats)
        #expect(statsReads.value == 1)
    }

    @Test("a finalize that never lands leaves the screen unavailable, not loading forever")
    func finalizeTimeout() async {
        let clock = TestClock()
        let store = makeStore(persistenceClient: .mock(), clock: clock)
        store.exhaustivity = .off

        await store.send(.task)
        await clock.advance(by: .seconds(RidesFeature.finalizeWaitSeconds))
        await store.receive(\.finalizeTimedOut)
        #expect(store.state.load == .unavailable)
    }

    // MARK: Content

    @Test("the loaded ride carries its track, elevation, stats and HR zones from persistence")
    func loadsPersistedRide() async {
        let points = Self.track()
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: points],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ))

        await load(store)

        #expect(store.state.trackSegments == RideMapThumbnail.drawableSegments(points))
        #expect(store.state.elevationProfileMeters?.first == 250)
        #expect(store.state.stats?.averageCadenceRPM == 90)
        // Every recorded second with a reading lands in exactly one zone.
        #expect(store.state.heartRateZoneSeconds.count == HeartRateZone.allCases.count)
        #expect(store.state.heartRateZoneSeconds.reduce(0, +) == points.count)
    }

    @Test("with no HR or cadence sensor, the zones are empty and cadence is nil — never zeros")
    func noSensorsAreAbsent() async {
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track(heartRate: { _ in nil })],
            rideStats: [Self.summary.id: RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11)],
            rides: [Self.summary]
        ))

        await load(store)

        #expect(store.state.heartRateZoneSeconds.isEmpty)
        #expect(store.state.stats?.averageCadenceRPM == nil)
        #expect(store.state.stats?.vehiclePassCount == nil)
    }

    // MARK: Title

    @Test("an unnamed ride gets its default name in the field, ready to save")
    func defaultTitleFromTimeAndShape() async {
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ))

        await load(store)

        #expect(store.state.title == "Morning Ride")
        #expect(store.state.defaultTitle == "Morning Ride")
        #expect(store.state.titleToSave == "Morning Ride")
    }

    @Test("a ride on a route is named for the route")
    func defaultTitleFromRoute() async {
        var stats = Self.stats
        stats.routeName = "SW Fargo"
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: stats],
            rides: [Self.summary]
        ))

        await load(store)

        #expect(store.state.title == "SW Fargo")
    }

    @Test("a ride that already has a name keeps it, and dismissing untouched saves nothing")
    func existingTitleKept() async {
        var named = Self.summary
        named.title = "Coffee Run"
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [named]
        ))

        await load(store)

        #expect(store.state.title == "Coffee Run")
        #expect(store.state.titleToSave == nil)
    }

    @Test("a name typed before the ride loads isn't replaced by the default")
    func typedTitleSurvivesLoad() async {
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ))
        store.exhaustivity = .off

        await store.send(.titleChanged("Hill Repeats"))
        await load(store)

        #expect(store.state.title == "Hill Repeats")
        #expect(store.state.titleToSave == "Hill Repeats")
    }

    // MARK: Place name (#283)

    private static let fargo = GeocodingClient { _ in "Fargo" }

    @Test("the start's place name joins an untouched default once the lookup answers")
    func placeNameJoinsDefault() async {
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ), geocodingClient: Self.fargo)

        await load(store)

        #expect(store.state.title == "Fargo Morning Ride")
        #expect(store.state.defaultTitle == "Fargo Morning Ride")
        #expect(store.state.titleToSave == "Fargo Morning Ride")
    }

    @Test("the ride-end default is swapped for the placed one, and saved on dismiss")
    func placeNameReplacesPersistedDefault() async {
        var named = Self.summary
        named.title = "Morning Ride"
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [named]
        ), geocodingClient: Self.fargo)

        await load(store)

        #expect(store.state.title == "Fargo Morning Ride")
        #expect(store.state.titleToSave == "Fargo Morning Ride")
    }

    @Test("a name the rider typed before the lookup answers is kept")
    func typedTitleSurvivesPlaceName() async {
        let clock = TestClock()
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ), geocodingClient: GeocodingClient { _ in
            try await clock.sleep(for: .seconds(1))
            return "Fargo"
        })
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.loaded)
        await store.send(.titleChanged("Hill Repeats"))
        await clock.advance(by: .seconds(1))
        await store.receive(\.placedTitleResolved)

        #expect(store.state.title == "Hill Repeats")
        #expect(store.state.defaultTitle == "Fargo Morning Ride")
        await store.finish()
    }

    @Test("the offline default shows without waiting on the lookup")
    func loadDoesNotWaitOnLookup() async {
        let clock = TestClock()
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ), geocodingClient: GeocodingClient { _ in
            try await clock.sleep(for: .seconds(60))
            return "Fargo"
        })
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.loaded)

        #expect(store.state.load == .loaded)
        #expect(store.state.title == "Morning Ride")
        await store.skipInFlightEffects()
    }

    @Test("a failed lookup keeps the offline default")
    func failedLookupKeepsDefault() async {
        let calls = LockIsolated(0)
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: Self.stats],
            rides: [Self.summary]
        ), geocodingClient: GeocodingClient { _ in
            calls.withValue { $0 += 1 }
            throw URLError(.notConnectedToInternet)
        })

        await load(store)

        #expect(calls.value == 1)
        #expect(store.state.title == "Morning Ride")
        #expect(store.state.defaultTitle == "Morning Ride")
    }

    @Test("a ride on a route never asks the geocoder")
    func routeRideSkipsLookup() async {
        var stats = Self.stats
        stats.routeName = "SW Fargo"
        let calls = LockIsolated(0)
        let store = makeStore(persistenceClient: .mock(
            trackPoints: [Self.summary.id: Self.track()],
            rideStats: [Self.summary.id: stats],
            rides: [Self.summary]
        ), geocodingClient: GeocodingClient { _ in
            calls.withValue { $0 += 1 }
            return "Fargo"
        })

        await load(store)

        #expect(calls.value == 0)
        #expect(store.state.title == "SW Fargo")
    }

    @Test("a cleared or blank field saves the default, never an empty title")
    func blankTitleSavesDefault() {
        var state = RideSummaryFeature.State(rideId: Self.summary.id)
        state.defaultTitle = "Morning Ride"
        state.title = "   "
        #expect(state.titleToSave == "Morning Ride")

        state.persistedTitle = "Morning Ride"
        #expect(state.titleToSave == nil)
    }
}

/// S10's zone breakdown arithmetic (#249), against explicit bounds rather than a profile.
@Suite("RideDetailSeries.zoneSeconds")
struct RideZoneSecondsTests {
    private let bounds = [100...119, 120...139, 140...159, 160...179, 180...200]

    @Test("each second lands in the zone whose range holds it")
    func secondsByZone() {
        let seconds = RideDetailSeries.zoneSeconds([110: 3, 125: 2, 139: 1, 140: 4, 185: 5], zoneBounds: bounds)
        #expect(seconds == [3, 3, 4, 0, 5])
    }

    @Test("below zone 1 counts as zone 1 and above zone 5 as zone 5, as the S15 chart draws them")
    func outOfRangeClamps() {
        #expect(RideDetailSeries.zoneSeconds([60: 2, 220: 7], zoneBounds: bounds) == [2, 0, 0, 0, 7])
    }

    @Test("a BLE strap's missing second is a dropout and counts for nothing")
    func histogramSkipsStrapDropouts() {
        let points = RideSummaryFeatureTests.track(count: 4, heartRate: { $0 == 1 ? nil : 150 })
        #expect(RideDetailSeries.secondsByBPM(points) == [150: 3])
    }

    /// Code review of #249: the recorder stamps an Apple Watch sample only on the second it
    /// arrives, so counting stamped seconds credited a Watch ride with a fifth of its time.
    @Test("an Apple Watch sample stands for the seconds after it, until the next one")
    func watchSamplesHoldForward() {
        // A sample every 5 s, for 20 s: 140, 150, 160, 170.
        let points = watchTrack(count: 20) { $0 % 5 == 0 ? 140 + $0 * 2 : nil }
        #expect(RideDetailSeries.secondsByBPM(points) == [140: 5, 150: 5, 160: 5, 170: 5])
    }

    @Test("a held Watch sample expires after the hold, and never crosses a pause")
    func watchHoldLimits() {
        let hold = Int(RideDetailSeries.appleWatchHoldSeconds)
        let expired = watchTrack(count: hold + 10) { $0 == 0 ? 150 : nil }
        #expect(RideDetailSeries.secondsByBPM(expired) == [150: hold + 1])

        let paused = watchTrack(count: 10, segmentBreak: 4) { $0 == 0 ? 150 : nil }
        #expect(RideDetailSeries.secondsByBPM(paused) == [150: 4])
    }

    /// One point a second, with Apple Watch heart rate where `heartRate` gives one.
    private func watchTrack(count: Int, segmentBreak: Int? = nil, heartRate: (Int) -> Int?) -> [TrackPointDTO] {
        RideSummaryFeatureTests.track(count: count, heartRate: heartRate).enumerated().map { second, point in
            var point = point
            if point.heartRateBPM != nil { point.heartRateSource = .appleWatch }
            if let segmentBreak, second >= segmentBreak { point.segmentIndex = 1 }
            return point
        }
    }
}
