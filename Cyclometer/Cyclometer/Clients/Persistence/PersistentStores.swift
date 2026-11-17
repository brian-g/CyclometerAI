import ComposableArchitecture
import CoreData
import Foundation
import SwiftData
import os

private let logger = Logger.cyclometer(.persistence)

// MARK: - Status

/// A store that would not open at launch (#206): a migration it refused, a corrupt file, a full
/// disk. The app runs on an in-memory stand-in instead, and the file stays where it was until the
/// rider resets. So a disk that is cleared, or a later build that can migrate it, opens it again
/// at the next launch with nothing lost.
struct StoreFailure: Equatable, Sendable {
    /// Where the store that failed lives, and where a reset opens the fresh one.
    let storeURL: URL
    /// The error, for the log and for diagnosis. Never shown to the rider.
    let reason: String
}

/// Which of the two stores is running on its stand-in. They fail separately and cost the
/// rider different things, so they are reported separately.
struct PersistentStoreStatus: Equatable, Sendable {
    /// SwiftData: the ride list and saved routes.
    var history: StoreFailure?
    /// CoreData: the recorded track of every past ride, behind S15's map, charts and stats.
    var tracks: StoreFailure?

    static let available = PersistentStoreStatus()

    var isDegraded: Bool { history != nil || tracks != nil }
}

/// What a reset did: the files it moved aside, so the rider can be told where their old
/// history went, and how the stores stand afterwards. A store that fails again on reopening
/// (a disk still full) is still reported as unavailable.
struct PersistentStoreReset: Equatable, Sendable {
    var preservedStores: [URL]
    var status: PersistentStoreStatus
}

extension SharedKey where Self == InMemoryKey<PersistentStoreStatus>.Default {
    /// The stores' status as S14 and S19 show it (#206). `AppFeature` writes it at launch and
    /// after a reset. In memory: it is read again from the stores each launch.
    static var persistentStoreStatus: Self {
        Self[.inMemory("persistentStoreStatus"), default: .available]
    }
}

// MARK: - The stores behind PersistenceClient

/// The live client's stores, and the actors working on them, behind one lock so a reset can
/// replace them in place without a relaunch (#206). Every client call reads the current set
/// once and then runs on it. A call already running when a reset lands finishes on the
/// stand-in it started on.
final class PersistentStores: @unchecked Sendable {
    private struct Current {
        var history: SwiftDataStack
        var tracks: CoreDataStack
        var rideActor: RidePersistenceActor
        var routeActor: RoutePersistenceActor

        init(history: SwiftDataStack, tracks: CoreDataStack) {
            self.history = history
            self.tracks = tracks
            rideActor = RidePersistenceActor(modelContainer: history.container)
            routeActor = RoutePersistenceActor(modelContainer: history.container)
        }

        var status: PersistentStoreStatus {
            PersistentStoreStatus(history: history.failure, tracks: tracks.failure)
        }
    }

    private let current: LockIsolated<Current>
    /// Where a reset moves a failed store, and where the retained-exports list lives.
    private let preservedDirectory: URL
    private let retainedExports: RetainedRideExports
    /// The `Documents/` whose `Rides/` exports a reset retains.
    private let documentsDirectory: URL

    init(
        history: SwiftDataStack,
        tracks: CoreDataStack,
        supportDirectory: URL,
        documentsDirectory: URL
    ) {
        current = LockIsolated(Current(history: history, tracks: tracks))
        preservedDirectory = supportDirectory.appending(component: "Preserved Stores", directoryHint: .isDirectory)
        retainedExports = RetainedRideExports(
            fileURL: preservedDirectory.appending(component: "retained-ride-exports.json")
        )
        self.documentsDirectory = documentsDirectory
    }

    var rideActor: RidePersistenceActor { current.value.rideActor }
    var routeActor: RoutePersistenceActor { current.value.routeActor }
    var trackContainer: NSPersistentContainer { current.value.tracks.container }
    var status: PersistentStoreStatus { current.value.status }

    /// The names the #346 launch sweep keeps: every name a `Ride` row holds, plus every
    /// retained export.
    ///
    /// Throws while history is on its stand-in, so the sweep removes nothing. A stand-in names
    /// no rides, and every export would look orphaned. And if the retained list can't be read,
    /// this throws too, rather than letting the sweep go ahead without it. Ride GPX files are
    /// the record that outlives a lost store, so nothing on this path may cost one.
    func gpxFileNamesToKeep() async throws -> Set<String> {
        guard current.value.history.failure == nil else { throw PersistenceError.storeUnavailable }
        let named = try await rideActor.gpxFileNames()
        let retained = try current.withValue { _ in try retainedExports.load() }
        return named.union(retained)
    }

