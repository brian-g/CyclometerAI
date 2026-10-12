import CoreText
import Foundation
import SwiftUI

// MARK: - Font Registration

struct AppFonts {
    static let dDINCondensedPostScriptName = "D-DINCondensed"

    static func registerFonts() {
        registerFont(named: "D-DINCondensed", extension: "otf")
    }

    private static func registerFont(named name: String, extension fileExtension: String) {
        guard let fontURL = fontURL(named: name, extension: fileExtension) else {
            print("Unable to find font resource: \(name).\(fileExtension)")
            return
        }

        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) else {
            let nsError = error?.takeRetainedValue() as Error?
            let alreadyRegisteredCode = CTFontManagerError.alreadyRegistered.rawValue

            if (nsError as NSError?)?.code != alreadyRegisteredCode {
                print("Unable to register font \(name): \(nsError?.localizedDescription ?? "Unknown error")")
            }
            return
        }
    }

    private static func fontURL(named name: String, extension fileExtension: String) -> URL? {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Fonts") {
                return url
            }
        }
        return nil
    }
}

private final class BundleToken { }

// MARK: - Font Extension

extension Font {
    static func dDINCondensed(size: CGFloat, relativeTo textStyle: TextStyle = .body) -> Font {
        .custom(AppFonts.dDINCondensedPostScriptName, size: size, relativeTo: textStyle)
    }
}

// MARK: - Tracking Constants

extension AppFonts {
    /// Negative tracking applied to D-DIN Condensed at display sizes (≥50pt).
    static let dDINCondensedTracking: CGFloat = -4.0
    static let dDINCondensedTrackingMinSize: CGFloat = 50
}

// MARK: - Digit Metrics

extension AppFonts {
    /// Without D-DIN, SwiftUI draws the system font, so that's the one to measure.
    private static let dDINMetricsFont = UIFont(name: dDINCondensedPostScriptName, size: 100)
        ?? .systemFont(ofSize: 100)

    /// D-DIN's cap height as a share of its ascent: where the digits' tops sit between a hero's
    /// top and its baseline, at any size.
    fileprivate static let dDINCapHeightToAscent = dDINMetricsFont.capHeight / dDINMetricsFont.ascender

    /// D-DIN's cap height as a share of its line: the digits' height from a hero's rendered height.
    fileprivate static let dDINCapHeightToLineHeight = dDINMetricsFont.capHeight
        / (dDINMetricsFont.ascender - dDINMetricsFont.descender)
}

private extension VerticalAlignment {
    /// The tops of a D-DIN hero's digits.
    enum DDINCapTop: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let dDINCapTop = VerticalAlignment(DDINCapTop.self)
}

extension View {
    /// Draws `accessory` right of this D-DIN text, level with the tops of its digits, and hands it
    /// the digits' height to size itself from (#81, #402). An overlay, so nothing beside the text
    /// moves. Apply it to the `Text` itself, after any `minimumScaleFactor` and before any fixed
    /// frame.
    func dDINCapAccessory<A: View>(@ViewBuilder _ accessory: @escaping (_ capHeight: CGFloat) -> A) -> some View {
        modifier(DDINCapAccessory(accessory: accessory))
    }
}

private struct DDINCapAccessory<A: View>: ViewModifier {
    let accessory: (CGFloat) -> A

    /// The text's rendered height. The digits' height comes from it, not from Dynamic Type: a hero
    /// held to its slot's height stops growing, and a text-styled glyph would outgrow it.
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // From the rendered baseline, so it holds when `minimumScaleFactor` shrinks the text.
            .alignmentGuide(.dDINCapTop) { $0[.firstTextBaseline] * (1 - AppFonts.dDINCapHeightToAscent) }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .dDINCapTop)) {
                accessory(height * AppFonts.dDINCapHeightToLineHeight)
                    .alignmentGuide(.trailing) { $0[.leading] - Spacing.xs }
            }
    }
}

// MARK: - View Modifier

extension View {
    /// Applies D-DIN Condensed at the given point size with appropriate tracking.
    func dDINCondensed(size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> some View {
        let tracking: CGFloat = size >= AppFonts.dDINCondensedTrackingMinSize
            ? AppFonts.dDINCondensedTracking
            : 0
        return self
            .font(.dDINCondensed(size: size, relativeTo: textStyle))
            .fontDesign(nil)
            .tracking(tracking)
    }
}
