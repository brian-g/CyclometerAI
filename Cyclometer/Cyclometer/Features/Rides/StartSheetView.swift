import ComposableArchitecture
import SwiftUI

/// S05.1 — Start Ride sheet. TCA-wired setup screen presented from any tab.
///
/// Brings its own stack, driven by `StartSheetFeature.path`, so the Route row pushes S05.2 as
/// reducer state (#196).
struct StartSheetView: View {
    @Bindable var store: StoreOf<StartSheetFeature>

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                Section("Ride Setup") {
                    LabeledContent("Bike") { Text(NewRideDemoData.bikeName) }
                    // `routePicker` opens S05.2 with the sheet's answer checked.
                    NavigationLink(state: store.routePicker) {
                        ActiveRouteRow(routeName: store.route?.name)
                    }
                    // Only with a route: a free ride has nothing to follow (#197 review). Bound the
                    // way Settings' toggles are, through an action rather than the shared state.
                    if store.route != nil {
                        Toggle("Turn-by-Turn", isOn: $store.isTurnByTurnEnabled.sending(\.turnByTurnChanged))
                    }
                }
                StartSheetWeatherSection(weather: store.weather, hours: store.forecastHours, unit: store.unitSystem)
                Section("Sensors") {
                    // Every paired sensor, connected or not — a rider setting up a ride
                    // needs to see that the strap they paired is the one about to be
                    // used, and whether it is up. Unpaired categories are absent, so
                    // with nothing paired the group says so rather than implying a scan
                    // that is not running.
                    if store.pairedRows.isEmpty {
                        HStack() {
                            Spacer()
                            Text("No paired sensors")
                                .foregroundStyle(Color.cyTextSecondary)
                            Spacer()
                        }
                    } else {
                        ForEach(store.pairedRows) { sensor in
                            SensorStatusRow(sensor: sensor)
                        }
                    }
                }
            }
            .navigationTitle("New Ride")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton(disabled: store.isStarting) { store.send(.cancelButtonTapped) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.startRideButtonTapped)
                    } label: {
                        Label("Start Ride", systemImage: "play.fill")
                    }.labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyPrimary)
                }
            }
        } destination: { pathStore in
            switch pathStore.case {
            case .routePicker(let pickerStore):
                RoutePickerView(store: pickerStore)
            }
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        // While the `Ride` row is being written: a dismissal then would strand a row with no ride
        // behind it, which the next launch would resume (#344).
        .interactiveDismissDisabled(store.isStarting)
        .task { await store.send(.task).finish() }
    }
}

/// The Weather group (#149): current conditions and the ride's hours, or why there are none. Its
/// footer carries WeatherKit's attribution, shown only with WeatherKit data above it.
///
/// Internal rather than private so `StartSheetSnapshotTests` can pin it, as with `SensorStatusRow`.
struct StartSheetWeatherSection: View {
    let weather: StartSheetWeather
    /// `StartSheetFeature.State.forecastHours`: the strip's hours, picked for the ride.
    let hours: [WeatherReading]
    let unit: UnitSystem

    var body: some View {
        Section {
            switch weather {
            case .loading:
                centered { ProgressView() }
            case .unavailable(.noLocation):
                centered { message("Turn on Location to see the weather here") }
            case .unavailable(.failed):
                centered { message("Weather unavailable") }
            case .loaded(let forecast):
                CurrentWeatherRow(reading: forecast.current, unit: unit)
                HourlyForecastStrip(hours: hours)
            }
        } header: {
            Text("Weather")
        } footer: {
            if case .loaded(let forecast) = weather {
                WeatherAttributionFooter(attribution: forecast.attribution)
            }
        }
    }

    /// Centred the way the Sensors group's "No paired sensors" is.
    private func centered(@ViewBuilder _ content: () -> some View) -> some View {
        HStack {
            Spacer()
            content()
            Spacer()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.cyTextSecondary)
            .multilineTextAlignment(.center)
    }
}

/// The Ride Setup group's Route row: the route the ride will follow, or "None" (#196).
///
/// Internal rather than private so `StartSheetSnapshotTests` can pin it, as with `SensorStatusRow`.
/// The disclosure chevron is the `NavigationLink`'s, not this view's.
struct ActiveRouteRow: View {
    let routeName: String?

    var body: some View {
        LabeledContent("Route") {
            // The token, not `LabeledContent`'s ambient secondary style, which a snapshot reference
            // would record as whatever the host resolved.
            Text(routeName ?? "None")
                .foregroundStyle(Color.cyTextSecondary)
                .lineLimit(1)
        }
    }
}

/// One sensor *category* in the Start sheet. Shares `SensorListRowView` with the
/// Sensors settings screen, which lists discovered *devices* instead.
///
/// No action: every row here is already paired, and pairing lives on S11. The row that
/// used to carry "Tap to Pair" was reachable only through a status the sheet can no
/// longer be in — offering it now would mean running discovery this screen does not do.
///
/// Internal rather than private so `StartSheetSnapshotTests` can pin it. The sheet as a
/// whole cannot be snapshotted: its toolbar renders blank inside a `UIHostingController`,
/// and a reference recorded from that is a test that can never fail.
struct SensorStatusRow: View {
    let sensor: SensorRow

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SensorListRowView(
                icon: sensor.kind.systemImage,
                iconTint: sensor.kind.tint,
                title: sensor.kind.displayName,
                // Device name only; the status control conveys connection state, so we
                // avoid a subtitle that could contradict it.
                subtitle: sensor.name
            ) {
                VStack(alignment: .trailing) {
                    SensorStatusBadge(status: sensor.status)
                    if let battery = sensor.batteryPercent, sensor.status == .connected {
                        SensorBatteryLabel(percent: battery)
                    }
                }
            }
            // Full width under the row: the hint is too long for the trailing column.
            if let warning = sensor.warning {
                SensorWarningLabel(warning: warning, isFromLastRide: true)
                    .padding(.bottom, Spacing.xs)
            }
        }
    }
}

