import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// The `Documents/` layout, which `UIFileSharingEnabled` puts on show as *On My iPhone →
/// Cyclometer*: what the app creates there, and what it clears out.
enum DocumentFolders {
    /// `Rides` receives each ride's GPX export. Created at startup so the folder is there
    /// from first launch rather than appearing the first time a ride is exported.
    ///
    /// `GPXExporter.write` still creates it itself: it writes into an overridable directory
    /// that startup never touched, and must not depend on having been run first.
    static let names = ["Rides"]

    /// Failure is logged, not thrown: a folder the app could not create is a degraded Files
    /// listing, and the real write path creates what it needs on demand anyway.
    static func create(in documentsDirectory: URL = .documentsDirectory) {
        for name in names {
            let url = documentsDirectory.appending(component: name, directoryHint: .isDirectory)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                logger.error("could not create Documents/\(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Inbox

    /// `LSSupportsOpeningDocumentsInPlace` covers file providers only. A `.gpx` arriving from
    /// Mail, AirDrop or a share sheet is *copied* into `Documents/Inbox/` instead, and iOS
    /// never removes that copy — which, since `Documents/` is browsable, would leave the rider
    /// an ever-growing Inbox folder of duplicates beside the `Rides` folder above.
    static func isInboxCopy(_ url: URL, documentsDirectory: URL = .documentsDirectory) -> Bool {
        url.isFileURL
            && url.deletingLastPathComponent().standardizedFileURL
            == documentsDirectory.appending(component: "Inbox", directoryHint: .isDirectory).standardizedFileURL
    }

    /// Called once the import has finished reading the file, on failure as much as on success:
    /// a copy the parser rejected is no more use to the rider than one it accepted. Anything
    /// outside the Inbox is left alone — a file the rider picked in place is theirs.
    static func discardInboxCopy(at url: URL, documentsDirectory: URL = .documentsDirectory) {
        guard isInboxCopy(url, documentsDirectory: documentsDirectory) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("could not discard the Inbox copy: \(error.localizedDescription, privacy: .public)")
        }
    }
}
