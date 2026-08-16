import ComposableArchitecture
import UIKit

/// TCA dependency for display power management during a ride (#110).
///
/// Two concerns, both of which are process-global UIKit state rather than view
/// state, which is why they sit behind a dependency instead of a `View` modifier:
/// the idle timer (screen sleep) and the backlight level.
///
/// `setBrightness` writes the *rider's own system brightness setting* — it is not
/// scoped to the app. Every caller is responsible for restoring it; `AppFeature`
/// does so from a single state transition so there is one place to get it right.
struct ScreenClient {
    /// `true` keeps the display awake. Mirrors `UIApplication.isIdleTimerDisabled`.
    var setIdleTimerDisabled: @Sendable (Bool) async -> Void
    /// Current backlight level, 0…1.
    var brightness: @Sendable () async -> Double
    /// Sets the backlight level, 0…1.
    var setBrightness: @Sendable (Double) async -> Void
}

extension ScreenClient: DependencyKey {
    static let liveValue = ScreenClient(
        setIdleTimerDisabled: { disabled in
            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = disabled }
        },
        brightness: {
            await MainActor.run { activeScreen()?.brightness ?? 1 }
        },
        setBrightness: { level in
            await MainActor.run { activeScreen()?.brightness = level }
        }
    )

    static let testValue = ScreenClient(
        setIdleTimerDisabled: { _ in },
        brightness: { 1 },
        setBrightness: { _ in }
    )
}

/// `UIScreen.main` is deprecated, so the screen is resolved through the connected
/// scenes instead. Prefers the foreground-active scene, falling back to any window
/// scene — restore-on-background runs after the scene has already resigned active,
/// and must still find a screen to write to.
@MainActor
private func activeScreen() -> UIScreen? {
    let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first
    return scene?.screen
}

extension DependencyValues {
    var screenClient: ScreenClient {
        get { self[ScreenClient.self] }
        set { self[ScreenClient.self] = newValue }
    }
}
