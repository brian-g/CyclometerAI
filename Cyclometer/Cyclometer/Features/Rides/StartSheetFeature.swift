import ComposableArchitecture
import Foundation
import os
import SwiftUI

private let logger = Logger.cyclometer(.routes)

/// S05.1 — Start Ride sheet. Global (app-level) setup screen: the ride's route — which S05.2,
/// pushed on the sheet's own stack, changes — the Phase 2 bike placeholder, the weather where the
/// ride starts over the hours it will take (#149, #559), and a live Sensors group. Presented by `AppFeature` via `@Presents`; the "Start Ride" CTA bubbles up as
/// `.delegate(.startRide)`, carrying the route, for the parent to begin the ride.
///
/// The CTA writes the ride's `Ride` row before that delegate is sent (#344). A ride without its
/// row has nothing to checkpoint or finalize and never reaches Rides, so a failed write keeps
/// the rider here with an alert, before the dashboard opens or any sensor starts recording.
@Reducer
struct StartSheetFeature {

    @Dependency(\.variaRadarClient) var variaRadarClient
    @Dependency(\.bleHRClient) var bleHRClient
    @Dependency(\.bleCSCClient) var bleCSCClient
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.persistenceClient) var persistenceClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date) var date
    @Dependency(\.weatherClient) var weatherClient
    @Dependency(\.networkStatus) var networkStatus
    @Dependency(\.locationClient) var locationClient
    @Dependency(\.permissionsClient) var permissionsClient

    private enum CancelID { case rideEstimate, weather }

    @ObservableState
    struct State: Equatable {
        @Shared(.appPreferences) var preferences
        /// Live connection status and battery per category, fed by the client streams.
        /// Whether a category is paired at all — and what the sensor is called — comes
        /// from `preferences`, never from here.
        var sensors: [SensorRow] = SensorRow.Kind.allCases.map { SensorRow(kind: $0) }

        /// The route the ride will follow, nil for a free ride (#196). Seeded by S20's "Use This
        /// Route" when that is what opened the sheet; S05.2 changes it.
        ///
        /// Here rather than in `AppFeature`, so it lives exactly as long as the sheet: Cancel, a
        /// swipe and starting the ride all discard it, and the next Start Ride from any tab opens on
        /// a free ride.
        var route: RouteReference? = nil

        /// Whether the ride will be followed turn by turn — the rider's last choice, remembered in
        /// `AppPreferences` (#197 review). Only offered while a route is chosen.
        var isTurnByTurnEnabled: Bool { preferences.isTurnByTurnEnabled }

        /// The sheet's own navigation stack: S05.2, pushed from the Route row (#196).
        var path = StackState<Path.State>()

        /// The ride whose `Ride` row is being written. A second tap in the meantime would start a
        /// second ride, and `AppFeature`'s launch-time resume check has to know this row is not
        /// an orphan (#344).
        var pendingRideId: UUID?
        var isStarting: Bool { pendingRideId != nil }
        /// The row couldn't be written (#344).
        @Presents var alert: AlertState<Action.Alert>?

        /// The rider's units for the wind.
        var unitSystem: UnitSystem { preferences.preferredUnit }

        /// The weather where the ride starts (#149): the route's first point when one is chosen
        /// (#559), else the rider's position. Fetched as the sheet opens and again when the route
        /// changes.
        var weather: StartSheetWeather = .loading

        /// How long a ride on the chosen route will take, from the rider's own rides
        /// (`RideDurationEstimate`). Nil with no route, or nothing to estimate from, and then the
        /// forecast covers `AttributedForecast.defaultRideWindow`.
        var rideEstimate: TimeInterval?

        /// The strip's hours: the one under way when the weather was fetched, then each hour that
        /// starts before the ride is expected to end.
        var forecastHours: [WeatherReading] {
            guard case let .loaded(forecast) = weather else { return [] }
            return forecast.rideHours(estimate: rideEstimate)
        }

        /// What the Route row pushes: S05.2, opened on the sheet's current answer so that answer is the
        /// one checked. Built here rather than in the view, so a test holds it to that.
        var routePicker: Path.State {
            .routePicker(RoutePickerFeature.State(selection: route))
        }

        /// The rows the sheet shows: one per paired role, whatever its connection state.
        ///
        /// Keyed on the durable record rather than on live status, which is what makes a
        /// paired sensor the app is not connected to appear at all — out of range, or
        /// simply not reconnected yet.
        ///
        /// An unpaired category is absent rather than shown empty — pairing is S11's
        /// (#100), and this sheet runs no discovery it could offer to pair *from*.
        var pairedRows: [SensorRow] {
            sensors.compactMap { row in
                guard let record = preferences.pairedSensor(for: row.kind.role) else { return nil }
                var row = row
                // The name at pairing time, so a sensor that is out of range is still
                // named. No client can answer for one it isn't connected to.
                row.name = record.displayName
                // From the last ride, not this sheet: a sagging cell reads high at rest,
                // so the sheet itself would almost never see it (#391).
                row.warning = preferences.sensorHealth[record.peripheralID]?.warning
                return row
            }
        }
    }

    enum Action: Equatable {
        case task
        case radarStatusUpdated(VariaRadarClient.ConnectionState)
        case hrPairingUpdated(Bool)
        case speedStatusUpdated(BLECSCClient.ConnectionState)
        case cadenceStatusUpdated(BLECSCClient.ConnectionState)
        case batteryUpdated(SensorRow.Kind, Int?)
        case cancelButtonTapped
        case startRideButtonTapped
        case rideCreated(rideId: UUID, route: RouteReference?)
        case rideCreationFailed
        case turnByTurnChanged(Bool)
        case weatherLoaded(AttributedForecast)
        case weatherUnavailable(StartSheetWeather.Unavailable)
        case rideEstimateLoaded(TimeInterval?)
        case alert(PresentationAction<Alert>)
        case path(StackActionOf<Path>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// The ride's id, whose `Ride` row now exists (#344), and the sheet's route, nil for a
            /// free ride (#196), for `AppFeature` to hand to the ride.
            case startRide(rideId: UUID, route: RouteReference?)
        }

        @CasePathable
        enum Alert: Equatable {}
    }

    /// What the sheet can push (#196). `Equatable` in extensions below, as TCA 1.25 asks.
    @Reducer
    enum Path {
        case routePicker(RoutePickerFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .task:
                // Reflect live connection status from each client. Streams replay current
                // state on subscribe, so already-connected sensors show immediately.
                //
                // The pairing scan that makes those statuses worth reading is taken by
                // `AppFeature` around this sheet's presentation, not here. It has to be:
                // every dismissal path clears the presented state before SwiftUI runs
                // `onDisappear`, so a release sent from inside the sheet reaches an absent
                // destination and is dropped — leaving the radio on for the rest of the
                // process. Only the owner of the presentation knows both ends of the
                // lifetime.
                return .merge(
                    fetchWeather(state.route),
                    // A route S20's "Use This Route" opened the sheet on.
                    estimateRide(state.route),
                    .run { send in
                        for await status in variaRadarClient.connectionState() {
                            await send(.radarStatusUpdated(status))
                        }
                    },
                    .run { send in
                        for await paired in bleHRClient.pairingStatus() {
                            await send(.hrPairingUpdated(paired))
                        }
                    },
                    .run { send in
                        for await status in bleCSCClient.connectionState(.speed) {
                            await send(.speedStatusUpdated(status))
                        }
                    },
                    .run { send in
                        for await status in bleCSCClient.connectionState(.cadence) {
                            await send(.cadenceStatusUpdated(status))
                        }
                    },
                    // Battery is a separate stream per sensor rather than part of the
                    // status ones: it is read once per connection and arrives well
                    // after the status transition that preceded it.
                    .run { send in
                        for await level in variaRadarClient.batteryLevel() {
                            await send(.batteryUpdated(.radar, level))
                        }
                    },
                    .run { send in
                        for await level in bleHRClient.batteryLevel() {
                            await send(.batteryUpdated(.heartRate, level))
                        }
                    },
                    .run { send in
                        for await level in bleCSCClient.batteryLevel(.speed) {
                            await send(.batteryUpdated(.speed, level))
                        }
                    },
                    .run { send in
                        for await level in bleCSCClient.batteryLevel(.cadence) {
                            await send(.batteryUpdated(.cadence, level))
                        }
                    }
                )

            case .radarStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .radar)
                return .none

            case .hrPairingUpdated(let connected):
                // The HR client exposes a bool meaning "notifications enabled and BPM
                // flowing", not the pairing record — which is why the row's existence
                // comes from `preferences` and only its badge comes from here. It needs
                // no third state: with the scan open, "not connected" is "still looking".
                state.setStatus(connected ? .connected : .searching, for: .heartRate)
                return .none

            case .speedStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .speed)
                return .none

            case .cadenceStatusUpdated(let status):
                state.setStatus(Self.status(from: status), for: .cadence)
                return .none

            case .batteryUpdated(let kind, let percent):
                state.setBattery(percent, for: kind)
                return .none

            case .cancelButtonTapped:
                return .run { _ in await dismiss() }

            case .startRideButtonTapped:
                guard !state.isStarting else { return .none }
                let rideId = uuid()
                state.pendingRideId = rideId
                return .run { [persistenceClient, startedAt = date.now, route = state.route] send in
                    do {
                        try await persistenceClient.createRide(rideId, startedAt, route)
                        // The route as written, not as the sheet has it now: the ride and its
                        // row must agree on it.
                        await send(.rideCreated(rideId: rideId, route: route))
                    } catch {
                        // Logged in RidePersistenceActor.
                        await send(.rideCreationFailed)
                    }
                }

            case let .rideCreated(rideId, route):
                state.pendingRideId = nil
                return .send(.delegate(.startRide(rideId: rideId, route: route)))

            case .rideCreationFailed:
                state.pendingRideId = nil
                state.alert = AlertState {
                    TextState("Couldn't Start Ride")
                } actions: {
                    ButtonState(role: .cancel) { TextState("OK") }
                } message: {
                    TextState("Your ride couldn't be saved, so it wasn't started. Try again.")
                }
                return .none

            case .turnByTurnChanged(let isOn):
                // The preference itself, not a copy: the ride reads it from there — a ride resumed
                // after a kill included.
                state.$preferences.withLock { $0.isTurnByTurnEnabled = isOn }
                return .none

            case let .path(.element(id: id, action: .routePicker(.delegate(.routeSelected(route))))):
                // The sheet pops rather than the picker dismissing itself, so the answer and the
                // navigation land in the same pass — and a test can assert both.
                let isNewStart = route?.id != state.route?.id
                state.route = route
                state.path.pop(from: id)
                // The last route's estimate is no answer for this one: the default until it lands.
                state.rideEstimate = nil
                // Re-picking the same route starts in the same place: its weather stands (#559).
                guard isNewStart else { return estimateRide(route) }
                state.weather = .loading
                return .merge(estimateRide(route), fetchWeather(route))

            case .weatherLoaded(let forecast):
                state.weather = .loaded(forecast)
                return .none

            case .weatherUnavailable(let reason):
                state.weather = .unavailable(reason)
                return .none

            case .rideEstimateLoaded(let estimate):
                state.rideEstimate = estimate
                return .none

            case .path, .delegate, .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .forEach(\.path, action: \.path)
    }

    /// The weather where the ride starts (#149). A newer route cancels an older one's fetch, so a
    /// slow answer for the last start can't land on this one.
    private func fetchWeather(_ route: RouteReference?) -> Effect<Action> {
        .run { send in
            let start: RouteCoordinate
            do throws(StartSheetWeather.Unavailable) {
                start = if let route { try await routeStart(route) } else { try await riderPosition() }
            } catch {
                await send(.weatherUnavailable(error))
                return
            }
            do {
                let forecast = try await weatherClient.attributedForecast(start, now: { date.now })
                await send(.weatherLoaded(forecast))
            } catch {
                // Logged in WeatherClient. WeatherKit's error can't say whether the device is
                // offline, so the network path is asked, and only now.
                await send(.weatherUnavailable(await networkStatus.isOffline() ? .offline : .failed))
            }
        }
        .cancellable(id: CancelID.weather, cancelInFlight: true)
    }

    /// A route's first point (#559), as S20 asks about it: where the ride begins, wherever the
    /// rider is now — at home, say, before driving to the trailhead. A route's start is a fixed
    /// coordinate, so it needs no location permission. A route that can't be read, or whose
    /// polyline didn't decode, has no start: `.failed`, never the rider's position instead, which
    /// would put another place's weather under this route.
    private func routeStart(_ route: RouteReference) async throws(StartSheetWeather.Unavailable) -> RouteCoordinate {
        let detail: RouteDetail?
        do {
            detail = try await persistenceClient.fetchRoute(route.id)
        } catch {
            logger.error("fetchRoute failed for \(route.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw .failed
        }
        guard let start = detail?.coordinates.first else {
            logger.error("fetchRoute found no start for route \(route.id, privacy: .public)")
            throw .failed
        }
        return start
    }

    /// The rider's position, for a free ride. Location *status*, never a request: S01 owns the
    /// location prompt, and a sheet that opens with location off still works without it.
    ///
    /// Only location that is off reads as `.noLocation`, whose message asks the rider to turn it on.
    /// Location that is on but gave no fix in time (indoors, say) is `.failed`: turning on what is
    /// already on would fix nothing.
    private func riderPosition() async throws(StartSheetWeather.Unavailable) -> RouteCoordinate {
        guard await permissionsClient.status(.locationWhenInUse).isGranted else { throw .noLocation }
        guard let position = await locationClient.currentCoordinate() else { throw .failed }
        return RouteCoordinate(latitude: position.latitude, longitude: position.longitude)
    }

    /// How long a ride on `route` will take, for how far ahead the forecast looks (#149). A failed
    /// read is no estimate, and the forecast keeps its default. A newer pick cancels an older one's
    /// read, so a slow answer for the last route can't land on this one.
    private func estimateRide(_ route: RouteReference?) -> Effect<Action> {
        guard let route else { return .cancel(id: CancelID.rideEstimate) }
        return .run { send in
            // A failed read is no estimate: the forecast keeps its default.
            await send(.rideEstimateLoaded(try? await persistenceClient.rideEstimate(forRoute: route.id)))
        }
        .cancellable(id: CancelID.rideEstimate, cancelInFlight: true)
    }

    // Map the shared client lifecycle onto the sheet's two-state badge (UX.md §S05.1).
    // This was two identical overloads until #98 gave the radar and CSC clients one
    // `SensorConnectionState` between them.
    //
    // Everything short of connected reads Searching, including `.disconnected`, and that
    // is true rather than charitable: the sheet holds a pairing scan open for as long as
    // it is up, so a paired sensor the client is not talking to is one it is actively
    // looking for. The rider setting up a ride is asking one question — is it up yet.
    private static func status(from state: SensorConnectionState) -> SensorRow.Status {
        switch state {
        case .connected, .active: .connected
        case .disconnected, .scanning, .connecting, .reconnecting: .searching
        }
    }
}

