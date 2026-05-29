import Testing
import ComposableArchitecture
@testable import Cyclometer

@Suite("VariaRadarClient — test value")
struct VariaRadarClientTests {

    @Test("Test value connect does not throw")
    func connectNoThrow() async throws {
        let client = VariaRadarClient.testValue
        try await client.connect("test-uuid")
    }

    @Test("Test value radar stream completes immediately")
    func streamCompletes() async {
        let client = VariaRadarClient.testValue
        var count = 0
        for await _ in client.radarTargets() {
            count += 1
        }
        #expect(count == 0)  // testValue stream finishes immediately
    }
}
