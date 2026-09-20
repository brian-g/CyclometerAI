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

    // ── Map ─────────────────────────────────────────────────────────────────
    /// 26 pt — direction-of-travel arrows drawn along a route polyline (S19, S20, the live map).
    ///
    /// A system symbol weight rather than D-DIN: it sets an SF Symbol, not a number. Fixed
    /// rather than Dynamic Type-scaled, because a map annotation is anchored to a point on
    /// the ground — growing it only makes neighbouring arrows collide. 26 pt, arrived at by
    /// rendering 14, 20 and 26 over a real route at a street-level zoom (#258 review): the arrow
    /// is drawn in the line's own colour, so its size is the only thing separating it from the
    /// line, and below ~20 pt it reads as a thickening rather than as an arrowhead.
    static let cyMapAnnotation = Font.system(size: 26, weight: .bold)
    /// 64 pt SF Pro Rounded semibold — the turn overlay's arrow (Sketch "Sxx - Route overlay")
    static let cyTurnGlyph = Font.system(size: 64, weight: .semibold, design: .rounded)
    /// 40 pt SF Pro Rounded semibold — W9's arrow beside a medium hero number (#200). The overlay's
    /// 64 pt would stand taller than the number it sits beside.
    static let cyTurnGlyphCompact = Font.system(size: 40, weight: .semibold, design: .rounded)
    /// 34 pt SF Pro regular — the turn overlay's instruction, under the arrow
    static let cyTurnInstruction = Font.system(size: 34)
}
