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
        /// Row distances follow the S12 units picker, the same read-through
        /// `RoutesFeature.State.unitSystem` does.
        @Shared(.appPreferences) var preferences

        var rides: [RideListSummary] = []

        /// False until the first read comes back — same reason as
        /// `RoutesFeature.State.hasLoaded`: without it, the empty state briefly claims
        /// "No Rides Yet" on every launch before `.task`'s first read lands.
        var hasLoaded = false

        var unitSystem: UnitSystem { preferences.preferredUnit }
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
        /// Renders the map thumbnail of any finished ride without one (#177), then reloads
        /// the list if one landed (#248). Sent by `rideFinished` once its poll ends.
        case captureMapThumbnails
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
            //
            // Then the ride's map thumbnail: once the ride is visible, its finalize has
            // landed, so it's the newest ride without one. Handed to its own action rather
            // than run here — see `captureMapThumbnails`.
            case .rideFinished(let id):
                return .run { [persistenceClient, clock] send in
                    for attempt in 0..<10 {
                        let rides = (try? await persistenceClient.fetchRides()) ?? []
                        if rides.contains(where: { $0.id == id }) || attempt == 9 {
                            await send(.ridesResponse(.success(rides)))
                            await send(.captureMapThumbnails)
                            return
                        }
                        try? await clock.sleep(for: .milliseconds(200))
                    }
                }
                .cancellable(id: CancelID.reload, cancelInFlight: true)

            // Captured here rather than at the end of `ActiveRideFeature`'s finish effect
            // (#177) so the list can reload once the image lands (#248) — the row is
            // already on screen by then, showing the placeholder. Deliberately not under
            // `CancelID.reload`: a delete or a reload in the seconds after a Finish would
            // otherwise cancel a render in flight and leave the image to the next launch.
            // Only finalized rides are picked, so it's harmless after a poll that gave up.
            case .captureMapThumbnails:
                return .run { send in
                    if await RideMapThumbnail.backfill() > 0 {
                        await send(.reloadRides)
                    }
                }

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
