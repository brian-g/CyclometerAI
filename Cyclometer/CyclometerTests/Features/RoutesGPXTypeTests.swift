import Testing
import UniformTypeIdentifiers
@testable import Cyclometer

/// What the S19 picker will and won't let a rider select.
///
/// The bug this suite exists to prevent recurring: the filter named `com.topografix.gpx`, the
/// identifier the app declares in `UTImportedTypeDeclarations` (#193). iOS 27 declares
/// `public.gpx` itself, a system declaration outranks an imported one, and conformance runs
/// one way — so every `.gpx` on device resolved to a type that didn't conform to the filter
/// and came up greyed out.
///
/// **Nothing here may assert an identifier.** The iOS 27 simulator still binds the extension
/// to `com.topografix.gpx` while the device binds it to `public.gpx`, so an identifier
/// assertion passes here and tells you nothing about the thing that broke. These tests pin
/// the mechanism: whatever *this* install binds `gpx` to is what the filter must admit.
@Suite("Routes GPX content type")
struct RoutesGPXTypeTests {

    /// Still required even though the filter no longer names it: `CFBundleDocumentTypes`
    /// lists it in `LSItemContentTypes`, so without the declaration the app claims a type
    /// nothing resolves and "Open in Cyclometer" quietly stops being offered.
    @Test("The app declares com.topografix.gpx")
    func identifierResolves() {
        let gpx = UTType("com.topografix.gpx")
        #expect(gpx != nil)
        #expect(gpx?.isDynamic == false)
    }

    /// Which identifier it is depends on the install; that some real type owns the extension
    /// does not. A dynamic answer would mean nothing declares `gpx` at all.
    @Test("Something declared owns the .gpx extension")
    func extensionResolvesToADeclaredType() {
        let gpx = UTType(filenameExtension: "gpx")
        #expect(gpx != nil)
        #expect(gpx?.isDynamic == false)
    }

    /// The assertion that would have caught the bug on either platform.
    @Test("The filter admits whatever this install binds .gpx to")
    func filterAdmitsTheExtensionBinding() throws {
        let bound = try #require(UTType(filenameExtension: "gpx"))
        #expect(bound.conforms(toAnyOf: RoutesView.gpxContentTypes),
                "a .gpx typed \(bound.identifier) would be greyed out")
    }

    /// For a provider that got as far as recognising the markup and no further.
    @Test("The filter admits plain XML")
    func filterAdmitsXML() {
        #expect(UTType.xml.conforms(toAnyOf: RoutesView.gpxContentTypes))
    }

    /// The filter is meant to filter again — `.data` was the stopgap while the type the
    /// device resolves was unknown, and it made every photo and video selectable.
    @Test("The filter excludes files that aren't GPX")
    func filterExcludesOtherFiles() {
        for type: UTType in [.jpeg, .mp3, .pdf, .folder] {
            #expect(type.conforms(toAnyOf: RoutesView.gpxContentTypes) == false,
                    "\(type.identifier) should not be selectable")
        }
    }
}

private extension UTType {
    func conforms(toAnyOf others: [UTType]) -> Bool {
        others.contains { conforms(to: $0) }
    }
}
