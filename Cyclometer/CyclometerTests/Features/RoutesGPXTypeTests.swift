import Testing
import UniformTypeIdentifiers
@testable import Cyclometer

/// The Files picker in S19 filters on `com.topografix.gpx`, and iOS only knows that
/// identifier because the app declares it in `Info.plist` under
/// `UTImportedTypeDeclarations` (#193).
///
/// Worth a test because deleting that declaration breaks the import flow *silently*:
/// `UTType(filenameExtension:)` still returns a type, just a dynamic one conforming to
/// nothing, so the picker compiles, runs, and shows every `.gpx` greyed out.
@Suite("Routes GPX content type")
struct RoutesGPXTypeTests {

    @Test("The app declares com.topografix.gpx")
    func identifierResolves() {
        let gpx = UTType("com.topografix.gpx")
        #expect(gpx != nil)
        #expect(gpx?.isDynamic == false)
    }

    @Test("A .gpx filename resolves to that declared type, not a dynamic one")
    func extensionResolvesToTheDeclaredType() {
        let gpx = UTType(filenameExtension: "gpx")
        #expect(gpx?.identifier == "com.topografix.gpx")
        #expect(gpx?.isDynamic == false)
    }

    /// Conformance to `public.xml` is what lets a file exported as generic XML, or offered
    /// by a provider that only knows it is XML, still be picked.
    @Test("The declared type conforms to XML")
    func conformsToXML() {
        #expect(UTType("com.topografix.gpx")?.conforms(to: .xml) == true)
    }
}
