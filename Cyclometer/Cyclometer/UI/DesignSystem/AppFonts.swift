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
