import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("AppFeature — dashboard / accessory lifecycle")
struct AppFeatureTests {

    /// Minimizing the dashboard hides the cover but keeps the ride alive, so the
    /// accessory strip takes over (S05.3).
    @Test("dashboardDismissed hides cover but keeps the active ride")
    func dashboardDismissedKeepsRide() async {
        let store = TestStore(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(recordingState: .active),
                isDashboardPresented: true
            )
        ) {
            AppFeature()
        }

        await store.send(.dashboardDismissed) {
            $0.isDashboardPresented = false
        }
        // Dropping to the accessory strip also hands the screen back to the system
        // (#110) — see AppScreenPowerTests for what that transition actually does.
        await store.receive(\.screenVisibilityChanged)
        #expect(store.state.activeRide != nil)
    }

    /// Tapping "Open" on the accessory re-presents the full-screen dashboard.
    @Test("dashboardOpened re-presents the dashboard while a ride is active")
    func dashboardOpenedRepresents() async {
        let store = TestStore(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(recordingState: .active),
                isDashboardPresented: false
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.screenClient = .testValue
        }

        await store.send(.dashboardOpened) {
            $0.isDashboardPresented = true
        }
        // Presenting takes the screen (#110), which arms the auto-dim countdown;
        // minimizing again releases it so the countdown doesn't outlive the test.
        await store.receive(\.screenVisibilityChanged)
        await store.send(.dashboardDismissed) {
            $0.isDashboardPresented = false
        }
        await store.receive(\.screenVisibilityChanged)
    }

    /// With no active ride, `dashboardOpened` is a no-op (accessory can't be shown).
    @Test("dashboardOpened is a no-op with no active ride")
    func dashboardOpenedNoRide() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.dashboardOpened)
    }

    /// Regression: the ride's long-running effects (1 Hz timer, HR, radar,
    /// location) are started by AppFeature when the ride begins — bound to
    /// `activeRide` via `.ifLet` — NOT by a dashboard-view `.task`. This is what
    /// keeps the timer running when the dashboard is minimized to the accessory
    /// strip; previously the effects died with the dismissed dashboard view.
    @Test("Ride effects are started at the ride level, not by the dashboard view")
    func rideEffectsStartAtRideLevel() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()   // timer suspends; cancelled on finish
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
        }
        store.exhaustivity = .off

        // Begin a ride via the start-sheet delegate. No dashboard cover / accessory
        // view is ever instantiated in this test — yet the ride still starts its
        // effects, because AppFeature emits `.task` itself.
        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        await store.receive(\.activeRide.task)
        #expect(store.state.activeRide?.recordingState == .active)

        // Finish via the real flow (pause → confirm) so the finish alert is
        // actually presented; this tears every ride effect down (activeRide → nil
        // via .ifLet) and lets the store settle cleanly.
        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        await store.finish()
        #expect(store.state.activeRide == nil)
    }

    /// #175: `.task` discovers a Ride a kill left behind and resumes it — the
    /// `AppFeature`-level wiring companion to `ActiveRideFeatureTests`'
    /// `State(resuming:)` tests and `RideRecordingTests.killAndRelaunchResumesRide`,
    /// neither of which exercises this reducer.
    @Test("task discovers a resumable ride and presents the dashboard")
    func taskDiscoversResumableRide() async {
        let summary = RideSummaryUpdate(
            rideId: UUID(), recordingState: .active,
            durationSeconds: 120, distanceMeters: 800, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = TestClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleCSCClient = .testValue
            $0.variaRadarClient = .testValue
            $0.bleHRClient = .testValue
            $0.screenClient = .testValue
            $0.hapticsClient = .testValue
            $0.locationClient = .testValue
            $0.persistenceClient = .mock(resumableRide: summary)
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.receive(\.resumableRideFetched)
        #expect(store.state.activeRide?.rideId == summary.rideId)
        #expect(store.state.activeRide?.recordingState == .active)
        #expect(store.state.isDashboardPresented == true)
        #expect(store.state.selectedTab == .rides)
        await store.receive(\.activeRide.task)
    }

    /// #175 review: `.task`'s BLE-pairing push and resumable-ride fetch race —
    /// the rider can start a brand-new ride through the normal start-sheet flow
    /// before the async fetch resolves. The already-started ride must not be
    /// clobbered, and the orphaned resumed ride must still get closed out
    /// rather than staying a phantom non-`.ended` row forever.
    @Test("resumableRideFetched finalizes an orphaned ride instead of clobbering one already started")
    func resumableRideFetchedDoesNotClobberANewlyStartedRide() async {
        let orphanedRideId = UUID()
        let newRideId = UUID()
        let orphanedSummary = RideSummaryUpdate(
            rideId: orphanedRideId, recordingState: .active,
            durationSeconds: 300, distanceMeters: 2_000, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
        let finalized = LockIsolated<(UUID, Date, RideSummaryUpdate, URL?)?>(nil)
        let fixedDate = Date(timeIntervalSince1970: 2_000_000)
        let store = TestStore(
            initialState: AppFeature.State(
                activeRide: ActiveRideFeature.State(rideId: newRideId, recordingState: .active),
                isDashboardPresented: true
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(fixedDate)
            $0.persistenceClient = .mock(onFinalizeRide: { finalized.setValue(($0, $1, $2, $3)) })
        }
        store.exhaustivity = .off

        await store.send(.resumableRideFetched(orphanedSummary))

        // The new ride is left untouched — not overwritten by the stale resumed one.
        #expect(store.state.activeRide?.rideId == newRideId)
        #expect(store.state.isDashboardPresented == true)

        #expect(finalized.value?.0 == orphanedRideId)
        #expect(finalized.value?.1 == fixedDate)
        #expect(finalized.value?.2 == orphanedSummary)
        #expect(finalized.value?.3 == nil)
    }

    /// The Rides tab only loads on its own `.task`, which fires once when it first
    /// mounts — not when a ride finishes underneath an already-mounted tab. Without
    /// this, a just-finished ride stayed invisible until something else (a tab
    /// switch) tore the view down and remounted it.
    ///
    /// `RidesFeature.rideFinished` (not a plain `reloadRides`) is what this actually
    /// exercises: `ActiveRideFeature`'s own finish effect (flush → GPX export →
    /// `finalizeRide`) is a separate, unsequenced effect, so the write is very often
    /// still in flight the instant this fires. `fetchRides` here only reports the ride
    /// once the test marks the write landed, standing in for that lag — proving the fix
    /// survives the race rather than merely firing once and usually losing it.
    /// (The poll mechanics themselves — the retry ceiling, multi-step chains — are
    /// `RidesFeatureTests.rideFinished*`'s job; this just proves the wiring at the
    /// ride-end seam sends the right action.)
    @Test("Confirming finish polls until the finalize write lands, not just reloads once and often misses it")
    func confirmFinishPollsUntilRideAppears() async {
        let testClock = TestClock()
        let fixedRideId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let finalized = LockIsolated(false)
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
            var client = PersistenceClient.mock()
            // Not there on the first read: the finalize write is still in flight.
            client.fetchRides = {
                guard finalized.value else { return [] }
                return [RideListSummary(id: fixedRideId, title: "", startedAt: .now,
                                        distanceMeters: 0, durationSeconds: 0)]
            }
            $0.persistenceClient = client
        }
        store.exhaustivity = .off

        // Real ride-start/finish flow, mirroring `rideEffectsStartAtRideLevel` — a
        // directly-seeded `activeRide` skips `.task`, leaving effects the finish
        // sequence expects to tear down (GPX export, calibration) never started.
        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        await store.receive(\.activeRide.task)

        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        await store.receive(\.rides.rideFinished)

        // Drives the poll's failed first read through to a successful second one.
        finalized.setValue(true)
        await testClock.advance(by: .milliseconds(200))
        await store.receive(\.rides.ridesResponse)
        // The thumbnail's wait for the same write, on its own one-second cadence.
        await testClock.advance(by: .seconds(1))
        await store.finish()

        #expect(store.state.rides.rides.map(\.id) == [fixedRideId])
    }

    // MARK: - Map thumbnail (#177)

    /// AppFeature nils `activeRide` on the same `confirmFinish` that starts the ride-end
    /// effect, and hands the capture to the Rides tab's `rideFinished` (#248), which waits
    /// for the finalize to land before rendering. The whole Finish → finalize → capture chain
    /// crosses two features, so only the composed reducer can see it end to end. The render
    /// checks for cancellation the way a real snapshotter may, so this fails if the ride's
    /// teardown ever reaches it.
    @Test("the map thumbnail is still captured although AppFeature tears the ride down on the same action")
    func thumbnailSurvivesRideTeardown() async throws {
        let finalized = LockIsolated<[UUID]>([])
        let saved = LockIsolated<[UUID]>([])
        let testClock = TestClock()
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.continuousClock = testClock
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.uuid = .incrementing
            $0.bleHRClient = .testValue
            $0.variaRadarClient = .testValue
            $0.locationClient = .testValue
            $0.hapticsClient = .testValue
            var client = PersistenceClient.mock(
                onFinalizeRide: { id, _, _, _ in finalized.withValue { $0.append(id) } },
                onSaveRideMapThumbnail: { id, _, _ in saved.withValue { $0.append(id) } }
            )
            // A finalized ride is the one that is missing its thumbnail, and the one
            // `rideFinished`'s poll is waiting to see.
            client.fetchRideIdsMissingMapThumbnail = { finalized.value }
            client.fetchRides = {
                finalized.value.map {
                    RideListSummary(id: $0, title: "", startedAt: .distantPast,
                                    distanceMeters: 0, durationSeconds: 0)
                }
            }
            // Whatever id `.task` gave the ride, it has a track.
            client.fetchTrackPoints = { rideId in
                [(43.070, -89.400), (43.071, -89.401)].map { latitude, longitude in
                    TrackPointDTO(
                        rideId: rideId, timestamp: Date(timeIntervalSince1970: 1_000_000),
                        latitude: latitude, longitude: longitude,
                        altitudeMeters: 0, horizontalAccuracyMeters: 5,
                        speedSource: .gps, heartRateSource: .none
                    )
                }
            }
            $0.persistenceClient = client
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _, _ in
                try Task.checkCancellation()
                return Data([1])
            }
        }
        store.exhaustivity = .off

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(nil)))))
        await store.receive(\.activeRide.task)
        let rideId = try #require(store.state.activeRide?.rideId)

        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))
        // Waits on the save itself: the pipeline (flush → export → finalize, then the
        // Rides tab's poll → capture) has no single action to receive. The poll sleeps on the
        // TestClock between reads, so it's stepped until the capture lands — at most the
        // poll's ten tries, after which the backfill runs regardless.
        await expectEventually { !finalized.value.isEmpty }
        for _ in 0..<20 where saved.value.isEmpty {
            await testClock.advance(by: .milliseconds(200))
            await Task.megaYield()
        }
        await expectEventually { !saved.value.isEmpty }
        await store.skipInFlightEffects(strict: false)

        #expect(store.state.activeRide == nil)
        #expect(saved.value == [rideId])
    }

    /// #175 review's orphan: a resumable ride found after the rider already started a new
    /// one is closed out rather than resumed. It never reached a Finish, so it gets its
    /// thumbnail here.
    @Test("an orphaned ride closed out at launch gets its map thumbnail")
    func orphanedRideCloseOutCapturesThumbnail() async {
        let orphan = RideSummaryUpdate(
            rideId: UUID(), recordingState: .active,
            durationSeconds: 120, distanceMeters: 800, averageSpeedMPS: 5, maxSpeedMPS: 9
        )
        let track = [(43.070, -89.400), (43.071, -89.401)].map { latitude, longitude in
            TrackPointDTO(
                rideId: orphan.rideId, timestamp: Date(timeIntervalSince1970: 1_000_000),
                latitude: latitude, longitude: longitude,
                altitudeMeters: 0, horizontalAccuracyMeters: 5,
                speedSource: .gps, heartRateSource: .none
            )
        }
        let finalized = LockIsolated<[UUID]>([])
        let saved = LockIsolated<[UUID]>([])
        let store = TestStore(
            initialState: AppFeature.State(activeRide: ActiveRideFeature.State(recordingState: .active))
        ) {
            AppFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient = .mock(
                trackPoints: [orphan.rideId: track],
                rideIdsMissingMapThumbnail: [orphan.rideId],
                onFinalizeRide: { id, _, _, _ in finalized.withValue { $0.append(id) } },
                onSaveRideMapThumbnail: { id, _, _ in saved.withValue { $0.append(id) } }
            )
            $0.mapSnapshotClient = MapSnapshotClient { _, _, _, _ in Data([1]) }
        }
        store.exhaustivity = .off

        await store.send(.resumableRideFetched(orphan))
        // The list reloads for the closed-out ride, then the capture tells the Rides tab its
        // image landed.
        await store.receive(\.rides.reloadRides)
        await store.receive(\.rides.mapThumbnailsCaptured)
        await store.finish(timeout: effectDrainTimeout)

        #expect(finalized.value == [orphan.rideId])
        #expect(saved.value == [orphan.rideId])
    }
}
