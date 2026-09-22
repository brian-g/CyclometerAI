import ComposableArchitecture
import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

@Reducer
struct RidesFeature {
    @ObservableState
    struct State: Equatable {
        var demoRides: [DemoRide] = DemoRide.sampleRides
    }

    enum Action {
        case deleteDemoRide(UUID)
        case deleteRecordedRide(UUID)
    }

    @Dependency(\.persistenceClient) var persistenceClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .deleteDemoRide(let id):
                state.demoRides.removeAll { $0.id == id }
                return .none

            // Nothing to remove from state: the list's recorded half is an
            // `@Query` over SwiftData (`AppView`), which drops the row once this
            // lands. The whole job is telling persistence to let go of everything
            // the ride owns — the GPX file and the track points included (#261).
            case .deleteRecordedRide(let id):
                return .run { [persistenceClient] _ in
                    try await persistenceClient.deleteRide(id)
                } catch: { error, _ in
                    logger.error("deleteRide failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
