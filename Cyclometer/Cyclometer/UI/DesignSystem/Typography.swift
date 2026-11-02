import SwiftUI

// MARK: - Cyclometer Typography
// Numbers are set by `HeroNumber` (UI/Components/HeroNumber), and D-DIN Condensed by `AppFonts`.
// This file holds the remaining fixed, non-numeric fonts, and the Dynamic Type cap for captions.

extension Font {
    /// 64 pt SF Pro Rounded semibold — the turn overlay's arrow (Sketch "Sxx - Route overlay")
    static let cyTurnGlyph = Font.system(size: 64, weight: .semibold, design: .rounded)
    /// 40 pt SF Pro Rounded semibold — W9's arrow beside a medium hero number (#200). The overlay's
    /// 64 pt would stand taller than the number it sits beside.
    static let cyTurnGlyphCompact = Font.system(size: 40, weight: .semibold, design: .rounded)
    /// 34 pt SF Pro regular — the turn overlay's instruction, under the arrow
    static let cyTurnInstruction = Font.system(size: 34)
}

extension DynamicTypeSize {
    /// The largest size a dashboard caption grows to: a widget's title and empty-state text, a hero's
    /// label and unit, a 1×1's symbol. Past it, accessibility sizes push them out of the cell (#499).
    static let cyCaptionMax = DynamicTypeSize.xxxLarge
}
