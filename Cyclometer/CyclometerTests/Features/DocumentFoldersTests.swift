import Foundation
import Testing
@testable import Cyclometer

/// Both folders have to exist before anything writes to them — `Rides` would otherwise
/// appear only after the first ride export, and `Routes` never, since nothing writes there.
@Suite("Document folders")
struct DocumentFoldersTests {

    @Test("Creates Rides and Routes")
    func createsBothFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "DocumentFoldersTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        DocumentFolders.create(in: root)

        for name in ["Rides", "Routes"] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appending(component: name).path, isDirectory: &isDirectory
            )
            #expect(exists, "\(name) was not created")
            #expect(isDirectory.boolValue, "\(name) is not a directory")
        }
    }

    /// Startup runs on every launch, so the second one must not log an error or throw.
    @Test("Running twice is harmless")
    func isIdempotent() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "DocumentFoldersTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        DocumentFolders.create(in: root)
        let marker = root.appending(component: "Routes").appending(component: "keep.gpx")
        try Data().write(to: marker)

        DocumentFolders.create(in: root)

        #expect(FileManager.default.fileExists(atPath: marker.path), "re-running wiped existing contents")
    }
}
