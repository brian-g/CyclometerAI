import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// `UIFileSharingEnabled` puts `Documents/` on show as *On My iPhone → Cyclometer*, so the
/// two folders the app files things under exist from first launch rather than appearing the
/// first time a ride is exported — an empty Cyclometer folder gives a rider nowhere obvious
/// to drop a `.gpx`, and nowhere to look for one.
///
/// `GPXExporter.write` still creates `Rides/` itself: it writes into an overridable
/// directory that startup never touched, and must not depend on having been run first.
enum DocumentFolders {
    /// `Rides` receives each ride's GPX export; `Routes` is where a rider drops the `.gpx`
    /// files they intend to import.
    static let names = ["Rides", "Routes"]

    /// Failure is logged, not thrown: a folder the app could not create is a degraded Files
    /// listing, and both real write paths create what they need on demand anyway.
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
}
