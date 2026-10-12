import ActivityKit
import ComposableArchitecture
import Foundation
import os

private let logger = Logger.cyclometer(.liveActivity)

/// TCA dependency for the ride's Live Activity (PRD §8.10, #307): the S05.3 mini-player's
/// content on the Lock Screen and in the Dynamic Island, drawn by the `CyclometerWidgets`
/// extension.
///
/// Local updates only — no push tokens — and never an alert: no call takes an
/// `AlertConfiguration`, so the activity cannot sound, buzz or wake the screen. Rider alerts are
/// the audio and haptics clients' job.
struct LiveActivityClient {
    /// Shows the ride. Adopts an activity that's already running with the same attributes — a
    /// ride resumed after a crash finds the one it started — rather than requesting a second.
    /// False when none is showing: ActivityKit refused the request, which it does to an app
    /// in the background (#308 retries on the next foreground).
    var start: @Sendable (RideActivityAttributes, RideActivityAttributes.ContentState) async -> Bool
    var update: @Sendable (RideActivityAttributes.ContentState) async -> Void
    /// Ends it with `.immediate` dismissal: no summary is left on the Lock Screen.
    var end: @Sendable () async -> Void
    /// The rider's system setting for this app's Live Activities.
    var isEnabled: @Sendable () -> Bool
}

extension LiveActivityClient {
    /// How long a state counts as current. Every update moves the stale date this far ahead, so
    /// an activity whose app has died shows as stale rather than as a ride still going (§8.10).
    static let staleInterval: TimeInterval = 30
}

extension LiveActivityClient: DependencyKey {
    /// Holds no `Activity`: each call acts on the system's list of ride activities, which a
    /// relaunch can't lose. There should only ever be one.
    static let liveValue = LiveActivityClient(
        start: { attributes, state in
            // Adopt one that's still showing this ride's units; end the rest. The system's list
            // keeps ended activities for hours, and units are fixed at request, so an ended one
            // or one in the other units can't carry the new ride.
            var adopted = false
            for activity in Activity<RideActivityAttributes>.activities {
                if !adopted, [.active, .stale].contains(activity.activityState), activity.attributes == attributes {
                    await activity.update(content(state))
                    adopted = true
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            if adopted { return true }
            do {
                _ = try Activity.request(attributes: attributes, content: content(state), pushType: nil)
                return true
            } catch {
                logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        },
        update: { state in await updateAll(state) },
        end: {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        },
        isEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled }
    )

    /// Switched off, so a ride under test shows no activity unless the test supplies a client.
    static let testValue = LiveActivityClient(
        start: { _, _ in false },
        update: { _ in },
        end: { },
        isEnabled: { false }
    )

    /// Previews never reach ActivityKit.
    static let previewValue = testValue

    private static func content(_ state: RideActivityAttributes.ContentState) -> ActivityContent<RideActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleInterval))
    }

    private static func updateAll(_ state: RideActivityAttributes.ContentState) async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.update(content(state))
        }
    }
}

extension DependencyValues {
    var liveActivityClient: LiveActivityClient {
        get { self[LiveActivityClient.self] }
        set { self[LiveActivityClient.self] = newValue }
    }
}
