import Foundation

/// Opacity design tokens. Documented in `assets/UX.md` → Opacity. Prefer these
/// over inline literals so washes stay consistent and tunable in one place.
enum Opacity {
    /// Background sparkline / watermark behind a dashboard hero number.
    static let watermark: Double = 0.2
}
