import CoreLocation
import Foundation
import HealthKit
import Testing
@testable import Cyclometer

@Suite("HealthKitClient")
struct HealthKitClientTests {

    @Test("testValue never has data — RiderProfile falls through to the next term")
    func testValueIsEmpty() async throws {
        let client = HealthKitClient.testValue
        #expect(try await client.fetchRestingHeartRate() == nil)
        #expect(try await client.fetchDateOfBirth() == nil)
        #expect(try await client.fetchHeartRateZoneCeilings() == nil)

        var samples: [Int] = []
        for await bpm in client.heartRateStream() { samples.append(bpm) }
        #expect(samples.isEmpty)
    }

    @Test("mock returns exactly what it is scripted with")
    func mockReturnsScriptedValues() async throws {
        let dob = DateComponents(year: 1990, month: 1, day: 1)
        let client = HealthKitClient.mock(
            restingHeartRate: 58,
            dateOfBirth: dob,
            heartRateZoneCeilings: [120, 140, 160, 175],
            heartRateSamples: [90, 92, 95]
        )

        #expect(try await client.fetchRestingHeartRate() == 58)
        #expect(try await client.fetchDateOfBirth() == dob)
        #expect(try await client.fetchHeartRateZoneCeilings() == [120, 140, 160, 175])

        var samples: [Int] = []
        for await bpm in client.heartRateStream() { samples.append(bpm) }
        #expect(samples == [90, 92, 95])
    }

    @Test("mock defaults to empty — a test that forgets to script HealthKit gets nothing, not a plausible number")
    func mockDefaultsAreEmpty() async throws {
        let client = HealthKitClient.mock()
        #expect(try await client.fetchRestingHeartRate() == nil)
        #expect(try await client.fetchDateOfBirth() == nil)

        var samples: [Int] = []
        for await bpm in client.heartRateStream() { samples.append(bpm) }
        #expect(samples.isEmpty)
    }

    @Test("the workout route carries each track point's position, accuracy and time, in order (#295)")
    func routeLocationsMapTrackPoints() {
        let rideId = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let points = [
            TrackPointDTO(
                rideId: rideId, timestamp: start, latitude: 43.0731, longitude: -89.4012,
                altitudeMeters: 270, horizontalAccuracyMeters: 4, speedMPS: 6.5, speedSource: .gps,
                heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil, powerWatts: nil
            ),
            TrackPointDTO(
                rideId: rideId, timestamp: start.addingTimeInterval(1), latitude: 43.0732, longitude: -89.4013,
                altitudeMeters: nil, horizontalAccuracyMeters: 8, speedMPS: nil, speedSource: .none,
                heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil, powerWatts: nil
            ),
        ]

        let locations = HealthKitClient.routeLocations(points)

        #expect(locations.count == 2)
        for (location, point) in zip(locations, points) {
            #expect(location.coordinate.latitude == point.latitude)
            #expect(location.coordinate.longitude == point.longitude)
            // No valid altitude (#303) goes in as 0, which the −1 vertical accuracy below marks unusable.
            #expect(location.altitude == point.altitudeMeters ?? 0)
            #expect(location.horizontalAccuracy == point.horizontalAccuracyMeters)
            #expect(location.timestamp == point.timestamp)
            // Never recorded, so never invented.
            #expect(location.course == -1)
            #expect(location.verticalAccuracy == -1)
        }
        #expect(locations[0].speed == 6.5)
        #expect(locations[1].speed == -1)
    }

