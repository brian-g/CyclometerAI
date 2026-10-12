import Testing
import SwiftUI
import UIKit
@testable import Cyclometer

/// #309 — the Live Activity's text passes WCAG AA (4.5:1) on its card over any wallpaper. The card,
/// `RideLockScreenView.card`, is translucent, so the worst case is the wallpaper furthest from the
/// text: white under dark mode's light text, black under light mode's dark text. The Always-On
/// display takes the dark card and white text in either appearance. Lowering
/// `Opacity.liveActivityCard` until this fails is the point of the test.
@Suite("Live Activity contrast")
struct LiveActivityContrastTests {

    static let wcagAA = 4.5

    @Test(arguments: [
        (UIUserInterfaceStyle.dark, false, UIColor.white),
        (UIUserInterfaceStyle.light, false, UIColor.black),
        (UIUserInterfaceStyle.light, true, UIColor.white)
    ])
    func textPassesAAOnWorstCaseWallpaper(style: UIUserInterfaceStyle, isLuminanceReduced: Bool,
                                          wallpaper: UIColor) {
        let card = UIColor(RideLockScreenView.card(colorScheme: style == .dark ? .dark : .light,
                                                    isLuminanceReduced: isLuminanceReduced))
        let backdrop = Self.composite(card, over: wallpaper)
        // The view switches its text to dark on the Always-On display, as the card does.
        let traits = UITraitCollection(userInterfaceStyle: isLuminanceReduced ? .dark : style)

        for token in [ColorResource.cyTextPrimary, .cyTextSecondary] {
            let text = UIColor(resource: token).resolvedColor(with: traits)
            let ratio = Self.contrast(text, backdrop)
            #expect(ratio >= Self.wcagAA, "\(token) \(style.rawValue) reduced \(isLuminanceReduced): \(ratio):1")
        }
    }

    // MARK: - WCAG 2.x

    /// `top` over `bottom` by `top`'s own alpha.
    private static func composite(_ top: UIColor, over bottom: UIColor) -> UIColor {
        let t = rgb(top), b = rgb(bottom)
        func mix(_ x: Double, _ y: Double) -> Double { x * t.a + y * (1 - t.a) }
        return UIColor(red: mix(t.r, b.r), green: mix(t.g, b.g), blue: mix(t.b, b.b), alpha: 1)
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = rgb(color)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private static func rgb(_ color: UIColor) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
