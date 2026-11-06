import ComposableArchitecture
import Foundation
import Testing
@testable import Cyclometer

/// S15's sheets (#538): the full-screen map, the vehicle passes and Edit, and what saving an
/// edit writes.
@MainActor
@Suite("RideDetailFeature — sheets and Edit")
struct RideDetailEditTests {

    // MARK: Harness

    private static let summary = RideListSummary(
        id: UUID(), title: "River Loop", startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        distanceMeters: 36_050, durationSeconds: 4_712
    )

    private static let stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, notes: "Headwind out")
    /// `stats` as the live read returns it, with the stored title.
    private static let storedStats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, title: "River Loop", notes: "Headwind out")

    private static let pass = VehiclePassEventDTO(
        rideId: summary.id, timestamp: Date(timeIntervalSince1970: 1_700_000_005),
        latitude: 45.0005, longitude: -93, alertLevelAtPass: .caution,
        riderSpeedKph: 22, estimatedPassSpeedKph: 61
    )

    private static let segments = [[
        RouteCoordinate(latitude: 45, longitude: -93), RouteCoordinate(latitude: 45.001, longitude: -93),
    ]]

    private func makeStore(
        _ configure: (inout RideDetailFeature.State) -> Void = { _ in },
        persistenceClient: PersistenceClient = .mock()
    ) -> TestStoreOf<RideDetailFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var state = RideDetailFeature.State(summary: Self.summary)
            state.stats = Self.stats
            configure(&state)
            return TestStore(initialState: state) {
                RideDetailFeature()
            } withDependencies: {
                $0.persistenceClient = persistenceClient
                $0.defaultFileStorage = storage
            }
        }
    }

    /// The map sheet as `mapTapped` opens it on this harness's ride: no track loaded, so no
    /// stops, and no radar in `stats`.
    private static func sheet(_ state: RideDetailFeature.State, passes: [VehiclePassEventDTO]) -> RideMapSheetFeature.State {
        RideMapSheetFeature.State(
            segments: segments, passes: passes, unitSystem: state.unitSystem, hasRadar: false,
            heartRateZones: state.heartRateZoneBounds, cadenceZones: state.preferences.cadenceZones
        )
    }

    /// The Edit sheet open on the ride as stored.
    private func editing(_ state: inout RideDetailFeature.State) {
        state.destination = .edit(RideEditFeature.State(title: Self.summary.title, notes: Self.stats.notes))
    }

    // MARK: Sheets

    @Test("tapping the map header opens the map with the track, the passes and the rider's units")
    func mapTappedOpensTheMap() async {
        let store = makeStore {
            $0.trackSegments = Self.segments
            $0.vehiclePasses = [Self.pass]
        }
        await store.send(.mapTapped) {
            $0.destination = .mapSheet(Self.sheet($0, passes: [Self.pass]))
        }
    }

    @Test("with no drawable track there is no map to open")
    func mapTappedWithoutTrackDoesNothing() async {
        let store = makeStore()
        await store.send(.mapTapped)
    }

    @Test("the Vehicle Passes row opens the pass sheet")
    func passesTappedOpensThePasses() async {
        let store = makeStore { $0.vehiclePasses = [Self.pass] }
        await store.send(.passesTapped) {
            $0.destination = .passes(RidePassesFeature.State(passes: [Self.pass], unitSystem: $0.unitSystem))
        }
    }

    @Test("Edit opens on the ride's title and notes")
    func editTappedOpensEdit() async {
        let store = makeStore()
        await store.send(.editTapped) {
            $0.destination = .edit(RideEditFeature.State(title: "River Loop", notes: "Headwind out"))
        }
    }

    /// The header room is kept while the track loads, so the title block doesn't drop half a
    /// screen when it lands, and given back once it's clear no track is coming.
    @Test("the header's room is kept while the track loads, and only for a ride that covered ground")
    func headerRoomWhileTrackLoads() async {
        let store = makeStore()
        #expect(store.state.reservesMapHeader, "loading, with distance")
        await store.send(.trackLoaded(segments: Self.segments, track: RideDetailTrack(points: [], altitudeSource: .gps))) {
            $0.trackSegments = Self.segments
            $0.track = RideDetailTrack(points: [], altitudeSource: .gps)
        }
        #expect(store.state.reservesMapHeader, "a drawable track")

        let noTrack = makeStore()
        await noTrack.send(.trackLoaded(segments: [], track: RideDetailTrack(points: [], altitudeSource: .gps))) {
            $0.track = RideDetailTrack(points: [], altitudeSource: .gps)
        }
        #expect(!noTrack.state.reservesMapHeader, "loaded, nothing to draw")

        let failed = makeStore()
        await failed.send(.trackLoadFailed) { $0.trackReadFailed = true }
        #expect(!failed.state.reservesMapHeader, "the read threw")

        let stationary = makeStore { $0.summary.distanceMeters = 0 }
        #expect(!stationary.state.reservesMapHeader, "no distance, so no track to wait for")
    }

    @Test("passes that land after the map sheet opened appear in it")
    func latePassesReachTheOpenMapSheet() async {
        let store = makeStore { $0.trackSegments = Self.segments }
        await store.send(.mapTapped) {
            $0.destination = .mapSheet(Self.sheet($0, passes: []))
        }
        await store.send(.vehiclePassesLoaded([Self.pass])) {
            $0.vehiclePasses = [Self.pass]
            $0.destination = .mapSheet(Self.sheet($0, passes: [Self.pass]))
        }
    }

    // MARK: Title from the store

    /// An S15 that was off screen while the ride was renamed elsewhere (the other tab, or further
    /// up the stack) takes the new title when it reappears and reloads.
    @Test("the stats bring the stored title, which replaces the one S15 was opened with")
    func statsLoadedTakesTheStoredTitle() async {
        let store = makeStore { $0.stats = nil }
        await store.send(.statsLoaded(RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, title: "Hill Loop"), route: nil)) {
            $0.stats = RideStats(averageSpeedMPS: 6, maxSpeedMPS: 11, title: "Hill Loop")
            $0.summary.title = "Hill Loop"
        }
    }

    /// Opened on no notes, a save would write over the stored ones without the rider seeing them.
    @Test("Edit waits for the stats, which bring the stored notes")
    func editTappedBeforeStatsDoesNothing() async {
        let store = makeStore { $0.stats = nil }
        await store.send(.editTapped)
    }

    // MARK: Saving

    @Test("saving a new title and notes shows them at once, writes both, tells the stack, and rewrites the GPX")
    func saveWritesTitleNotesAndGPX() async {
        let renamed = LockIsolated<[String]>([])
        let noted = LockIsolated<[String]>([])
        let replaced = LockIsolated<[String]>([])
        let store = makeStore(editing, persistenceClient: .mock(
            // What the rewrite reads back once the rename has landed.
            rideExportMetadata: [Self.summary.id: RideExportMetadata(title: "Hill Loop", startedAt: Self.summary.startedAt)],
            onRenameRide: { _, title in renamed.withValue { $0.append(title) } },
            onUpdateRideNotes: { _, notes in noted.withValue { $0.append(notes) } },
            onReplaceRideGPX: { _, data in replaced.withValue { $0.append(String(decoding: data, as: UTF8.self)) } }
        ))

        await store.send(.destination(.presented(.edit(.delegate(.save(title: "Hill Loop", notes: "Tailwind home")))))) {
            $0.destination = nil
            $0.summary.title = "Hill Loop"
            $0.stats?.notes = "Tailwind home"
        }
        await store.receive(.delegate(.rideEdited(id: Self.summary.id, title: "Hill Loop", notes: "Tailwind home")))
        await store.finish()

        #expect(renamed.value == ["Hill Loop"])
        #expect(noted.value == ["Tailwind home"])
        #expect(replaced.value.count == 1)
        #expect(replaced.value.first?.contains("<name>Hill Loop</name>") == true)
    }

    @Test("saving only the notes writes the notes, and leaves the title and the GPX alone")
    func saveNotesOnlySkipsRenameAndGPX() async {
        let renamed = LockIsolated(0)
        let noted = LockIsolated<[String]>([])
        let replaced = LockIsolated(0)
        let store = makeStore(editing, persistenceClient: .mock(
            onRenameRide: { _, _ in renamed.withValue { $0 += 1 } },
            onUpdateRideNotes: { _, notes in noted.withValue { $0.append(notes) } },
            onReplaceRideGPX: { _, _ in replaced.withValue { $0 += 1 } }
        ))

        await store.send(.destination(.presented(.edit(.delegate(.save(title: "River Loop", notes: "")))))) {
            $0.destination = nil
            $0.stats?.notes = ""
        }
        await store.receive(.delegate(.rideEdited(id: Self.summary.id, title: "River Loop", notes: "")))
        await store.finish()

        #expect(renamed.value == 0)
        #expect(noted.value == [""])
        #expect(replaced.value == 0)
    }

    @Test("a write that fails puts back what the store holds, tells no one, and leaves the GPX alone")
    func failedSaveReverts() async {
        let replaced = LockIsolated(0)
        var client = PersistenceClient.mock(
            rideExportMetadata: [Self.summary.id: RideExportMetadata(title: "River Loop", startedAt: Self.summary.startedAt)],
            rideStats: [Self.summary.id: Self.storedStats],
            onReplaceRideGPX: { _, _ in replaced.withValue { $0 += 1 } }
        )
        client.renameRide = { _, _ in throw PersistenceError.rideNotFound }
        let store = makeStore(editing, persistenceClient: client)

        await store.send(.destination(.presented(.edit(.delegate(.save(title: "Hill Loop", notes: "Tailwind home")))))) {
            $0.destination = nil
            $0.summary.title = "Hill Loop"
            $0.stats?.notes = "Tailwind home"
        }
        await store.receive(.editFailed)
        await store.receive(.editReverted(title: "River Loop", notes: "Headwind out")) {
            $0.summary.title = "River Loop"
            $0.stats?.notes = "Headwind out"
        }
        await store.finish()

        #expect(replaced.value == 0)
    }

    /// The notes are written first, so a failure can't leave a rename stored that S14 and the
    /// GPX never hear about.
    @Test("a notes write that fails leaves the title unwritten, so nothing is half-saved")
    func failedNotesWriteSkipsRename() async {
        let renamed = LockIsolated(0)
        var client = PersistenceClient.mock(
            rideExportMetadata: [Self.summary.id: RideExportMetadata(title: "River Loop", startedAt: Self.summary.startedAt)],
            rideStats: [Self.summary.id: Self.storedStats],
            onRenameRide: { _, _ in renamed.withValue { $0 += 1 } }
        )
        client.updateRideNotes = { _, _ in throw PersistenceError.rideNotFound }
        let store = makeStore(editing, persistenceClient: client)

        await store.send(.destination(.presented(.edit(.delegate(.save(title: "Hill Loop", notes: "Tailwind home")))))) {
            $0.destination = nil
            $0.summary.title = "Hill Loop"
            $0.stats?.notes = "Tailwind home"
        }
        await store.receive(.editFailed)
        await store.receive(.editReverted(title: "River Loop", notes: "Headwind out")) {
            $0.summary.title = "River Loop"
            $0.stats?.notes = "Headwind out"
        }
        await store.finish()

        #expect(renamed.value == 0)
    }
}

