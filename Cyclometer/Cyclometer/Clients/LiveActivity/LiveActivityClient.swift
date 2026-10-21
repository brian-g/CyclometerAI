import ActivityKit
import ComposableArchitecture
import Foundation
import os
import Synchronization

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
    /// Returns when the activity showing ends (#412). Meant for an end outside the app, but `end`
    /// itself reads as `.dismissed` too, so the caller tells them apart. `.ended` at once when none
    /// is showing. Nil when cancelled, or when the state updates finish without an end.
    var ended: @Sendable () async -> LiveActivityEnd?
}

/// How an activity ended outside the app (#412). ActivityKit gives no reason, only the state.
enum LiveActivityEnd: Equatable, Sendable {
    /// Still on the Lock Screen but no longer updated: the system's 8-hour limit. A new one can
    /// be requested.
    case ended
    /// Gone from the screen: the rider swiped it away, or chose "Don't Allow" at iOS's prompt.
    case dismissed
}

extension LiveActivityClient {
    /// How long a state counts as current. Every update moves the stale date this far ahead, so
    /// an activity whose app has died shows as stale rather than as a ride still going (§8.10).
    static let staleInterval: TimeInterval = 30
}

extension LiveActivityClient: DependencyKey {
    /// Holds no `Activity`: each call acts on the system's list of ride activities, which a
    /// relaunch can't lose. There should only ever be one.
    ///
    /// `start`, `update` and `end` run one at a time, in the order they're called (#411). An `end`
    /// sent while a `start` is out would otherwise sweep the list before the request lands in it,
    /// and leave that ride's card on the Lock Screen.
    static let liveValue = LiveActivityClient(
        start: { attributes, state in await calls.run {
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
        } },
        update: { state in await calls.run { await updateAll(state) } },
        end: { await calls.run {
            for activity in Activity<RideActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        } },
        isEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
        // Not queued: it waits as long as the activity shows, and every call after it would too.
        ended: {
            // `start` ended every other ride activity, so this is the one it left showing. None
            // showing means it has gone already; the next foreground's `start` recovers.
            guard let activity = Activity<RideActivityAttributes>.activities
                .first(where: { [.active, .stale].contains($0.activityState) }) else { return .ended }
            for await state in activity.activityStateUpdates {
                logger.info("Live Activity state: \(String(describing: state), privacy: .public)")
                switch state {
                case .ended: return .ended
                case .dismissed: return .dismissed
                default: continue
                }
            }
            return nil
        }
    )

    /// Switched off, so a ride under test shows no activity unless the test supplies a client.
    static let testValue = LiveActivityClient(
        start: { _, _ in false },
        update: { _ in },
        end: { },
        isEnabled: { false },
        ended: { nil }
    )

    /// Previews never reach ActivityKit.
    static let previewValue: LiveActivityClient = testValue

    private static let calls = SerialCalls()

    private static func content(_ state: RideActivityAttributes.ContentState) -> ActivityContent<RideActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleInterval))
    }

    private static func updateAll(_ state: RideActivityAttributes.ContentState) async {
        for activity in Activity<RideActivityAttributes>.activities {
            await activity.update(content(state))
        }
    }
}

/// Runs calls one at a time, in the order they're made. An actor alone wouldn't: a call
/// waiting on ActivityKit lets the next one in.
///
/// A call runs to the end even if its caller is cancelled: a request already underway can't be
/// stopped, and the `end` behind it must still find what it showed.
private final class SerialCalls: Sendable {
    /// The call made last, which the next one waits for.
    private let last = Mutex<Task<Void, Never>?>(nil)

    func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let call = last.withLock { last in
            let previous = last
            let call = Task {
                await previous?.value
                return await operation()
            }
            last = Task { _ = await call.value }
            return call
        }
        return await call.value
    }
}

extension DependencyValues {
    var liveActivityClient: LiveActivityClient {
        get { self[LiveActivityClient.self] }
        set { self[LiveActivityClient.self] = newValue }
    }
}