extension StartSheetFeature.Path.State: Equatable {}
extension StartSheetFeature.Path.Action: Equatable {}

extension StartSheetFeature.State {
    mutating func setStatus(_ status: SensorRow.Status, for kind: SensorRow.Kind) {
        guard let index = sensors.firstIndex(where: { $0.kind == kind }) else { return }
        sensors[index].status = status
    }

    mutating func setBattery(_ percent: Int?, for kind: SensorRow.Kind) {
        guard let index = sensors.firstIndex(where: { $0.kind == kind }) else { return }
        sensors[index].batteryPercent = percent
    }
}

/// The Start sheet's Weather group (#149).
enum StartSheetWeather: Equatable {
    case loading
    case unavailable(Unavailable)
    case loaded(AttributedForecast)

    /// An `Error` so that each start — a route's, the rider's — can say why it has none (#559).
    enum Unavailable: Error, Equatable {
        /// A free ride with location off for the app: the rider can fix it by turning it on. A
        /// route's start needs no location, so a ride on one never reads this (#559).
        case noLocation
        /// WeatherKit failed with no usable network (#204): the rider can fix it by going online.
        case offline
        /// No weather to show for any other reason: location is on but gave no fix in time, the
        /// chosen route has no start that could be read (#559), or WeatherKit failed online (or
        /// the App ID lacks its App Service).
        case failed
    }
}

