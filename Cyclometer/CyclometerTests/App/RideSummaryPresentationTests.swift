import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S10 at the ride-end seam (#249): Finish presents it for the ride just ended, and dismissing it
/// — by its button or a swipe — saves the name, and commits Sync To (#631).
@MainActor
@Suite("Ride Summary presentation")
struct RideSummaryPresentationTests {

    private static let rideId = UUID(uuidString: "00000000-0000-0000-0000-000000000249")!

    /// `state` is built inside the store's file storage, after `seed`, so the S10 it carries reads
    /// the seeded preferences.
    private func makeStore(
        _ state: @autoclosure () -> AppFeature.State = AppFeature.State(),
        seed: (inout AppPreferences) -> Void = { _ in },
        persistenceClient: PersistenceClient,
        healthKitClient: HealthKitClient = .testValue
    ) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock(seed)
            return TestStore(initialState: state()) {
                AppFeature()
            } withDependencies: {
                $0.continuousClock = TestClock()
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
                $0.uuid = .incrementing
                $0.bleHRClient = .testValue
                $0.variaRadarClient = .testValue
                $0.locationClient = .testValue
                $0.hapticsClient = .testValue
                $0.persistenceClient = persistenceClient
                $0.healthKitClient = healthKitClient
                $0.defaultFileStorage = storage
            }
        }
    }

    /// App state with S10 up for a loaded, unnamed ride whose default is "Morning Loop".
    private func presenting(title: String, persistedTitle: String = "", notes: String = "") -> AppFeature.State {
        var summary = RideSummaryFeature.State(rideId: Self.rideId)
        summary.load = .loaded
        summary.defaultTitle = "Morning Loop"
        summary.persistedTitle = persistedTitle
        summary.title = title
        summary.notes = notes
        var state = AppFeature.State()
        state.rideSummary = summary
        return state
    }

    @Test("confirming Finish presents S10 after the dashboard dismisses")
    func finishPresentsSummary() async {
        let store = makeStore(persistenceClient: .mock())
        store.exhaustivity = .off

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.delegate(.startRide(rideId: UUID(0), route: nil)))))
        await store.receive(\.activeRide.task)
        let rideId = store.state.activeRide?.rideId

        await store.send(.activeRide(.pauseTapped))
        await store.send(.activeRide(.finishTapped))
        await store.send(.activeRide(.finishAlert(.presented(.confirmFinish))))

        #expect(store.state.activeRide == nil)
        #expect(store.state.isDashboardPresented == false)
        #expect(store.state.rideSummary == nil)
        #expect(store.state.pendingRideSummary?.rideId == rideId)

        await store.send(.dashboardDismissalCompleted)

        #expect(store.state.rideSummary?.rideId == rideId)
        #expect(store.state.rideSummary?.load == .waiting)
        #expect(store.state.pendingRideSummary == nil)
        await store.skipInFlightEffects()
    }

    /// The cover's `onDismiss` fires for a drag down mid-ride too (#365). Only a Finish leaves S10
    /// waiting on it.
    @Test("minimizing the dashboard mid-ride presents no S10")
    func minimizePresentsNoSummary() async {
        let store = makeStore(
            AppFeature.State(activeRide: ActiveRideFeature.State(recordingState: .active)),
            persistenceClient: .mock()
        )

        await store.send(.dashboardDismissalCompleted)
    }

    @Test("the Finish Ride button dismisses S10 and saves the rider's name, refreshes S14, then rewrites the GPX")
    func finishButtonSavesRename() async {
        let renamed = LockIsolated<[(UUID, String)]>([])
        let replaced = LockIsolated<[(UUID, String)]>([])
        let store = makeStore(presenting(title: "Hill Repeats"), persistenceClient: .mock(
            // What the rewrite reads back once the rename has landed.
            rideExportMetadata: [Self.rideId: RideExportMetadata(title: "Hill Repeats", startedAt: Date(timeIntervalSince1970: 1_000_000))],
            onRenameRide: { id, title in renamed.withValue { $0.append((id, title)) } },
            onReplaceRideGPX: { id, data in replaced.withValue { $0.append((id, String(decoding: data, as: UTF8.self))) } }
        ))
        store.exhaustivity = .off

        await store.send(.rideSummary(.presented(.finishTapped)))
        await store.receive(\.rideSummary.dismiss)
        await store.receive(\.rides.reloadRides)
        await store.finish()

        #expect(store.state.rideSummary == nil)
        #expect(renamed.value.map(\.0) == [Self.rideId])
        #expect(renamed.value.map(\.1) == ["Hill Repeats"])
        #expect(replaced.value.map(\.0) == [Self.rideId])
        #expect(replaced.value.first?.1.contains("<trk>\n    <name>Hill Repeats</name>") == true)
    }

    @Test("a rename that fails leaves the GPX alone")
    func failedRenameSkipsRewrite() async {
        let replaced = LockIsolated(0)
        var client = PersistenceClient.mock(onReplaceRideGPX: { _, _ in replaced.withValue { $0 += 1 } })
        client.renameRide = { _, _ in throw PersistenceError.rideNotFound }
        let store = makeStore(presenting(title: "Hill Repeats"), persistenceClient: client)

        await store.send(.rideSummary(.dismiss)) {
            $0.rideSummary?.$preferences.withLock { $0.syncDestinationDefaults = [.appleHealth: true] }
            $0.rideSummary = nil
        }
        await store.finish()
        #expect(replaced.value == 0)
    }

    /// A swipe-down arrives as a bare `.dismiss`, with no child action before it.
    @Test("swiping S10 away saves the name too — the default, when the rider didn't type one")
    func swipeSavesDefault() async {
        let renamed = LockIsolated<[String]>([])
        let store = makeStore(presenting(title: "Morning Loop"), persistenceClient: .mock(
            onRenameRide: { _, title in renamed.withValue { $0.append(title) } }
        ))
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.receive(\.rides.reloadRides)

        #expect(store.state.rideSummary == nil)
        #expect(renamed.value == ["Morning Loop"])
    }

    @Test("dismissing a ride whose name didn't change writes nothing")
    func unchangedNameNoWrite() async {
        let renamed = LockIsolated(0)
        let store = makeStore(presenting(title: "Coffee Run", persistedTitle: "Coffee Run"), persistenceClient: .mock(
            onRenameRide: { _, _ in renamed.withValue { $0 += 1 } }
        ))

        await store.send(.rideSummary(.dismiss)) {
            $0.rideSummary?.$preferences.withLock { $0.syncDestinationDefaults = [.appleHealth: true] }
            $0.rideSummary = nil
        }
        await store.finish()
        #expect(renamed.value == 0)
    }

    @Test("notes typed in S10 are saved on dismiss, without a rename, S14 reload or GPX rewrite (#645)")
    func notesSavedAlone() async {
        let notes = LockIsolated<[(UUID, String)]>([])
        let renamed = LockIsolated(0)
        let replaced = LockIsolated(0)
        let store = makeStore(presenting(title: "Coffee Run", persistedTitle: "Coffee Run", notes: "  Headwind "),
                              persistenceClient: .mock(
            onRenameRide: { _, _ in renamed.withValue { $0 += 1 } },
            onUpdateRideNotes: { id, text in notes.withValue { $0.append((id, text)) } },
            onReplaceRideGPX: { _, _ in replaced.withValue { $0 += 1 } }
        ))

        await store.send(.rideSummary(.dismiss)) {
            $0.rideSummary?.$preferences.withLock { $0.syncDestinationDefaults = [.appleHealth: true] }
            $0.rideSummary = nil
        }
        await store.finish()

        #expect(notes.value.map(\.0) == [Self.rideId])
        #expect(notes.value.map(\.1) == ["Headwind"])
        #expect(renamed.value == 0)
        #expect(replaced.value == 0)
    }

    @Test("the notes are written before the rename; a failed notes write doesn't stop the rename (#645)")
    func notesAndRename() async {
        let writes = LockIsolated<[String]>([])
        var client = PersistenceClient.mock(onRenameRide: { _, title in writes.withValue { $0.append("rename \(title)") } })
        client.updateRideNotes = { _, notes in
            writes.withValue { $0.append("notes \(notes)") }
            throw PersistenceError.rideNotFound
        }
        let store = makeStore(presenting(title: "Hill Repeats", notes: "Legs gone"), persistenceClient: client)
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.receive(\.rides.reloadRides)

        #expect(writes.value == ["notes Legs gone", "rename Hill Repeats"])
    }

    /// A rename typed before deleting must not be written to a ride that's going (#452).
    @Test("confirming Delete closes S10 without a rename or Sync To, and deletes the ride and its workout through S14")
    func confirmedDeleteDeletesRide() async {
        let renamed = LockIsolated(0)
        let owedSet = LockIsolated(0)
        let deleted = LockIsolated<[String]>([])
        var state = presenting(title: "Hill Repeats")
        state.rideSummary?.alert = RideSummaryFeature.deleteAlert
        let store = makeStore(
            state,
            persistenceClient: .mock(
                onRenameRide: { _, _ in renamed.withValue { $0 += 1 } },
                onSetHealthWorkoutOwed: { _, _ in owedSet.withValue { $0 += 1 } },
                onDeleteRide: { id in deleted.withValue { $0.append("ride \(id)") } }
            ),
            healthKitClient: .mock(onDeleteWorkout: { id in deleted.withValue { $0.append("workout \(id)") } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.presented(.alert(.presented(.confirmDelete)))))
        await store.receive(\.rideSummary.presented.delegate.deleteRide) {
            $0.rideSummary = nil
        }
        await store.receive(\.rides.deleteRecordedRide)
        await store.finish()

        #expect(renamed.value == 0)
        #expect(owedSet.value == 0)
        #expect(store.state.preferences.syncDestinationDefaults.isEmpty)
        #expect(deleted.value == ["workout \(Self.rideId)", "ride \(Self.rideId)"])
    }

    // MARK: - Sync To (#631)

    private static let stravaNoUploadScope = ConnectedService(
        serviceType: .strava, keychainIdentifier: "strava", athleteID: "1",
        grantedScopes: ["read"], connectedAt: Date(timeIntervalSince1970: 0)
    )

    private static let owedRide = OwedHealthWorkout(
        rideId: rideId, startedAt: Date(timeIntervalSince1970: 1_000_000),
        endedAt: Date(timeIntervalSince1970: 1_003_600), distanceMeters: 20_000, movingSeconds: 3_500
    )

    @Test("closing S10 with Apple Health on marks the ride owed, writes its workout, and remembers the choice")
    func healthOnAtClose() async {
        let owed = LockIsolated<[(UUID, Bool)]>([])
        let written = LockIsolated<[UUID]>([])
        let store = makeStore(
            presenting(title: "Morning Loop", persistedTitle: "Morning Loop"),
            persistenceClient: .mock(
                ridesOwedHealthWorkout: [Self.owedRide],
                onSetHealthWorkoutOwed: { id, isOwed in owed.withValue { $0.append((id, isOwed)) } }
            ),
            healthKitClient: .mock(onSaveWorkout: { workout in written.withValue { $0.append(workout.rideId) } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(owed.value.map(\.0) == [Self.rideId])
        #expect(owed.value.map(\.1) == [true])
        #expect(written.value == [Self.rideId])
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: true])
    }

    @Test("closing S10 with Apple Health turned off clears the ride, writes no workout, and remembers off")
    func healthOffAtClose() async {
        let owed = LockIsolated<[Bool]>([])
        let written = LockIsolated(0)
        // Computed, so it's built in the store's file storage (see `makeStore`).
        var state: AppFeature.State {
            var state = presenting(title: "Morning Loop", persistedTitle: "Morning Loop")
            state.rideSummary?.syncToggles[.appleHealth] = false
            return state
        }
        let store = makeStore(
            state,
            persistenceClient: .mock(onSetHealthWorkoutOwed: { _, isOwed in owed.withValue { $0.append(isOwed) } }),
            healthKitClient: .mock(onSaveWorkout: { _ in written.withValue { $0 += 1 } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(owed.value == [false])
        #expect(written.value == 0)
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: false])
    }

    /// A swipe-down is a bare `.dismiss`; Finish Ride sends `finishTapped` first. Both commit.
    @Test("Finish Ride commits Sync To as a swipe does")
    func finishButtonCommitsSyncTo() async {
        let owed = LockIsolated<[Bool]>([])
        let store = makeStore(
            presenting(title: "Morning Loop", persistedTitle: "Morning Loop"),
            persistenceClient: .mock(onSetHealthWorkoutOwed: { _, isOwed in owed.withValue { $0.append(isOwed) } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.presented(.finishTapped)))
        await store.receive(\.rideSummary.dismiss)
        await store.finish()

        #expect(owed.value == [true])
    }

    @Test("with Strava chosen, the ride is queued after the rename lands, so the upload carries the new name")
    func stravaQueuedAfterRename() async {
        let records = LockIsolated<[UUID]>([])
        let store = makeStore(
            presenting(title: "Hill Repeats"),
            seed: {
                $0.connectedServices = [Self.stravaNoUploadScope]
                $0.syncDestinationDefaults = [.service(.strava): true]
            },
            persistenceClient: .mock(onSaveSyncRecord: { id, _ in records.withValue { $0.append(id) } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        // Not exhaustive, so a `receive` skips what came before it: the enqueue after the reload
        // proves the order.
        await store.receive(\.rides.reloadRides)
        await store.receive(\.syncQueue.enqueue)
        await store.finish()

        // Without the upload scope the queue writes it waiting rather than uploading (#630).
        #expect(records.value == [Self.rideId])
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: true, .service(.strava): true])
    }

    @Test("a service never chosen starts off, so a swipe sends the ride nowhere but Apple Health")
    func stravaNeverChosenNotQueued() async {
        let records = LockIsolated(0)
        let store = makeStore(
            presenting(title: "Morning Loop", persistedTitle: "Morning Loop"),
            seed: { $0.connectedServices = [Self.stravaNoUploadScope] },
            persistenceClient: .mock(onSaveSyncRecord: { _, _ in records.withValue { $0 += 1 } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(records.value == 0)
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: true, .service(.strava): false])
    }

    @Test("with Strava turned off, nothing is queued, and off is remembered")
    func stravaOffNotQueued() async {
        let records = LockIsolated(0)
        var state: AppFeature.State {
            var state = presenting(title: "Morning Loop", persistedTitle: "Morning Loop")
            state.rideSummary?.syncToggles[.service(.strava)] = false
            return state
        }
        let store = makeStore(
            state,
            seed: {
                $0.connectedServices = [Self.stravaNoUploadScope]
                $0.syncDestinationDefaults = [.service(.strava): true]
            },
            persistenceClient: .mock(onSaveSyncRecord: { _, _ in records.withValue { $0 += 1 } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(records.value == 0)
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: true, .service(.strava): false])
    }

    @Test("a Strava account waiting on Reconnect isn't queued, and its remembered choice is kept")
    func disconnectedStravaKeepsChoice() async {
        let records = LockIsolated(0)
        var disconnected = Self.stravaNoUploadScope
        disconnected.isDisconnected = true
        let store = makeStore(
            presenting(title: "Morning Loop", persistedTitle: "Morning Loop"),
            seed: {
                $0.connectedServices = [disconnected]
                $0.syncDestinationDefaults = [.service(.strava): true]
            },
            persistenceClient: .mock(onSaveSyncRecord: { _, _ in records.withValue { $0 += 1 } })
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(records.value == 0)
        #expect(store.state.preferences.syncDestinationDefaults == [.appleHealth: true, .service(.strava): true])
    }

    @Test("closing before the ride's finalize lands waits for it, then commits")
    func closeBeforeFinalizeWaits() async {
        let owed = LockIsolated<[Bool]>([])
        var state: AppFeature.State {
            var state = presenting(title: "Morning Loop", persistedTitle: "Morning Loop")
            state.rideSummary?.load = .waiting
            return state
        }
        let store = makeStore(
            state,
            persistenceClient: .mock(
                // Finalized by the time it's read: `fetchRides` lists only ended rides.
                rides: [RideListSummary(id: Self.rideId, title: "Morning Loop", startedAt: .now,
                                        distanceMeters: 1_000, durationSeconds: 300)],
                onSetHealthWorkoutOwed: { _, isOwed in owed.withValue { $0.append(isOwed) } }
            )
        )
        store.exhaustivity = .off

        await store.send(.rideSummary(.dismiss))
        await store.finish()

        #expect(owed.value == [true])
    }

    @Test("a Reconnect from Sync To resumes the upload queue")
    func reconnectResumesQueue() async {
        let store = makeStore(presenting(title: "Morning Loop"), persistenceClient: .mock())
        store.exhaustivity = .off

        await store.send(.rideSummary(.presented(.delegate(.serviceConnected))))
        await store.receive(\.syncQueue.resume)
        await store.finish()
    }
}
