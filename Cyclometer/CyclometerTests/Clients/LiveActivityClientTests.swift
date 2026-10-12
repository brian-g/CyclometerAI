import ActivityKit
import Foundation
import Testing
@testable import Cyclometer

/// #307 — the live `LiveActivityClient` against real ActivityKit, in the simulator the test host
/// runs on. Serialized, and every test clears ride activities first (and last, when it gets
/// there), because the activities are the system's, shared by every test in the process.
///
/// ActivityKit applies a request, update or end asynchronously: read back at once, an activity
/// still shows what it had. Every check waits for the change with `expectEventually`.
@MainActor
@Suite(.serialized, .enabled(if: ActivityAuthorizationInfo().areActivitiesEnabled))
struct LiveActivityClientTests {

    private let client = LiveActivityClient.liveValue
    private let metric = RideActivityAttributes(units: .metric)

    nonisolated private static func state(speedMPS: Double = 7.89, distanceMeters: Double = 12_300) -> RideActivityAttributes.ContentState {
        .init(status: .riding, startDate: Date(timeIntervalSince1970: 1_000_000), pausedElapsed: nil,
              speedMPS: speedMPS, distanceMeters: distanceMeters, routeProgress: 0.42)
    }

    /// The ride activities still on screen.
    nonisolated private static func showing() -> [Activity<RideActivityAttributes>] {
        Activity<RideActivityAttributes>.activities.filter { [.active, .stale].contains($0.activityState) }
    }

    /// Ends whatever an earlier test or run left behind.
    private func clearActivities() async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @Test func startShowsTheRide() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))

        await expectEventually("one activity, showing the state") {
            Self.showing().only?.content.state == Self.state()
        }
        #expect(Self.showing().only?.attributes == metric)
        await clearActivities()
    }

    /// A ride resumed after a crash calls `start` again; it must not leave two activities.
    @Test func startAgainAdoptsTheRunningActivity() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))
        await expectEventually { Self.showing().count == 1 }
        let first = try #require(Self.showing().only?.id)

        #expect(await client.start(metric, Self.state(distanceMeters: 15_000)))
        await expectEventually("the new state, on the same activity") {
            Self.showing().only?.content.state.distanceMeters == 15_000
        }
        #expect(Self.showing().only?.id == first)
        await clearActivities()
    }

    /// The system keeps an ended activity for hours. A ride that crashed and wasn't resumed leaves
    /// one, and the next ride must get an activity of its own, not adopt the dead one.
    @Test func startReplacesAnEndedActivity() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))
        await expectEventually { Self.showing().count == 1 }
        let ended = try #require(Self.showing().only)
        await ended.end(nil, dismissalPolicy: .default)
        await expectEventually("ended, but still listed") { ended.activityState == .ended }

        #expect(await client.start(metric, Self.state(distanceMeters: 15_000)))
        await expectEventually("a new activity shows the new ride") {
            Self.showing().only?.content.state.distanceMeters == 15_000
        }
        #expect(Self.showing().only?.id != ended.id)
        await expectEventually("the old one is off the Lock Screen") { ended.activityState == .dismissed }
        await clearActivities()
    }

    /// Units are fixed when an activity is requested, so a ride in other units needs a new one.
    @Test func startInOtherUnitsReplacesTheActivity() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))
        await expectEventually { Self.showing().count == 1 }

        let imperial = RideActivityAttributes(units: .imperial)
        #expect(await client.start(imperial, Self.state()))
        await expectEventually("one activity, in the new units") {
            Self.showing().only?.attributes == imperial
        }
        await clearActivities()
    }

    @Test func updateReplacesTheStateAndPushesStaleness() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))
        await expectEventually { Self.showing().count == 1 }

        let before = Date.now
        await client.update(Self.state(speedMPS: 9))
        await expectEventually("the update arrives") { Self.showing().only?.content.state.speedMPS == 9 }
        let staleDate = try #require(Self.showing().only?.content.staleDate)
        let ahead = staleDate.timeIntervalSince(before)
        #expect(ahead >= LiveActivityClient.staleInterval - 1 && ahead <= LiveActivityClient.staleInterval + 5,
                "stale \(ahead) s ahead")
        await clearActivities()
    }

    /// `.immediate`: the ride's card leaves the Lock Screen when the ride ends, with no summary
    /// left behind. A `.default` end would leave it `.ended` and on screen for up to 4 hours.
    @Test func endTakesTheRideOffTheLockScreen() async throws {
        await clearActivities()
        #expect(await client.start(metric, Self.state()))
        await expectEventually { Self.showing().count == 1 }

        await client.end()
        await expectEventually("every ride activity dismissed") {
            Activity<RideActivityAttributes>.activities.allSatisfy { $0.activityState == .dismissed }
        }
    }
}

private extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
