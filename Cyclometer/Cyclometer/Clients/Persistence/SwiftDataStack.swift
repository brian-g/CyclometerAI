import SwiftData
import Foundation

/// SwiftData stack — ride summaries, user profile, settings metadata.
/// High-frequency time-series data lives in CoreDataStack (NSBatchInsertRequest).
@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            // TODO: RideSummary.self, UserProfile.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }
}
