import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

/// #151 — the weather recorded during a ride is saved with it, survives a kill, and reaches S15.
@MainActor
@Suite("Ride weather recording")
struct RideWeatherRecordingTests {
    private static let start = Date(timeIntervalSince1970: 1_000_000)
    private static let samples = Array(RideWeatherSample.fixtureRide.prefix(3))

    @Test("The checkpoint a pause writes carries the weather recorded so far")
    func checkpointCarriesTheWeather() async {
        let written = LockIsolated<RideSummaryUpdate?>(nil)
        var state = ActiveRideFeature.State(recordingState: .active)
        state.weather.samples = Self.samples
        let store = TestStore(initialState: state) {
            ActiveRideFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = DateGenerator { Self.start }
            $0.hapticsClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(onUpdateRideSummary: { written.setValue($0) })
        }
        // About the checkpoint, not the effects a pause fans out (`ActiveRideFeatureTests`).
        store.exhaustivity = .off
        await store.send(.pauseTapped)
        await store.finish()

        #expect(written.value?.weather == Self.samples)
    }

    @Test("A ride killed mid-ride comes back with the weather it had recorded")
    func resumeRestoresTheWeather() {
        var summary = RideSummaryUpdate(rideId: UUID(), recordingState: .active, durationSeconds: 1_800,
                                        distanceMeters: 12_000, averageSpeedMPS: 6.6, maxSpeedMPS: 12)
        summary.weather = Self.samples
        #expect(ActiveRideFeature.State(resuming: summary).weather.samples == Self.samples)
    }

    @Test("Checkpoint, resume read and finish all keep the samples, and S15's stats carry them")
    func persistenceRoundTrip() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Self.start, nil)
        var update = RideSummaryUpdate(rideId: rideId, recordingState: .active, durationSeconds: 600,
                                       distanceMeters: 4_000, averageSpeedMPS: 6.6, maxSpeedMPS: 10)
        update.weather = Array(Self.samples.prefix(1))
        try await client.updateRideSummary(update)
        #expect(try await client.fetchResumableRide()?.weather == Array(Self.samples.prefix(1)))

        update.weather = Self.samples
        try await client.finalizeRide(rideId, Self.start.addingTimeInterval(1_800), update, nil)
        #expect(try await client.fetchRideStats(rideId).weather == Self.samples)
    }

    @Test("A ride with no weather stores none, and reads back empty")
    func noWeatherReadsEmpty() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Self.start, nil)
        try await client.finalizeRide(rideId, Self.start.addingTimeInterval(600), RideSummaryUpdate(
            rideId: rideId, durationSeconds: 600, distanceMeters: 4_000, averageSpeedMPS: 6.6, maxSpeedMPS: 10
        ), nil)
        #expect(try await client.fetchRideStats(rideId).weather.isEmpty)
    }

    /// JSON can't encode a non-finite number, and `Ride.weather`'s setter would then drop every
    /// sample of the ride (lessons, #191).
    @Test("A reading with a non-finite value is never recorded")
    func nonFiniteReadingIsRejected() {
        var reading = WeatherReading.fixture
        #expect(RideWeatherSample(reading) != nil)
        reading.temperature = Measurement(value: .nan, unit: .celsius)
        #expect(RideWeatherSample(reading) == nil)
        reading = .fixture
        reading.windDirection = Measurement(value: .infinity, unit: .degrees)
        #expect(RideWeatherSample(reading) == nil)

        var samples: [RideWeatherSample] = []
        samples.record(reading)
        #expect(samples.isEmpty)
    }

    @Test("A sample stores WeatherKit's reading in plain SI numbers")
    func sampleConvertsUnits() throws {
        let sample = try #require(RideWeatherSample(.fixture))
        #expect(sample.date == WeatherReading.fixture.date)
        #expect(sample.temperatureCelsius == 18)
        // Foundation's km/h coefficient is 0.277778, not 1/3.6: compare against its own conversion.
        #expect(sample.windSpeedMPS == Measurement(value: 14, unit: UnitSpeed.kilometersPerHour).converted(to: .metersPerSecond).value)
        #expect(sample.windFromDegrees == 270)
        #expect(sample.humidity == 0.62)
        #expect(sample.condition == .partlyCloudy)
    }
}
