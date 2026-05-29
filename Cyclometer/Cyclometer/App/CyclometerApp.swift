import SwiftUI
import SwiftData
import ComposableArchitecture

@main
struct CyclometerApp: App {
    init() {
        AppFonts.registerFonts()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
        .modelContainer(sharedModelContainer)
    }
}
