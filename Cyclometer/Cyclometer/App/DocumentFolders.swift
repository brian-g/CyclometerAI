import Foundation
import os

private let logger = Logger.cyclometer(.persistence)

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

    // MARK: - Ride exports

    /// Deletes the exports in `Rides` that no ride references (#346). Deleting a ride removes
    /// its file first and carries on if that fails (#261), so a file can outlive its rows; this
    /// is what eventually clears it.
    ///
    /// Only the app's own exports are candidates: `.gpx` files in `Rides` itself, named by
    /// `GPXExporter`. Anything else there was put in through Files and is the rider's.
    ///
    /// The folder is listed *before* `referencedFileNames` is read, so a file written after the
    /// listing is never a candidate. One written before it is kept once its ride-end marker or
    /// row names it, which the ride-end sequence does straight after the write.
    ///
    /// Failure is logged, not thrown: an orphan left for the next launch costs nothing.
    static func sweepOrphanedRideExports(
        documentsDirectory: URL = .documentsDirectory,
        referencedFileNames: () async throws -> Set<String>
    ) async {
        let ridesDirectory = documentsDirectory.appending(component: "Rides", directoryHint: .isDirectory)
        let exports: [URL]
        do {
            exports = try FileManager.default
                .contentsOfDirectory(at: ridesDirectory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { url in
                    url.pathExtension == "gpx"
                        && url.lastPathComponent.hasPrefix(GPXExporter.filenamePrefix)
                        && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                }
        } catch CocoaError.fileReadNoSuchFile {
            return // Nothing exported yet.
        } catch {
            logger.error("export sweep could not list Documents/Rides: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !exports.isEmpty else { return }

        let referenced: Set<String>
        do {
            referenced = try await referencedFileNames()
        } catch {
            // Without the references every export looks orphaned, so nothing is removed.
            logger.error("export sweep skipped, references unreadable: \(error.localizedDescription, privacy: .public)")
            return
        }
        for url in exports where !referenced.contains(url.lastPathComponent) {
            do {
                try FileManager.default.removeItem(at: url)
                logger.notice("export sweep removed orphan \(url.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("export sweep could not remove \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
