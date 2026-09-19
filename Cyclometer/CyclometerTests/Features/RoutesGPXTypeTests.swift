import Testing
import UniformTypeIdentifiers
@testable import Cyclometer

/// Two separate things, both easy to break silently.
///
/// The `UTImportedTypeDeclarations` entry in `Info.plist` (#193) is what makes
/// `com.topografix.gpx` a real identifier on this device. The S19 picker no longer filters
/// on it — see `RoutesView.gpxContentTypes` — but `CFBundleDocumentTypes` still names it in
/// `LSItemContentTypes`, so deleting the declaration would leave the app claiming a type
/// nothing resolves, and "Open in Cyclometer" would quietly stop being offered.
///
/// The filter is the other half: it has to admit whatever the provider hands over, which is
/// the failure this suite exists to prevent recurring.
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
    /// provider typed as plain `public.xml`, or as a `dyn.*` type — which is how a fresh
    /// install came to grey out every `.gpx` already in iCloud Drive. Naming the GPX type in
    /// the filter is exactly what broke, so the assertion is that nothing is excluded.
    @Test("The filter admits every file type, however the provider typed it")
    func filterAdmitsEveryFileType() {
        let dynamic = UTType(filenameExtension: "cyclometer-not-a-real-extension")!
        for type: UTType in [UTType("com.topografix.gpx")!, .xml, .plainText, .jpeg, dynamic] {
            #expect(type.conforms(toAnyOf: RoutesView.gpxContentTypes),
                    "\(type.identifier) would be greyed out")
        }
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
