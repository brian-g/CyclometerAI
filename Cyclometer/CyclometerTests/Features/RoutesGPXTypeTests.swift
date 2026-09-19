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

    /// The picker asks whether the *file's* type conforms to an allowed one, and that runs
    /// one way: `com.topografix.gpx` conforming to `public.xml` does nothing for a file the
    /// provider typed as plain `public.xml` or as a `dyn.*` type — which is how a fresh
    /// install came to grey out every `.gpx` already in iCloud Drive. So the filter has to
    /// name those two directly; asserting the GPX type's own conformance would pass while
    /// the picker stayed broken.
    @Test("The picker filter admits provider types that don't conform to GPX")
    func filterAdmitsPartlyRecognisedFiles() {
        let allowed = RoutesView.gpxContentTypes
        #expect(allowed.contains(UTType("com.topografix.gpx")!))
        #expect(UTType.xml.conforms(toAnyOf: allowed))
        // A stand-in for the `dyn.*` type a provider hands back for an extension its own
        // LaunchServices database has no binding for — which is what a `.gpx` synced before
        // the app was installed looks like.
        #expect(UTType(filenameExtension: "cyclometer-not-a-real-extension")!.conforms(toAnyOf: allowed))
    }

    /// Folders must stay unselectable, or the picker offers a directory it cannot import.
    @Test("The filter does not admit folders")
    func filterExcludesFolders() {
        #expect(UTType.folder.conforms(toAnyOf: RoutesView.gpxContentTypes) == false)
    }
}

private extension UTType {
    func conforms(toAnyOf others: [UTType]) -> Bool {
        others.contains { conforms(to: $0) }
    }
}