/// A single sensor row in the Start sheet's Sensors group.
struct SensorRow: Equatable, Identifiable {
    enum Kind: CaseIterable {
        case radar, heartRate, speed, cadence
    }

    /// Two states, not three. An unpaired category has no row at all — see
    /// `StartSheetFeature.State.pairedRows` — and everything short of connected is a
    /// sensor the sheet's own scan is still looking for.
    enum Status: Equatable {
        case connected, searching
    }

    var kind: Kind
    /// The sensor's name, filled in from its `PairedSensor` record. Nil only for a
    /// record written before the peripheral advertised one.
    var name: String? = nil
    var status: Status = .searching
    /// Battery percentage (0–100), or nil when the sensor is disconnected or doesn't
    /// expose the Battery Service. Rendered only when non-nil and connected.
    var batteryPercent: Int? = nil
    /// What the sensor's last ride said about it (#391), filled in from
    /// `AppPreferences.sensorHealth`. Shown whatever the status: a sensor still searching may be the dead cell.
    var warning: SensorWarning? = nil

    var id: Kind { kind }
}

extension SensorRow.Kind {
    /// The persisted role this category stands for. One-to-one: the sheet has no row
    /// for `.power`, which is Phase 3 hardware.
    var role: SensorRole {
        switch self {
        case .radar: .radar
        case .heartRate: .heartRate
        case .speed: .speed
        case .cadence: .cadence
        }
    }

    var displayName: String {
        switch self {
        case .radar: "Radar"
        case .heartRate: "Heart Rate"
        case .speed: "Speed"
        case .cadence: "Cadence"
        }
    }

    /// Both defer to `SensorRowStyle`, shared with S11 — the two lists ask different
    /// questions (a fixed role here, a discovered device there) but must answer with the
    /// same colour, or the rider learns a palette on one screen that the other ignores.
    var systemImage: String { role.symbolName }

    var tint: Color { role.tint }
}

extension SensorRow.Status {
    /// Badge text + colors, mirroring the app's capsule-badge idiom (`SpeedWidgetView.sourceBadge`).
    var badge: (label: String, foreground: Color, background: Color) {
        switch self {
        case .connected: ("Connected", .cyTextOnPrimary, .cyPrimary)
        case .searching: ("Searching", .cyTextTertiary, .cyBgTertiary)
        }
    }
}
