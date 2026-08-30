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
}