// MARK: - Previews

private extension DependencyValues {
    /// The Weather group from the fixture client at a fixed position, so no preview reads live
    /// location or WeatherKit (#149).
    mutating func previewWeather() {
        permissionsClient = .testValue
        locationClient = .testValue
        locationClient.currentCoordinate = { Coordinate(latitude: 46.8772, longitude: -96.7898) }
        weatherClient = .testValue
        // The fixture forecast is dated, so "now" has to be inside it for the strip to have hours.
        date = .constant(WeatherReading.fixtureDate.addingTimeInterval(40 * 60))
    }
}

// The rows come from the paired records, so the preview has to seed them — and in the
// same dependency scope the store reads, or the seed lands in different storage.
//
// Each preview mocks the route library, so the Route row pushes a populated S05.2. There is no
// `PersistenceClient.previewValue`: without the mock a preview reads the live store.
#Preview("Start Sheet") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        @Shared(.appPreferences) var preferences
        $preferences.withLock {
            $0.pairedSensors = [
                PairedSensor(peripheralID: UUID(), role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: UUID(), role: .heartRate, displayName: "HRM-Dual with Long Name"),
                PairedSensor(peripheralID: UUID(), role: .speed, displayName: "Wahoo Cadence 8683")
            ]
        }
        return StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(
                    sensors: [
                        SensorRow(kind: .radar, status: .connected, batteryPercent: 82),
                        SensorRow(kind: .heartRate, status: .connected, batteryPercent: 14),
                        // Paired but out of range — the case the sheet exists to show.
                        SensorRow(kind: .speed, status: .searching),
                        SensorRow(kind: .cadence, status: .searching)
                    ]
                )
            ) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                $0.previewWeather()
            }
        )
    }
}

/// The last ride flagged two sensors (#391): one sagging battery, one flapping link.
#Preview("Start Sheet — sensor warnings") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        @Shared(.appPreferences) var preferences
        let rideId = UUID()
        let radar = UUID()
        let speed = UUID()
        $preferences.withLock {
            $0.pairedSensors = [
                PairedSensor(peripheralID: radar, role: .radar, displayName: "Varia RTL515"),
                PairedSensor(peripheralID: speed, role: .speed, displayName: "Wahoo SPEED")
            ]
            $0.sensorHealth = [
                radar: SensorHealthReport(rideId: rideId, minBatteryPercent: 64, maxLinkLossesPerWindow: 12),
                speed: SensorHealthReport(rideId: rideId, minBatteryPercent: 0, maxLinkLossesPerWindow: 43)
            ]
        }
        return StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(
                    sensors: [
                        SensorRow(kind: .radar, status: .connected, batteryPercent: 82),
                        // Reads high at rest — the reason the warning comes from the last ride.
                        SensorRow(kind: .speed, status: .connected, batteryPercent: 95)
                    ]
                )
            ) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                $0.previewWeather()
            }
        )
    }
}

#Preview("Start Sheet — nothing paired") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        StartSheetView(
            store: Store(initialState: StartSheetFeature.State()) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                $0.previewWeather()
            }
        )
    }
}

/// The weather group in each state, as the sheet draws it (#149).
#Preview("Weather — loaded") {
    List {
        StartSheetWeatherSection(
            weather: .loaded(StartSheetForecast(
                current: .fixture,
                hourly: WeatherReading.fixtureHourly,
                attribution: .fixture,
                fetchedAt: WeatherReading.fixtureDate.addingTimeInterval(40 * 60)
            )),
            hours: Array(WeatherReading.fixtureHourly.prefix(4)),
            unit: .metric
        )
    }
}

#Preview("Weather — loading") {
    List { StartSheetWeatherSection(weather: .loading, hours: [], unit: .metric) }
}

#Preview("Weather — no location") {
    List { StartSheetWeatherSection(weather: .unavailable(.noLocation), hours: [], unit: .metric) }
}

#Preview("Weather — failed, dark") {
    List { StartSheetWeatherSection(weather: .unavailable(.failed), hours: [], unit: .metric) }
        .preferredColorScheme(.dark)
}

/// As S20's "Use This Route" opens it.
#Preview("Start Sheet — route chosen") {
    withDependencies {
        $0.defaultFileStorage = .inMemory
    } operation: {
        StartSheetView(
            store: Store(
                initialState: StartSheetFeature.State(route: RouteSummary.previewRoutes[1].reference)
            ) {
                StartSheetFeature()
            } withDependencies: {
                $0.variaRadarClient = .testValue
                $0.bleHRClient = .testValue
                $0.bleCSCClient = .testValue
                $0.persistenceClient = .mock(routes: RouteSummary.previewRoutes)
                $0.previewWeather()
            }
        )
    }
}