/// The Edit sheet's own rules: a ride keeps a title, Save needs a change, and surrounding
/// whitespace isn't saved.
@MainActor
@Suite("RideEditFeature")
struct RideEditFeatureTests {
    @Test("Save is off until something changes, and while the title is blank")
    func canSave() {
        var state = RideEditFeature.State(title: "River Loop", notes: "Headwind out")
        #expect(!state.canSave)
        state.notes = "Headwind out  "
        #expect(!state.canSave, "only whitespace changed")
        state.notes = "Tailwind"
        #expect(state.canSave)
        state.title = "   "
        #expect(!state.canSave, "a blank title")
        state.title = "Hill Loop"
        state.notes = "Headwind out"
        #expect(state.canSave)
    }

    @Test("Save hands up the trimmed title and notes")
    func saveSendsTrimmed() async {
        let store = TestStore(initialState: RideEditFeature.State(title: "River Loop", notes: "")) {
            RideEditFeature()
        }
        await store.send(.titleChanged(" Hill Loop ")) { $0.title = " Hill Loop " }
        await store.send(.notesChanged("Windy\n")) { $0.notes = "Windy\n" }
        await store.send(.saveTapped)
        await store.receive(.delegate(.save(title: "Hill Loop", notes: "Windy")))
    }

    @Test("Save does nothing while it's off")
    func saveWhileOffDoesNothing() async {
        let store = TestStore(initialState: RideEditFeature.State(title: "River Loop", notes: "")) {
            RideEditFeature()
        }
        await store.send(.saveTapped)
    }

