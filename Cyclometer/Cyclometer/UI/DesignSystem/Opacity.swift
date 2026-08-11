import Foundation

/// Opacity design tokens. Documented in `assets/UX.md` → Opacity. Prefer these
/// over inline literals so washes stay consistent and tunable in one place.
enum Opacity {
    /// Background sparkline / watermark behind a dashboard hero number.
    static let watermark: Double = 0.2
    /// Coloured zone band wash behind a watermark history chart (e.g. cadence zones).
    static let zoneBand: Double = 0.12
    /// History trace line drawn over zone bands — fainter than foreground text but
    /// readable against the band wash.
    static let lineWatermark: Double = 0.35
    /// Tinted square behind a sensor row's SF Symbol (`SensorListRowView`).
    static let iconTile: Double = 0.14
}
