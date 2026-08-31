import SwiftUI
import SwiftData
import ComposableArchitecture

@main
struct CyclometerApp: App {
    init() {
        AppFonts.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
        .modelContainer(SwiftDataStack.shared.container)
    }
}
