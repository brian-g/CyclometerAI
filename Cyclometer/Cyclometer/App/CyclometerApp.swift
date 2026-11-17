import SwiftUI
import ComposableArchitecture

@main
struct CyclometerApp: App {
    init() {
        AppFonts.registerFonts()
        DocumentFolders.create()
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
        // No `.modelContainer`: no view reads SwiftData directly (no `@Query`, no
        // `modelContext`). Every read goes through `PersistenceClient`, whose stores a reset
        // can replace (#206), and a scene-wide container would pin the one opened at launch.
    }
}
