import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

/// Shared body for every SwiftData write in `RidePersistenceActor` and
/// `RoutePersistenceActor`: run `changes` (insert/delete/mutate, no save), save the
/// context once, and log-then-rethrow under one label on failure.
///
/// One definition rather than one per actor. The two were byte-identical, down to the
/// privacy annotations, so a change to the log format or the save semantics would have
/// had to be made twice — and applying it to only one would quietly leave the two actors
/// handling failure differently.
///
/// Takes the context rather than being a protocol extension so the actor's isolation
/// stays at the call site, where it is visible.
func savingChanges(
    _ label: String,
    id: UUID,
    context: ModelContext,
    _ changes: () throws -> Void
) throws {
    do {
        try changes()
        try context.save()
    } catch {
        logger.error("\(label, privacy: .public)(\(id, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        throw error
    }
}
