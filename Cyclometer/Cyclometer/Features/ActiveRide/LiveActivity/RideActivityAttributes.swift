import ActivityKit
import Foundation

/// The ride's Live Activity (PRD §8.10): the S05.3 mini-player's content on the Lock Screen and
/// in the Dynamic Island. Compiled into the app, which starts and updates the activity, and into
/// the `CyclometerWidgets` extension, which draws it (#306).
///
/// State values are canonical — metres, m/s — and converted with `units` in the view, as the
/// mini-player does.
struct RideActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        var status: RideStatus
        /// When the ride started, less any paused time: `Text(timerInterval:)` counts from it,
        /// so the timer ticks without an update every second.
        var startDate: Date
        /// The elapsed time shown, frozen, while `status` is `.paused`.
        var pausedElapsed: TimeInterval?
        var speedMPS: Double
        var distanceMeters: Double
        /// 0…1, `NavigationFeature.State.routeProgressFraction`. Nil while no route is being
        /// followed, which shows the app's rider glyph (#310).
        var routeProgress: Double?
    }

    var units: UnitSystem
}

/// The ride as the Live Activity shows it. A pause only changes the icon and freezes the timer;
/// the activity keeps running until the ride ends.
enum RideStatus: String, Codable, Hashable {
    case riding, paused
}
