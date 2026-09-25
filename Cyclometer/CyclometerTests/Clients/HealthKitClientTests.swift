import CoreLocation
import Foundation
import Testing
@testable import Cyclometer

@Suite("HealthKitClient")
struct HealthKitClientTests {

    @Test("testValue never has data — RiderProfile falls through to the next term")
    func testValueIsEmpty() async throws {
        let client = HealthKitClient.testValue
        #expect(try await client.fetchRestingHeartRate() == nil)
        #expect(try await client.fetchDateOfBirth() == nil)

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
            heartRateSamples: [90, 92, 95]
        )

        #expect(try await client.fetchRestingHeartRate() == 58)
        #expect(try await client.fetchDateOfBirth() == dob)

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
                altitudeMeters: 271, horizontalAccuracyMeters: 8, speedMPS: nil, speedSource: .none,
                heartRateBPM: nil, heartRateSource: .none, cadenceRPM: nil, powerWatts: nil
            ),
        ]

        let locations = HealthKitClient.routeLocations(points)

        #expect(locations.count == 2)
        for (location, point) in zip(locations, points) {
            #expect(location.coordinate.latitude == point.latitude)
            #expect(location.coordinate.longitude == point.longitude)
            #expect(location.altitude == point.altitudeMeters)
            #expect(location.horizontalAccuracy == point.horizontalAccuracyMeters)
            #expect(location.timestamp == point.timestamp)
            // Never recorded, so never invented.
            #expect(location.course == -1)
            #expect(location.verticalAccuracy == -1)
        }
        #expect(locations[0].speed == 6.5)
        #expect(locations[1].speed == -1)
    }
}
