import SwiftData
import Foundation

/// SwiftData stack — low-frequency Ride summary and VehiclePassEvent records (and,
/// later, RadarEvent / UserProfile). High-frequency time-series data lives in
/// CoreDataStack (NSBatchInsertRequest).
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    let container: ModelContainer

    private init() {
        container = Self.makeContainer(inMemory: false)
    }

    #if DEBUG
    /// Test-only: an isolated, ephemeral store instead of `.shared`'s. Unlike
    /// CoreDataStack's inMemory init (SQLite pointed at /dev/null, needed because
    /// NSBatchInsertRequest requires a real store type), SwiftData's own
    /// isStoredInMemoryOnly works fine here — Ride writes go through plain
    /// ModelContext.save(), not a SQL batch request.
    init(inMemory: Bool) {
        container = Self.makeContainer(inMemory: inMemory)
    }
    #endif

    private static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([Ride.self, VehiclePassEvent.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }
}
