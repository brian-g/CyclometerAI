import Foundation
import Testing
@testable import Cyclometer

/// `Documents/` is browsable as *On My iPhone → Cyclometer*, so what the app leaves there is
/// something the rider sees.
@Suite("Document folders")
struct DocumentFoldersTests {

    /// A throwaway stand-in for the app's `Documents/`.
    private func makeDocumentsDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(component: "DocumentFoldersTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Creates Rides")
    func createsRides() throws {
        let root = try makeDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        DocumentFolders.create(in: root)

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: root.appending(component: "Rides").path, isDirectory: &isDirectory
        )
        #expect(exists, "Rides was not created")
        #expect(isDirectory.boolValue, "Rides is not a directory")
    }

    /// Startup runs on every launch, so the second one must not throw or clear anything.
    @Test("Running twice is harmless")
    func isIdempotent() throws {
        let root = try makeDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        DocumentFolders.create(in: root)
        let marker = root.appending(component: "Rides").appending(component: "keep.gpx")
        try Data().write(to: marker)

        DocumentFolders.create(in: root)

        #expect(FileManager.default.fileExists(atPath: marker.path), "re-running wiped existing contents")
    }

    // MARK: - Inbox

    /// A `.gpx` from Mail or AirDrop is copied into `Documents/Inbox/` and iOS never removes
    /// the copy, so without this the rider accumulates duplicates next to `Rides`.
    @Test("Discards a copy in the Inbox")
    func discardsInboxCopy() throws {
        let root = try makeDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appending(component: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let copy = inbox.appending(component: "Route.gpx")
        try Data().write(to: copy)

        DocumentFolders.discardInboxCopy(at: copy, documentsDirectory: root)

        #expect(FileManager.default.fileExists(atPath: copy.path) == false)
    }

    /// A file the rider picked in place is theirs — deleting it would delete out of their
    /// iCloud Drive. Only the app's own copy is the app's to remove.
    @Test("Leaves a file outside the Inbox alone")
    func keepsFilesOutsideTheInbox() throws {
        let root = try makeDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = root.appending(component: "Route.gpx")
        try Data().write(to: elsewhere)
        let nested = try makeDocumentsDirectory().appending(component: "Inbox", directoryHint: .isDirectory)

        DocumentFolders.discardInboxCopy(at: elsewhere, documentsDirectory: root)
        // Another container's Inbox is not this one's.
        #expect(DocumentFolders.isInboxCopy(nested.appending(component: "Route.gpx"), documentsDirectory: root) == false)

        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    /// The `Rides` folder sits beside the Inbox, and a GPX export must never be mistaken for
    /// one of its copies.
    @Test("An exported ride is not an Inbox copy")
    func exportIsNotAnInboxCopy() throws {
        let root = try makeDocumentsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let export = root.appending(component: "Rides").appending(component: "Cyclometer_2026-09-19_11-48.gpx")

        #expect(DocumentFolders.isInboxCopy(export, documentsDirectory: root) == false)
    }
}