    @Test("closing with nothing changed closes at once")
    func closeWithoutChangesDismisses() async {
        let dismissed = LockIsolated(false)
        let store = TestStore(initialState: RideEditFeature.State(title: "River Loop", notes: "")) {
            RideEditFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { dismissed.setValue(true) }
        }
        await store.send(.closeTapped)
        await store.finish()
        #expect(dismissed.value)
    }

    @Test("closing with changes asks first; Discard closes, Keep Editing stays")
    func closeWithChangesAsks() async {
        let dismissed = LockIsolated(0)
        let store = TestStore(initialState: RideEditFeature.State(title: "River Loop", notes: "")) {
            RideEditFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { dismissed.withValue { $0 += 1 } }
        }
        // A blank title can't be saved, but it is still a change to lose.
        await store.send(.titleChanged("")) { $0.title = "" }
        #expect(store.state.hasChanges && !store.state.canSave)

        await store.send(.closeTapped) { $0.discardDialog = Self.discardDialog }
        await store.send(.discardDialog(.dismiss)) { $0.discardDialog = nil }
        #expect(dismissed.value == 0)

        await store.send(.closeTapped) { $0.discardDialog = Self.discardDialog }
        await store.send(.discardDialog(.presented(.discard))) { $0.discardDialog = nil }
        await store.finish()
        #expect(dismissed.value == 1)
    }

    private static let discardDialog = ConfirmationDialogState<RideEditFeature.Action.Discard>(titleVisibility: .hidden) {
        TextState("Discard Changes?")
    } actions: {
        ButtonState(role: .destructive, action: .discard) {
            TextState("Discard Changes")
        }
        ButtonState(role: .cancel) {
            TextState("Keep Editing")
        }
    }
}
