import Foundation
import Testing
@testable import Cyclometer

/// #306 — the Live Activity's state, which the app encodes and the extension decodes.
@Suite("RideActivityAttributes")
struct RideActivityAttributesTests {

    typealias State = RideActivityAttributes.ContentState

    @Test("content state survives encoding, riding and paused", arguments: [
        State(status: .riding, startDate: Date(timeIntervalSince1970: 1_000_000), pausedElapsed: nil,
              speedMPS: 7.89, distanceMeters: 12_300, routeProgress: 0.42),
        State(status: .paused, startDate: Date(timeIntervalSince1970: 1_000_000), pausedElapsed: 2_340,
              speedMPS: 0, distanceMeters: 12_300, routeProgress: nil),
    ])
    func roundTrip(_ state: State) throws {
        let decoded = try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }

    /// ActivityKit drops an update whose state is 4 KB or more (PRD §8.10). Every field set, each
    /// number at its longest encoding.
    @Test("the largest content state stays under ActivityKit's 4 KB")
    func worstCaseFitsTheLimit() throws {
        let largest = State(
            status: .paused,
            startDate: .distantFuture,
            pausedElapsed: -.greatestFiniteMagnitude,
            speedMPS: -.greatestFiniteMagnitude,
            distanceMeters: -.greatestFiniteMagnitude,
            routeProgress: -.leastNonzeroMagnitude
        )
        #expect(try JSONEncoder().encode(largest).count < 4_096)
    }
}
