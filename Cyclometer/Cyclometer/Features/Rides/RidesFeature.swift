import ComposableArchitecture
import Foundation
import SwiftData
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "persistence")

extension PersistenceClient {
    /// `fetchRides`, reduced to the rider-facing `PersistenceFailure` — mirrors `loadRoutes`
    /// (`RouteLibrary.swift`). No log here: `RidePersistenceActor.fetchRides()` already logs
    /// the failure before rethrowing, and a second line under the same category would read
    /// as two failures for one root cause. One consumer (this tab), so this lives here
    /// rather than in a shared library file.
    func loadRides() async -> Result<[RideListSummary], PersistenceFailure> {
        do {
            return .success(try await fetchRides())
        } catch {
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
        /// A ride just ended, from `AppFeature`'s ride-end seam (#247 follow-up). Not a
        /// plain `reloadRides`: `ActiveRideFeature`'s own finish effect (flush → GPX
        /// export → `finalizeRide`) is a separate, unsequenced effect, so a same-instant
        /// reload usually wins the race and reads a snapshot that still excludes the ride
        /// that just ended.
        case rideFinished(UUID)
        case deleteRecordedRide(UUID)
        case deleteFailed
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case reload }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                return .send(.reloadRides)

            case .reloadRides:
                return .run { send in
                    await send(.ridesResponse(await persistenceClient.loadRides()))
                }
                .cancellable(id: CancelID.reload, cancelInFlight: true)

            case .ridesResponse(.success(let rides)):
                state.hasLoaded = true
                state.rides = rides
                return .none

            case .ridesResponse(.failure):
                state.hasLoaded = true
                return .none

            // Bounded poll rather than one read: `finalizeRide` isn't sequenced with
            // this action (see the case's doc comment), so the write may still be in
            // flight. Ten tries at 200ms is a 2s ceiling — comfortably past a real
            // GPX export — after which the last read wins even if it still misses it;
            // nothing here can wait forever on a write that never lands.
            case .rideFinished(let id):
                return .run { [persistenceClient, clock] send in
                    for attempt in 0..<10 {
                        let rides = (try? await persistenceClient.fetchRides()) ?? []
                        if rides.contains(where: { $0.id == id }) || attempt == 9 {
                            await send(.ridesResponse(.success(rides)))
                            return
                        }
                        try? await clock.sleep(for: .milliseconds(200))
                    }
                }
                .cancellable(id: CancelID.reload, cancelInFlight: true)

            // Optimistic, mirroring `RoutesFeature.deleteButtonTapped`: a swiped row that
            // lingers while SwiftData saves reads as a gesture that didn't take. Cancels
            // any in-flight reload/rideFinished poll first — one of those landing after
            // this optimistic removal would otherwise resurrect the row it just dropped.
            case .deleteRecordedRide(let id):
                state.rides.removeAll { $0.id == id }
                return .merge(
                    .cancel(id: CancelID.reload),
                    .run { [persistenceClient] send in
                        do {
                            try await persistenceClient.deleteRide(id)
                        } catch {
                            logger.error("deleteRide failed: \(error.localizedDescription, privacy: .public)")
                            await send(.deleteFailed)
                        }
                    }
                )

            // No alert in this screen's design (unchanged from #261) — resync from the
            // store, which is the authority on what survived the failed write.
            case .deleteFailed:
                return .send(.reloadRides)
            }
        }
    }
}