    /// A ride ending while history is on its stand-in still writes its row, but the row goes
    /// when the app does. So its export is retained first. Once the store opens again, the
    /// sweep would otherwise find a file no row names, and remove the only record of the ride.
    /// If that can't be written, the finalize fails, and the ride-end marker keeps naming the
    /// file instead (#188).
    func retainExportIfHistoryUnavailable(_ gpxFileURL: URL?) throws {
        guard let gpxFileURL else { return }
        try current.withValue { current in
            guard current.history.failure != nil else { return }
            try retainedExports.insert([gpxFileURL.lastPathComponent])
        }
    }

    /// Moves each failed store aside under a timestamped name and opens a fresh one where it
    /// was. A store that is open is left alone: the two cost the rider different things, and a
    /// track store that failed is no reason to discard the ride list.
    ///
    /// Before history's store moves, every export in `Documents/Rides/` is retained: the fresh
    /// store names none of them, and the sweep would otherwise remove them all at the next
    /// launch. Any failure on the way stops the reset before the store moves. Nothing is
    /// partly done.
    func resetUnavailableStores(now: Date) throws -> PersistentStoreReset {
        try current.withValue { current in
            var preserved: [URL] = []
            if let failure = current.history.failure {
                try retainedExports.insert(try exportNames())
                if let moved = try PersistentStoreFiles.moveAside(failure.storeURL, into: preservedDirectory, at: now) {
                    preserved.append(moved)
                }
                current = Current(history: current.history.reopened(), tracks: current.tracks)
            }
            if let failure = current.tracks.failure {
                if let moved = try PersistentStoreFiles.moveAside(failure.storeURL, into: preservedDirectory, at: now) {
                    preserved.append(moved)
                }
                current.tracks = current.tracks.reopened()
            }
            logger.notice("store reset preserved \(preserved.map(\.lastPathComponent), privacy: .public)")
            return PersistentStoreReset(preservedStores: preserved, status: current.status)
        }
    }

    /// The app's own exports in `Documents/Rides/`, by name, the files the sweep would
    /// consider. An empty folder, or none at all, is nothing to retain. Anything else unreadable
    /// throws and stops the reset.
    private func exportNames() throws -> [String] {
        let directory = GPXExporter.ridesDirectory(in: documentsDirectory)
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
                .filter(GPXExporter.isExportFileName)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }
}

// MARK: - Retained exports

/// Exports the #346 sweep keeps whether a `Ride` row names them or not (#206). Those are the
/// exports in `Documents/Rides/` when history was reset, and each ride finalized while history
/// was unavailable. Its own file, outside both stores, like the ride-end marker (#188): it has
/// to survive exactly the stores it protects against.
///
/// Entries are never removed. A name whose file the rider has deleted keeps nothing alive.
struct RetainedRideExports: Sendable {
    let fileURL: URL

    /// Empty when the file doesn't exist yet. Throws when it exists and can't be read.
    func load() throws -> Set<String> {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return try JSONDecoder().decode(Set<String>.self, from: data)
    }

    func insert(_ names: some Sequence<String>) throws {
        let updated = try load().union(names)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(updated.sorted()).write(to: fileURL, options: .atomic)
    }
}

// MARK: - Moving a store aside

enum PersistentStoreFiles {
    /// SQLite's companions. A store moved without its write-ahead log loses whatever had not
    /// been checkpointed into the main file yet.
    static let companionSuffixes = ["-wal", "-shm"]

    /// Moves a SQLite store and its companions to `directory` as
    /// `<name>-failed-<yyyyMMdd-HHmmss>.<ext>`, and returns where the store went. Moved, not
    /// copied through SQLite: a corrupt file may not open, and the bytes are what diagnosis
    /// needs. The timestamp is UTC.
    ///
    /// Nil when there is no file at `storeURL`: one that failed for want of disk can have none,
    /// and then there is nothing to preserve. Any companion left behind goes too, so the fresh
    /// store doesn't open onto the old one's log.
    static func moveAside(_ storeURL: URL, into directory: URL, at date: Date) throws -> URL? {
        let fileManager = FileManager.default
        let storeExists = fileManager.fileExists(atPath: storeURL.path(percentEncoded: false))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = storeURL.deletingPathExtension().lastPathComponent
        let ext = storeURL.pathExtension
        let stamp = date.formatted(
            .verbatim(
                "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                timeZone: .gmt,
                calendar: Calendar(identifier: .gregorian)
            )
        )
        let destination = directory.appending(component: "\(stem)-failed-\(stamp)" + (ext.isEmpty ? "" : ".\(ext)"))
        for suffix in [""] + companionSuffixes {
            let source = URL(filePath: storeURL.path(percentEncoded: false) + suffix)
            guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
            try fileManager.moveItem(
                at: source,
                to: URL(filePath: destination.path(percentEncoded: false) + suffix)
            )
        }
        return storeExists ? destination : nil
    }
}
