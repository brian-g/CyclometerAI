import UIKit

extension UITraitCollection {
    /// The traits every snapshot renders with (#648): the device settings a reference must never
    /// inherit, at iOS's defaults — text size Large, Bold Text off, Increase Contrast off — and the
    /// appearance, Light unless the snapshot is of Dark.
    ///
    /// SnapshotTesting overrides only the traits a test passes, on top of its device config, and
    /// renders in a window with no scene. Any trait left unset comes from the simulator, which
    /// is whatever Device Hub last set there. On 2026-11-22 a simulator's text size set to Medium
    /// failed 292 snapshots that were correct. Appearance is a device setting too, and every
    /// reference that passed none was recorded in Light.
    ///
    /// What this can't pin: UIKit's own Increase Contrast adjustment to tinted system controls (a
    /// `Picker`'s value, a `Slider`'s fill, a `Link`). It follows the global setting, not these
    /// traits, so with Increase Contrast on, 10 snapshots still differ. Run the tests on the
    /// erased "Cyclometer Tests" simulator (`scripts/test-simulator.sh`), which has it off.
    ///
    /// `adjust` is for a snapshot that tests one of these on purpose, such as a larger text size.
    static func snapshot(
        _ style: UIUserInterfaceStyle = .light,
        _ adjust: (inout any UIMutableTraits) -> Void = { _ in }
    ) -> UITraitCollection {
        UITraitCollection { traits in
            traits.preferredContentSizeCategory = .large
            traits.legibilityWeight = .regular
            traits.accessibilityContrast = .normal
            traits.userInterfaceStyle = style
            adjust(&traits)
        }
    }
}
