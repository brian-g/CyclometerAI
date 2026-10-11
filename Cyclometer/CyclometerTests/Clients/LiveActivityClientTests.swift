import ActivityKit
import Foundation
import Testing
@testable import Cyclometer

/// #307 — the live `LiveActivityClient` against real ActivityKit, in the simulator the test host
/// runs on. Serialized, and every test clears ride activities first (and last, when it gets
/// there), because the activities are the system's, shared by every test in the process.
@MainActor
@Suite(.serialized, .enabled(if: ActivityAuthorizationInfo().areActivitiesEnabled))
struct LiveActivityClientTests {

    private let client = LiveActivityClient.liveValue
    private let attributes = RideActivityAttributes(units: .metric)

    private static func state(speedMPS: Double = 7.89, distanceMeters: Double = 12_300) -> RideActivityAttributes.ContentState {
        .init(status: .riding, startDate: Date(timeIntervalSince1970: 1_000_000), pausedElapsed: nil,
              speedMPS: speedMPS, distanceMeters: distanceMeters, routeProgress: 0.42)
    }

    private var running: [Activity<RideActivityAttributes>] {
        Activity<RideActivityAttributes>.activities.filter { $0.activityState == .active }
    }

    /// The running activity once its content satisfies `condition`. ActivityKit applies an update
    /// asynchronously: `activity.update` returns before `content` reads the new state.
    private func activity(
        within limit: Duration = .seconds(5),
        where condition: (RideActivityAttributes.ContentState) -> Bool
    ) async throws -> Activity<RideActivityAttributes>? {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if let activity = running.only, condition(activity.content.state) { return activity }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Ends whatever an earlier test or run left behind.
    private func clearActivities() async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @Test func startShowsTheRide() async throws {
        await clearActivities()
        await client.start(attributes, Self.state())

        let activity = try #require(running.only)
        #expect(activity.attributes.units == .metric)
        #expect(activity.content.state == Self.state())
        await clearActivities()
    }

    /// A ride resumed after a crash calls `start` again; it must not leave two activities.
    @Test func startAgainAdoptsTheRunningActivity() async throws {
        await clearActivities()
        await client.start(attributes, Self.state())
        await client.start(attributes, Self.state(distanceMeters: 15_000))

        #expect(try await activity { $0.distanceMeters == 15_000 } != nil, "the state never arrived")
        #expect(running.count == 1)
        await clearActivities()
    }

    @Test func updateReplacesTheStateAndPushesStaleness() async throws {
        await clearActivities()
        await client.start(attributes, Self.state())

        let before = Date.now
        await client.update(Self.state(speedMPS: 9))
        let activity = try #require(try await activity { $0.speedMPS == 9 }, "the state never arrived")
        let staleDate = try #require(activity.content.staleDate)
        let ahead = staleDate.timeIntervalSince(before)
        #expect(ahead >= LiveActivityClient.staleInterval - 1 && ahead <= LiveActivityClient.staleInterval + 5,
                "stale \(ahead) s ahead")
        await clearActivities()
    }

    @Test func endLeavesNoRideActivity() async throws {
        await clearActivities()
        await client.start(attributes, Self.state())
        try #require(running.count == 1)

        await client.end()
        #expect(running.isEmpty)
    }
}

private extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
