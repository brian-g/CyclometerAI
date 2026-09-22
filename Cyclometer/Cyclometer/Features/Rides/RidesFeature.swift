import ComposableArchitecture
import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

extension PersistenceClient {
    /// `fetchRides`, logged and reduced to the rider-facing `PersistenceFailure` — mirrors
    /// `loadRoutes` (`RouteLibrary.swift`). One consumer (this tab), so it lives here rather
    /// than in a shared library file.
    func loadRides() async -> Result<[RideListSummary], PersistenceFailure> {
        do {
            return .success(try await fetchRides())
        } catch {
            logger.error("fetchRides failed: \(error.localizedDescription, privacy: .public)")
            return .failure(PersistenceFailure())
        }
    }
}

@Reducer
struct RidesFeature {
    @ObservableState
    struct State: Equatable {
        var rides: [RideListSummary] = []

        /// False until the first read comes back — same reason as
        /// `RoutesFeature.State.hasLoaded`: without it, the empty state briefly claims
        /// "No Rides Yet" on every launch before `.task`'s first read lands.
        var hasLoaded = false
    }

    enum Action: Equatable {
        case task
        case reloadRides
        case ridesResponse(Result<[RideListSummary], PersistenceFailure>)
        case deleteRecordedRide(UUID)
        case deleteFailed
    }

    @Dependency(\.persistenceClient) var persistenceClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .send(.reloadRides)

            case .reloadRides:
                return .run { send in
                    await send(.ridesResponse(await persistenceClient.loadRides()))
                }

            case .ridesResponse(.success(let rides)):
                state.hasLoaded = true
                state.rides = rides
                return .none

            case .ridesResponse(.failure):
                state.hasLoaded = true
                return .none

            // Optimistic, mirroring `RoutesFeature.deleteButtonTapped`: a swiped row that
            // lingers while SwiftData saves reads as a gesture that didn't take.
            case .deleteRecordedRide(let id):
                state.rides.removeAll { $0.id == id }
                return .run { [persistenceClient] send in
                    do {
                        try await persistenceClient.deleteRide(id)
                    } catch {
                        logger.error("deleteRide failed: \(error.localizedDescription, privacy: .public)")
                        await send(.deleteFailed)
                    }
                }

            // No alert in this screen's design (unchanged from #261) — resync from the
            // store, which is the authority on what survived the failed write.
            case .deleteFailed:
                return .send(.reloadRides)
            }
        }
    }
}
