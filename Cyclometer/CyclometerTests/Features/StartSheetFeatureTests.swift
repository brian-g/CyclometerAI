import Foundation
import Testing
import ComposableArchitecture
@testable import Cyclometer

@MainActor
@Suite("StartSheetFeature")
struct StartSheetFeatureTests {

    @Test("Start Ride writes the Ride row, then emits the startRide delegate with its id")
    func startRideEmitsDelegate() async {
        let created = LockIsolated<[UUID: Date]>([:])
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient.createRide = { id, startedAt, _ in created.withValue { $0[id] = startedAt } }
        }

        await store.send(.startRideButtonTapped) { $0.pendingRideId = UUID(0) }
        await store.receive(.rideCreated(rideId: UUID(0), route: nil)) { $0.pendingRideId = nil }
        await store.receive(.delegate(.startRide(rideId: UUID(0), route: nil)))
        #expect(created.value == [UUID(0): Date(timeIntervalSince1970: 1_000_000)])
    }

    /// A ride without its `Ride` row has nothing to checkpoint or finalize and never reaches
    /// Rides (#344). The failure keeps the rider on the sheet, before any sensor records,
    /// and a second tap is a retry.
    @Test("A failed Ride write keeps the sheet up with an alert, and starts no ride")
    func startRideFailureAlerts() async {
        struct WriteFailed: Error {}
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient.createRide = { _, _, _ in throw WriteFailed() }
        }

        await store.send(.startRideButtonTapped) { $0.pendingRideId = UUID(0) }
        await store.receive(.rideCreationFailed) {
            $0.pendingRideId = nil
            $0.alert = AlertState {
                TextState("Couldn't Start Ride")
            } actions: {
                ButtonState(role: .cancel) { TextState("OK") }
            } message: {
                TextState("Your ride couldn't be saved, so it wasn't started. Try again.")
            }
        }
        await store.send(.alert(.dismiss)) { $0.alert = nil }
    }

    /// The Route row stays usable while the row is written. The ride must follow the route its
    /// row was written with, or S20's Previous Rides would file it under a route it didn't ride.
    @Test("A route picked while the Ride row is being written doesn't reach the ride")
    func startRideKeepsTheWrittenRoute() async {
        let gate = AsyncStream.makeStream(of: Void.self)
        let store = TestStore(initialState: StartSheetFeature.State(route: Self.route.reference)) {
            StartSheetFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient.createRide = { _, _, _ in
                for await _ in gate.stream { break }
            }
        }
        store.exhaustivity = .off

        await store.send(.startRideButtonTapped)
        await store.send(.path(.push(id: 0, state: store.state.routePicker)))
        await store.send(.path(.element(id: 0, action: .routePicker(.delegate(.routeSelected(nil))))))
        #expect(store.state.route == nil)
        gate.continuation.yield()
        await store.receive(.delegate(.startRide(rideId: UUID(0), route: Self.route.reference)))
    }

    @Test("A second tap while the Ride row is being written starts nothing")
    func startRideIgnoresSecondTap() async {
        let gate = AsyncStream.makeStream(of: Void.self)
        let created = LockIsolated(0)
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient.createRide = { _, _, _ in
                created.withValue { $0 += 1 }
                for await _ in gate.stream { break }
            }
        }

        await store.send(.startRideButtonTapped) { $0.pendingRideId = UUID(0) }
        await store.send(.startRideButtonTapped)
        gate.continuation.yield()
        await store.receive(.rideCreated(rideId: UUID(0), route: nil)) { $0.pendingRideId = nil }
        await store.receive(.delegate(.startRide(rideId: UUID(0), route: nil)))
        #expect(created.value == 1)
    }

    @Test("Cancel dismisses the sheet")
    func cancelDismisses() async {
        let isDismissed = LockIsolated(false)
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect { isDismissed.setValue(true) }
        }

        await store.send(.cancelButtonTapped)
        #expect(isDismissed.value)
    }

    /// #197 review: the toggle is the rider's remembered preference, not the sheet's own state, so
    /// the ride — and a ride resumed after a kill — reads the same answer.
    @Test("The turn-by-turn toggle writes the rider's preference, both ways")
    func turnByTurnToggleWritesThePreference() async {
        let store = makeStore()
        await store.send(.turnByTurnChanged(false)) {
            $0.$preferences.withLock { $0.isTurnByTurnEnabled = false }
        }
        await store.send(.turnByTurnChanged(false))
        await store.send(.turnByTurnChanged(true)) {
            $0.$preferences.withLock { $0.isTurnByTurnEnabled = true }
        }
    }

    @Test("Radar connection states map to the radar row badge")
    func radarStatusMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.radarStatusUpdated(.active)) {
            $0.setStatus(.connected, for: .radar)
        }
        await store.send(.radarStatusUpdated(.disconnected)) {
            $0.setStatus(.searching, for: .radar)
        }
        // Everything short of connected collapses into Searching — the sheet holds a
        // pairing scan open, so a sensor it is not talking to is one it is looking for.
        await store.send(.radarStatusUpdated(.connected)) {
            $0.setStatus(.connected, for: .radar)
        }
        await store.send(.radarStatusUpdated(.reconnecting)) {
            $0.setStatus(.searching, for: .radar)
        }
        await store.send(.radarStatusUpdated(.scanning))
        await store.send(.radarStatusUpdated(.connecting))
    }

    @Test("HR's bool maps to connected / searching — it is not the pairing record")
    func hrPairingMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.hrPairingUpdated(true)) {
            $0.setStatus(.connected, for: .heartRate)
        }
        await store.send(.hrPairingUpdated(false)) {
            $0.setStatus(.searching, for: .heartRate)
        }
    }

    @Test("Speed and cadence CSC states update their own rows independently")
    func speedCadenceMapping() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.cadenceStatusUpdated(.connected)) {
            $0.setStatus(.connected, for: .cadence)
        }
        #expect(store.state.sensors.first { $0.kind == .speed }?.status == .searching)
    }



    // MARK: Which rows the sheet shows

    /// Seeded in the same dependency scope the store reads from, otherwise the seed and
    /// the store see different storage — the idiom `DeviceManagementFeatureTests` uses.
    private func makeStore(
        sensors: [SensorRow] = SensorRow.Kind.allCases.map { SensorRow(kind: $0) },
        pairedSensors: [PairedSensor] = [],
        sensorHealth: [UUID: SensorHealthReport] = [:]
    ) -> TestStoreOf<StartSheetFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            @Shared(.appPreferences) var preferences
            $preferences.withLock {
                $0.pairedSensors = pairedSensors
                $0.sensorHealth = sensorHealth
            }
            return TestStore(initialState: StartSheetFeature.State(sensors: sensors)) {
                StartSheetFeature()
            } withDependencies: {
                $0.defaultFileStorage = storage
            }
        }
    }

    /// The point of the change: a paired sensor the app is not connected to is the
    /// sheet's *normal* state, because nothing scans until the ride starts.
    @Test("A paired sensor that is not connected is still listed, named, and Searching")
    func notConnectedPairedSensorIsListed() {
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515")
            ]
        )

        let rows = store.state.pairedRows
        #expect(rows.map(\.kind) == [.radar])
        // Named from the record, which is the only source that survives being out of range.
        #expect(rows[0].name == "Varia RTL515")
        #expect(rows[0].status == .searching)
        #expect(rows[0].status.badge.label == "Searching")
    }

    @Test("A row carries the warning its device's last ride left (#391)")
    func rowCarriesLastRideWarning() {
        let rideId = UUID(0)
        let store = makeStore(
            pairedSensors: [
                PairedSensor(peripheralID: UUID(1), role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: UUID(2), role: .speed, displayName: "Wahoo SPEED"),
                PairedSensor(peripheralID: UUID(3), role: .cadence, displayName: "Wahoo CADENCE"),
                PairedSensor(peripheralID: UUID(4), role: .heartRate, displayName: "Wahoo TICKR")
            ],
            sensorHealth: [
                UUID(1): SensorHealthReport(rideId: rideId, minBatteryPercent: 80, maxLinkLossesPerWindow: 0),
                UUID(2): SensorHealthReport(rideId: rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 43),
                UUID(3): SensorHealthReport(rideId: rideId, minBatteryPercent: 85, maxLinkLossesPerWindow: 9)
            ]
        )

        let warnings = Dictionary(uniqueKeysWithValues: store.state.pairedRows.map { ($0.kind, $0.warning) })
        #expect(warnings[.radar] == .some(nil))
        #expect(warnings[.speed] == .batteryLow)
        #expect(warnings[.cadence] == .linkUnreliable)
        #expect(warnings[.heartRate] == .some(nil))
    }

    @Test("An unpaired category has no row at all")
    func unpairedCategoriesAreAbsent() {
        let store = makeStore(
            sensors: [
                SensorRow(kind: .radar, status: .connected),
                SensorRow(kind: .heartRate, status: .searching),
                SensorRow(kind: .speed, status: .searching),
                SensorRow(kind: .cadence, status: .searching)
            ],
            pairedSensors: [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: UUID(), role: .speed, displayName: "Wahoo RPM")
            ]
        )

        #expect(store.state.pairedRows.map(\.kind) == [.radar, .speed])
    }

    /// Live status is not what decides the row's existence — that was the bug. A record
    /// with no client signal behind it still gets a row.
    @Test("Rows come from the records, not from live client status")
    func rowsComeFromRecordsNotStatus() {
        let store = makeStore(pairedSensors: [])
        #expect(store.state.pairedRows.isEmpty)

        let paired = makeStore(
            pairedSensors: SensorRow.Kind.allCases.map {
                PairedSensor(peripheralID: UUID(), role: $0.role, displayName: nil)
            }
        )
        #expect(paired.state.pairedRows.count == SensorRow.Kind.allCases.count)
        #expect(paired.state.pairedRows.allSatisfy { $0.status == .searching })
    }

    @Test("Every category maps to the role its records are keyed by")
    func kindsMapToRoles() {
        #expect(SensorRow.Kind.allCases.map(\.role) == [.radar, .heartRate, .speed, .cadence])
    }

    @Test("Battery updates land on the addressed row only, and clear on nil")
    func batteryUpdatesAddressedRow() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.batteryUpdated(.radar, 82)) {
            $0.setBattery(82, for: .radar)
        }
        // A second row's level must not disturb the first.
        await store.send(.batteryUpdated(.heartRate, 14)) {
            $0.setBattery(14, for: .heartRate)
        }
        #expect(store.state.sensors.first { $0.kind == .radar }?.batteryPercent == 82)

        // Disconnecting clears it — the row must not keep showing a stale level.
        await store.send(.batteryUpdated(.radar, nil)) {
            $0.setBattery(nil, for: .radar)
        }
    }

    @Test("Appearing subscribes to each client's battery stream")
    func taskSubscribesToBatteryStreams() async {
        let (radarStream, radarContinuation) = AsyncStream<Int?>.makeStream()
        let (hrStream, hrContinuation) = AsyncStream<Int?>.makeStream()
        let (speedStream, speedContinuation) = AsyncStream<Int?>.makeStream()
        let (cadenceStream, cadenceContinuation) = AsyncStream<Int?>.makeStream()

        var radar = VariaRadarClient.testValue
        radar.batteryLevel = { radarStream }
        var hr = BLEHRClient.testValue
        hr.batteryLevel = { hrStream }
        var csc = BLECSCClient.testValue
        csc.batteryLevel = { role in role == .speed ? speedStream : cadenceStream }

        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.variaRadarClient = radar
            $0.bleHRClient = hr
            $0.bleCSCClient = csc
        }

        await store.send(.task)
        // No position from `LocationClient.testValue`, so no weather (#149).
        await store.receive(.weatherUnavailable(.noLocation)) { $0.weather = .unavailable(.noLocation) }

        radarContinuation.yield(91)
        await store.receive(\.batteryUpdated) { $0.setBattery(91, for: .radar) }
        hrContinuation.yield(47)
        await store.receive(\.batteryUpdated) { $0.setBattery(47, for: .heartRate) }
        speedContinuation.yield(63)
        await store.receive(\.batteryUpdated) { $0.setBattery(63, for: .speed) }
        cadenceContinuation.yield(8)
        await store.receive(\.batteryUpdated) { $0.setBattery(8, for: .cadence) }

        radarContinuation.finish()
        hrContinuation.finish()
        speedContinuation.finish()
        cadenceContinuation.finish()
        await store.finish()
    }

    // MARK: Route (#196)

    /// "Summit Climb".
    private static let route = RouteSummary.previewRoutes[1]

    @Test("Start Ride carries the sheet's route")
    func startRideCarriesTheRoute() async {
        let createdRoute = LockIsolated<RouteReference?>(nil)
        let store = TestStore(initialState: StartSheetFeature.State(route: Self.route.reference)) {
            StartSheetFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
            $0.persistenceClient.createRide = { _, _, route in createdRoute.setValue(route) }
        }

        await store.send(.startRideButtonTapped) { $0.pendingRideId = UUID(0) }
        await store.receive(.rideCreated(rideId: UUID(0), route: Self.route.reference)) { $0.pendingRideId = nil }
        await store.receive(.delegate(.startRide(rideId: UUID(0), route: Self.route.reference)))
        // Written to the row too, which is what S20's Previous Rides reads back.
        #expect(createdRoute.value == Self.route.reference)
    }

    /// The state the Route row pushes. Held here so that dropping `selection: route` fails a test:
    /// after Use This Route, S05.2 must open with that route checked, not None.
    @Test("The Route row opens S05.2 with the sheet's route checked")
    func routeRowOpensThePickerOnTheSheetsRoute() {
        let chosen = StartSheetFeature.State(route: Self.route.reference)
        #expect(chosen.routePicker == .routePicker(RoutePickerFeature.State(selection: Self.route.reference)))
        #expect(StartSheetFeature.State().routePicker == .routePicker(RoutePickerFeature.State()))
    }

    @Test("Picking a route on S05.2 fills the Route row and pops back to the sheet")
    func pickingARouteSetsItAndPops() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        }

        await store.send(.path(.push(id: 0, state: .routePicker(RoutePickerFeature.State())))) {
            $0.path[id: 0] = .routePicker(RoutePickerFeature.State())
        }
        await store.send(.path(.element(id: 0, action: .routePicker(.routeTapped(Self.route))))) {
            $0.path[id: 0, case: \.routePicker]?.selection = Self.route.reference
        }
        await store.receive(\.path[id: 0].routePicker.delegate.routeSelected, Self.route.reference) {
            $0.route = Self.route.reference
            $0.path = StackState()
        }
        // `PersistenceClient.testValue` has no such route, so no estimate (#149).
        await store.receive(.rideEstimateLoaded(nil))
    }

    /// The way back to a free ride once S20 has seeded a route.
    @Test("Picking None on S05.2 clears the route")
    func pickingNoneClearsTheRoute() async {
        let store = TestStore(initialState: StartSheetFeature.State(route: Self.route.reference)) {
            StartSheetFeature()
        }
        let picker = RoutePickerFeature.State(selection: Self.route.reference)

        await store.send(.path(.push(id: 0, state: .routePicker(picker)))) {
            $0.path[id: 0] = .routePicker(picker)
        }
        await store.send(.path(.element(id: 0, action: .routePicker(.routeTapped(nil))))) {
            $0.path[id: 0, case: \.routePicker]?.selection = nil
        }
        await store.receive(\.path[id: 0].routePicker.delegate.routeSelected, nil) {
            $0.route = nil
            $0.path = StackState()
        }
    }

    // MARK: - Weather (#149)

    private nonisolated static let fargo = Coordinate(latitude: 46.8772, longitude: -96.7898)

    @Test("With location, the sheet shows the weather where the rider is")
    func weatherLoads() async {
        let asked = LockIsolated<[RouteCoordinate]>([])
        var weather = WeatherClient.testValue
        weather.current = { coordinate in asked.withValue { $0.append(coordinate) }; return .fixture }

        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.date = .constant(WeatherReading.fixtureNow)
            $0.locationClient.currentCoordinate = { Self.fargo }
            $0.weatherClient = weather
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task)
        await store.receive(.weatherLoaded(StartSheetForecast.fixture)) { $0.weather = .loaded(StartSheetForecast.fixture) }
        #expect(asked.value == [RouteCoordinate(latitude: Self.fargo.latitude, longitude: Self.fargo.longitude)])
    }

    /// S01 owns the location prompt; this sheet only reads the status.
    @Test("With location off, the sheet says so and never asks for a position")
    func weatherWithoutLocation() async {
        let positionAsked = LockIsolated(false)
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.permissionsClient.status = { _ in .denied }
            $0.permissionsClient.request = { _ in Issue.record("The sheet must not raise a location prompt"); return .denied }
            $0.locationClient.currentCoordinate = { positionAsked.setValue(true); return Self.fargo }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task)
        await store.receive(.weatherUnavailable(.noLocation)) { $0.weather = .unavailable(.noLocation) }
        #expect(!positionAsked.value)
    }

    @Test("A failed WeatherKit request shows the unavailable state")
    func weatherFails() async {
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.locationClient.currentCoordinate = { Self.fargo }
            $0.weatherClient = .unavailable
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task)
        await store.receive(.weatherUnavailable(.failed)) { $0.weather = .unavailable(.failed) }
    }

    @Test("With no route, the strip covers the hour under way and the next three hours")
    func forecastHoursDefault() {
        var state = StartSheetFeature.State()
        state.weather = .loaded(StartSheetForecast.fixture)
        // 14:40: 14:00, 15:00, 16:00 and 17:00 all start before 17:40.
        #expect(state.forecastHours == Array(WeatherReading.fixtureHourly.prefix(4)))
    }

    @Test("With a route, the strip covers the ride's estimated time")
    func forecastHoursForRoute() {
        var state = StartSheetFeature.State(route: Self.route.reference)
        state.weather = .loaded(StartSheetForecast.fixture)
        state.rideEstimate = 5.5 * 3600
        // 14:40 + 5 h 30 min is 20:10: the hours from 14:00 to 20:00.
        #expect(state.forecastHours == Array(WeatherReading.fixtureHourly.prefix(7)))
        state.weather = .unavailable(.failed)
        #expect(state.forecastHours.isEmpty)
    }

    @Test("A route S20 seeded is estimated as the sheet opens, from the rider's rides of it")
    func estimateOnOpen() async {
        let summary = RouteSummary.previewRoutes[1]
        // 10 m/s, so the estimate is exactly the route's distance over 10.
        let rides = [RouteRideSummary(rideId: UUID(), title: "", startedAt: .distantPast, endedAt: nil,
                                      durationSeconds: 3_600, distanceMeters: 36_000)]
        let store = TestStore(initialState: StartSheetFeature.State(route: summary.reference)) {
            StartSheetFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(routes: [summary], ridesByRoute: [summary.id: rides])
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.task)
        await store.receive(.rideEstimateLoaded(summary.distanceMeters / 10)) { $0.rideEstimate = summary.distanceMeters / 10 }
    }

    @Test("Picking another route clears the estimate until the new one lands; None leaves it cleared")
    func estimateFollowsTheRoute() async {
        let summary = RouteSummary.previewRoutes[1]
        let recent = [RideListSummary(id: UUID(), title: "", startedAt: .distantPast,
                                      distanceMeters: 18_000, durationSeconds: 3_600)]
        var initial = StartSheetFeature.State()
        initial.rideEstimate = 9_999
        let store = TestStore(initialState: initial) {
            StartSheetFeature()
        } withDependencies: {
            $0.persistenceClient = .mock(rides: recent, routes: [summary])
        }

        await store.send(.path(.push(id: 0, state: .routePicker(RoutePickerFeature.State())))) {
            $0.path[id: 0] = .routePicker(RoutePickerFeature.State())
        }
        await store.send(.path(.element(id: 0, action: .routePicker(.delegate(.routeSelected(summary.reference)))))) {
            $0.route = summary.reference
            $0.path = StackState()
            $0.rideEstimate = nil
        }
        // No rides of this route yet: the rider's recent speed, 5 m/s.
        await store.receive(.rideEstimateLoaded(summary.distanceMeters / 5)) { $0.rideEstimate = summary.distanceMeters / 5 }

        await store.send(.path(.push(id: 1, state: .routePicker(RoutePickerFeature.State(selection: summary.reference))))) {
            $0.path[id: 1] = .routePicker(RoutePickerFeature.State(selection: summary.reference))
        }
        await store.send(.path(.element(id: 1, action: .routePicker(.delegate(.routeSelected(nil)))))) {
            $0.route = nil
            $0.path = StackState()
            $0.rideEstimate = nil
        }
    }

    @Test("A slow estimate for the last route can't land on the newly picked one")
    func staleEstimateCancelled() async {
        let first = RouteSummary.previewRoutes[0]
        let second = RouteSummary.previewRoutes[1]
        let gate = AsyncStream<Void>.makeStream()
        var persistence = PersistenceClient.mock(routes: [first, second])
        persistence.fetchRouteSummary = { id in
            if id == first.id { for await _ in gate.stream { break } }
            return id == first.id ? first : second
        }
        persistence.fetchRides = {
            [RideListSummary(id: UUID(), title: "", startedAt: .distantPast, distanceMeters: 10_000, durationSeconds: 1_000)]
        }
        let store = TestStore(initialState: StartSheetFeature.State()) {
            StartSheetFeature()
        } withDependencies: {
            $0.persistenceClient = persistence
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.path(.push(id: 0, state: .routePicker(RoutePickerFeature.State()))))
        await store.send(.path(.element(id: 0, action: .routePicker(.delegate(.routeSelected(first.reference))))))
        await store.send(.path(.push(id: 1, state: .routePicker(RoutePickerFeature.State()))))
        await store.send(.path(.element(id: 1, action: .routePicker(.delegate(.routeSelected(second.reference))))))
        // 10 m/s from the recent ride, over the second route.
        await store.receive(.rideEstimateLoaded(second.distanceMeters / 10)) { $0.rideEstimate = second.distanceMeters / 10 }
        gate.continuation.yield()
        await store.finish()
        #expect(store.state.rideEstimate == second.distanceMeters / 10)
    }
}
