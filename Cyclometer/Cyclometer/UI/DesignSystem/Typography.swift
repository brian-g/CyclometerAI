import SwiftUI

// MARK: - Cyclometer Typography
// Primary typeface: D-DIN (installed in Resources/Fonts, declared in Info.plist)
// Fallback:         SF Pro Display

extension Font {
    static func ddin(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("D-DIN", size: size).weight(weight)
    }

    // ── Metric display ──────────────────────────────────────────────────────
    /// 82 pt — hero speed readout
    static let cyHeroSpeed    = Font.ddin(size: 82, weight: .black)
    /// 32 pt — large secondary metric
    static let cyMetricLarge  = Font.ddin(size: 32, weight: .bold)
    /// 24 pt — standard metric tile value
    static let cyMetricMedium = Font.ddin(size: 24, weight: .bold)
    /// 18 pt — small metric or section heading
    static let cyMetricSmall  = Font.ddin(size: 18, weight: .semibold)

    // ── Labels ──────────────────────────────────────────────────────────────
    /// 12 pt — metric labels, unit strings, uppercase tags
    static let cyLabel   = Font.ddin(size: 12)
    /// 10 pt — captions, secondary metadata
    static let cyCaption = Font.ddin(size: 10)
}
