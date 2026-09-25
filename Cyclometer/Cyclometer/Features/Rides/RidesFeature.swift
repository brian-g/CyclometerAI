import ComposableArchitecture
import Foundation
import SwiftData
import UIKit
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

/// A row's map thumbnail, decoded for both appearances. Decoded once, off the main thread,
/// when the row first shows — never per render (#248).
struct RideThumbnailImages: Equatable, Sendable {
    let light: UIImage
    let dark: UIImage

    /// Both appearances decoded and prepared for display, or nil when either doesn't decode.
    /// Shared by S14, S19 and S05.2's rows (#273).
    static func decode(_ data: RideMapThumbnailData) async -> RideThumbnailImages? {
        guard let light = await UIImage(data: data.light)?.byPreparingForDisplay(),
              let dark = await UIImage(data: data.dark)?.byPreparingForDisplay()
        else { return nil }
        return RideThumbnailImages(light: light, dark: dark)
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

        /// Thumbnails of the rows that have been on screen, by ride id. Absent until a row
        /// first appears, so a long history never reads images nobody scrolled to.
        var thumbnails: [UUID: Thumbnail] = [:]

        /// The tab's navigation stack: S15, pushed from a row (#251) — the same shape as
        /// `RoutesFeature.path`, for the same reason.
        var path = StackState<Path.State>()

        var unitSystem: UnitSystem { preferences.preferredUnit }
    }

    enum Thumbnail: Equatable {
        case loading
        /// No stored image: recorded before #177, no GPS track, or not captured yet.
        case missing
        case loaded(RideThumbnailImages)
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
        /// Renders the map thumbnail of every finished ride without one (#177), once a
        /// Finish's ride is finalized. `AppFeature` runs the same backfill at launch.
        case captureMapThumbnails
        /// A capture stored at least one image; sent here and by `AppFeature`'s launch
        /// backfill.
        case mapThumbnailsCaptured
        case rowAppeared(UUID)
        case thumbnailLoaded(UUID, RideThumbnailImages?)
        case deleteRecordedRide(UUID)
        case deleteFailed
        case path(StackActionOf<Path>)
    }

    /// What the Rides tab can push (#251).
    @Reducer(state: .equatable, action: .equatable)
    enum Path {
        case detail(RideDetailFeature)
    }

    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case reload, awaitFinalize, capture }

    /// How long a Finish waits for its ride's finalize before capturing anyway. Generous:
    /// flush and GPX export scale with the ride's length, and waiting costs one cheap read a
    /// second. Past it the capture still runs and finds nothing new; the launch backfill
    /// then picks the ride up.
    static let finalizeWaitSeconds = 60

    /// Waits for a just-finished ride's `finalizeRide` to land, reading once a second for up to
    /// `finalizeWaitSeconds`. `fetchRides` only returns rides with an `endedAt`, so the ride
    /// appearing there is the finalize having landed. Nil if it never does. Shared with S10
    /// (#249), which must not show the checkpoint aggregates the finalize is about to replace.
    static func awaitFinalized(
        _ id: UUID,
        persistenceClient: PersistenceClient,
        clock: any Clock<Duration>
    ) async throws -> RideListSummary? {
        for _ in 0..<finalizeWaitSeconds {
            let rides = (try? await persistenceClient.fetchRides()) ?? []
            if let ride = rides.first(where: { $0.id == id }) { return ride }
            try await clock.sleep(for: .seconds(1))
        }
        return nil
    }

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

            // Two effects, cancelled differently.
            //
            // The list: a bounded poll rather than one read, because `finalizeRide` may
            // still be in flight (see the case's doc comment). Ten tries at 200ms is a 2s
            // ceiling, after which the last read wins even if it still misses the ride. A
            // read that fails every time is sent as the failure, which keeps the list, rather
            // than as an empty success, which would claim "No Rides Yet". Under
            // `CancelID.reload`, so a delete stops a late read resurrecting its row.
            //
            // The thumbnail: waits for the finalize on its own id, because a delete or a
            // reload in the seconds after a Finish must not cancel it, then captures (#248).
            case .rideFinished(let id):
                return .merge(
                    .run { [persistenceClient, clock] send in
                        for attempt in 0..<10 {
                            let result = await persistenceClient.loadRides()
                            let found = (try? result.get())?.contains(where: { $0.id == id }) ?? false
                            if found || attempt == 9 {
                                await send(.ridesResponse(result))
                                return
                            }
                            try? await clock.sleep(for: .milliseconds(200))
                        }
                    }
                    .cancellable(id: CancelID.reload, cancelInFlight: true),
                    .run { [persistenceClient, clock] send in
                        _ = try await Self.awaitFinalized(id, persistenceClient: persistenceClient, clock: clock)
                        await send(.captureMapThumbnails)
                    }
                    .cancellable(id: CancelID.awaitFinalize, cancelInFlight: true)
                )

            // A second Finish's capture replaces the first's: each run re-reads the whole
            // list of rides missing an image, so the newer covers everything the older
            // would have. Overlap with `AppFeature`'s launch backfill is `backfill`'s own
            // to prevent — it runs one at a time (#248 review).
            case .captureMapThumbnails:
                return .run { send in
                    if await RideMapThumbnail.backfill() > 0 {
                        await send(.mapThumbnailsCaptured)
                    }
                }
                .cancellable(id: CancelID.capture, cancelInFlight: true)

            // Rows on screen with no image take another look. The list itself is unchanged,
            // so it isn't reloaded; rows not yet shown read theirs when they appear.
            case .mapThumbnailsCaptured:
                let missing = state.thumbnails.filter { $0.value == .missing }.map(\.key)
                for id in missing { state.thumbnails[id] = .loading }
                return .merge(missing.map(loadThumbnail))

            case .rowAppeared(let id):
                guard state.thumbnails[id] == nil else { return .none }
                state.thumbnails[id] = .loading
                return loadThumbnail(id)

            case .thumbnailLoaded(let id, let images):
                // The ride may have been deleted while its image was read.
                guard state.thumbnails[id] != nil else { return .none }
                state.thumbnails[id] = images.map(Thumbnail.loaded) ?? .missing
                return .none

            // Optimistic, mirroring `RoutesFeature.deleteButtonTapped`: a swiped row that
            // lingers while SwiftData saves reads as a gesture that didn't take. Cancels
            // any in-flight reload/rideFinished poll first — one of those landing after
            // this optimistic removal would otherwise resurrect the row it just dropped.
            case .deleteRecordedRide(let id):
                state.rides.removeAll { $0.id == id }
                state.thumbnails[id] = nil
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

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }

    /// Reads one ride's stored image and decodes both appearances off the main thread. A
    /// failed read shows as missing; it's logged inside `RidePersistenceActor`.
    private func loadThumbnail(_ id: UUID) -> Effect<Action> {
        .run { [persistenceClient] send in
            guard let data = try? await persistenceClient.fetchRideMapThumbnail(id) else {
                await send(.thumbnailLoaded(id, nil))
                return
            }
            await send(.thumbnailLoaded(id, await RideThumbnailImages.decode(data)))
        }
    }
}
