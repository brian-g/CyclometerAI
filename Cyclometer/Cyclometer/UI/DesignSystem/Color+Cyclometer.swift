import SwiftUI

// MARK: - Cyclometer Design Tokens
// Primary brand : #60BD10 (Cyclometer green)
// Token prefix  : cy  (Cyclometer)
// Theme         : Dark-primary, outdoor sunlight optimised
// Contrast      : WCAG AA+ on all foreground/background pairs

extension Color {

    // MARK: Primary Brand
    /// Brand green — CTAs, active states, highlights
    static let cyPrimary      = Color("cyPrimary")
    /// Pressed / hover state
    static let cyPrimaryDark  = Color("cyPrimaryDark")
    /// Tinted backgrounds, chips
    static let cyPrimaryLight = Color("cyPrimaryLight")
    /// Secondary accents, inactive icons
    static let cyPrimaryMuted = Color("cyPrimaryMuted")

    // MARK: Backgrounds
    static let cyBgPrimary   = Color("cyBgPrimary")     // Main app background
    static let cyBgSecondary = Color("cyBgSecondary")   // Cards, grouped sections
    static let cyBgTertiary  = Color("cyBgTertiary")    // Inset fields, wells
    static let cyBgElevated  = Color("cyBgElevated")    // Modals, sheets, popovers

    // MARK: Text
    static let cyTextPrimary   = Color("cyTextPrimary")   // Headlines, critical values
    static let cyTextSecondary = Color("cyTextSecondary") // Descriptions, timestamps
    static let cyTextTertiary  = Color("cyTextTertiary")  // Placeholders, captions
    static let cyTextOnPrimary = Color("cyTextOnPrimary") // Text on primary buttons
    static let cyTextInverted  = Color("cyTextInverted")  // Text on inverted surfaces

    // MARK: Borders & Separators
    static let cyBorder       = Color("cyBorder")
    static let cyBorderSubtle = Color("cyBorderSubtle")
    static let cyBorderStrong = Color("cyBorderStrong")

    // MARK: Ratings
    static let cyRatingBad    = Color("cyRatingBad")
    static let cyRatingBadBg  = Color("cyRatingBadBg")
    static let cyRatingOkay   = Color("cyRatingOkay")
    static let cyRatingOkayBg = Color("cyRatingOkayBg")
    static let cyRatingGood   = Color("cyRatingGood")
    static let cyRatingGoodBg = Color("cyRatingGoodBg")

    // MARK: Heart Rate Zones
    static let cyHRZone1 = Color("cyHRZone1")  // Recovery   — light blue
    static let cyHRZone2 = Color("cyHRZone2")  // Endurance  — blue
    static let cyHRZone3 = Color("cyHRZone3")  // Tempo      — green (= cyPrimary)
    static let cyHRZone4 = Color("cyHRZone4")  // Threshold  — orange
    static let cyHRZone5 = Color("cyHRZone5")  // VO₂ Max    — red

    // MARK: System
    static let cyDestructive = Color("cyDestructive")
    static let cyInfo        = Color("cyInfo")
}

// MARK: - Semantic Helpers

extension Color {
    /// HR zone colour for zone 1–5. Returns cyTextTertiary for out-of-range values.
    static func hrZone(_ zone: Int) -> Color {
        switch zone {
        case 1: return .cyHRZone1
        case 2: return .cyHRZone2
        case 3: return .cyHRZone3
        case 4: return .cyHRZone4
        case 5: return .cyHRZone5
        default: return .cyTextTertiary
        }
    }

    /// Foreground rating colour for a normalised score (0.0–1.0).
    static func rating(score: Double) -> Color {
        score < 0.33 ? .cyRatingBad : score < 0.66 ? .cyRatingOkay : .cyRatingGood
    }

    /// Background tint for a normalised score (0.0–1.0).
    static func ratingBackground(score: Double) -> Color {
        score < 0.33 ? .cyRatingBadBg : score < 0.66 ? .cyRatingOkayBg : .cyRatingGoodBg
    }
}