    /// A poor-GPS second's position is one no fix gave, and its accuracy is the rejected fix's,
    /// −1 for an invalid one, which makes a `CLLocation` invalid. Fitness draws the same line
    /// between the trusted points either side of it.
    @Test("the workout route leaves out a second recorded under a poor fix (#624)")
    func routeLocationsSkipUntrustedPoints() {
        let rideId = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let points = [(0.0, true, 4.0), (1, false, -1), (2, false, 35), (3, true, 6)].map { second, trusted, accuracy in
            TrackPointDTO(
                rideId: rideId, timestamp: start.addingTimeInterval(second), latitude: 43.0731 + second / 10_000,
                longitude: -89.4012, horizontalAccuracyMeters: accuracy, speedSource: .bleWheel,
                heartRateSource: .none, isPositionTrusted: trusted
            )
        }

        let locations = HealthKitClient.routeLocations(points)

        #expect(locations.map(\.timestamp) == [start, start.addingTimeInterval(3)])
        #expect(locations.map(\.horizontalAccuracy) == [4, 6])
    }

    // MARK: - Health's preferred zones (#238)

    private static func configuration(startingAt starts: [Double]) throws -> HKWorkoutZoneConfiguration {
        try HKWorkoutZoneConfiguration(
            quantityType: HKQuantityType(.heartRate),
            zoneBoundaries: starts.map { HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: $0) }
        )
    }

    /// A zone runs `[minimum, maximum)`, so the one below a zone starting at 121 bpm tops out at 120.
    @Test("each zone's ceiling is one bpm below where the next zone starts")
    func zoneCeilingsAreOneBelowTheNextStart() throws {
        let configuration = try Self.configuration(startingAt: [121, 141, 161, 176])

        #expect(HealthKitClient.zoneCeilings(from: configuration) == [120, 140, 160, 175])
    }

    /// 120.5 isn't a whole bpm: 120 is still below it, in the zone underneath, and 121 is above.
    @Test("a fractional start rounds up before the ceiling is taken")
    func fractionalStartRoundsUp() throws {
        let configuration = try Self.configuration(startingAt: [120.5, 140, 160, 175])

        #expect(HealthKitClient.zoneCeilings(from: configuration)?.first == 120)
    }

    @Test("anything but five zones has no ceilings", arguments: [[120.0, 140, 160], [120.0, 140, 160, 175, 185]])
    func otherZoneCountsHaveNoCeilings(_ starts: [Double]) throws {
        #expect(HealthKitClient.zoneCeilings(from: try Self.configuration(startingAt: starts)) == nil)
    }

    // MARK: - Workout span (#646)

    private static let rideStart = Date(timeIntervalSince1970: 1_757_155_800)
    /// HealthKit's own limit, the same for every type the workout writes.
    private static let limit = HKQuantityType(.distanceCycling).maximumAllowedDuration

    @Test("a span up to Health's limit passes", arguments: [30.0 * 60, limit])
    func spanWithinLimitPasses(_ seconds: TimeInterval) throws {
        try HealthKitClient.checkSpan(from: Self.rideStart, to: Self.rideStart.addingTimeInterval(seconds))
    }

    /// A ride left running for 5 days: HealthKit raised an uncatchable exception on it.
    @Test("a span over Health's limit throws before reaching HealthKit")
    func spanOverLimitThrows() {
        #expect(throws: WorkoutWriteError.exceedsMaximumDuration(Self.limit)) {
            try HealthKitClient.checkSpan(from: Self.rideStart, to: Self.rideStart.addingTimeInterval(Self.limit + 1))
        }
    }

    @Test("a span that ends before it starts throws")
    func spanEndingBeforeStartThrows() {
        #expect(throws: WorkoutWriteError.endsBeforeStart) {
            try HealthKitClient.checkSpan(from: Self.rideStart, to: Self.rideStart.addingTimeInterval(-60))
        }
    }

    /// The workout and its route are capped too, not only the samples, so a span check of the
    /// samples alone would still let a long ride reach `HKWorkoutBuilder`.
    @Test("every type the workout writes is checked, and each has a limit")
    func everyWrittenTypeIsChecked() {
        #expect(Set(HealthKitClient.workoutSpanTypes) == PermissionsClient.healthShareTypes)
        #expect(HealthKitClient.workoutSpanTypes.allSatisfy { $0.isMaximumDurationRestricted })
    }
}
