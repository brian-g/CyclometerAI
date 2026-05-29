#!/usr/bin/env bash
# =============================================================================
#  Cyclometer — Xcode Project Scaffold
#  Bundle ID  : name.glaeske.cyclometer
#  Platform   : iOS 26+  (min device: iPhone 11 / A13 Bionic)
#  Arch       : TCA (The Composable Architecture)
#  Deps       : Swift Package Manager only
#  Tests      : XCTest + Swift Testing framework
#
#  Run from inside the CyclometerAI project folder:
#    chmod +x scaffold.sh && ./scaffold.sh
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/Cyclometer"
TESTS="$ROOT/CyclometerTests"
UI_TESTS="$ROOT/CyclometerUITests"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'
log()  { echo -e "${CYAN}  ▸${RESET} $1"; }
ok()   { echo -e "${GREEN}  ✓${RESET} $1"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $1"; }

echo ""
echo -e "${GREEN}🚴  Cyclometer Scaffold — iOS 26 · TCA · SPM${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Directories ────────────────────────────────────────────────────────────

log "Creating directory tree..."

mkdir -p \
  "$APP/App" \
  "$APP/Features/RideMetrics" \
  "$APP/Features/MapNavigation" \
  "$APP/Features/RadarDetail" \
  "$APP/Features/Settings" \
  "$APP/Features/Onboarding" \
  "$APP/Clients/BLE" \
  "$APP/Clients/Location" \
  "$APP/Clients/HealthKit" \
  "$APP/Clients/Persistence" \
  "$APP/Clients/Audio" \
  "$APP/Clients/Haptics" \
  "$APP/Models" \
  "$APP/UI/Components/RadarColumn" \
  "$APP/UI/Components/MetricTile" \
  "$APP/UI/Components/HRZoneBadge" \
  "$APP/UI/DesignSystem" \
  "$APP/Resources/Assets.xcassets/AppIcon.appiconset" \
  "$APP/Resources/Assets.xcassets/AccentColor.colorset" \
  "$APP/Resources/Fonts" \
  "$APP/Resources/Sounds" \
  "$TESTS/Features" \
  "$TESTS/Clients" \
  "$TESTS/Models" \
  "$UI_TESTS"

ok "Directory tree created."
echo ""

# ── 2. App Entry Point ────────────────────────────────────────────────────────

log "Writing App/..."

cat > "$APP/App/CyclometerApp.swift" << 'SWIFT'
import SwiftUI
import ComposableArchitecture

@main
struct CyclometerApp: App {
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
    }
}
SWIFT

cat > "$APP/App/AppFeature.swift" << 'SWIFT'
import ComposableArchitecture

/// Root reducer — owns the three-page paged navigation state.
/// Pages: Ride Metrics (1) · Map/Navigation (2) · Radar Detail (3)
@Reducer
struct AppFeature {

    @ObservableState
    struct State: Equatable {
        var rideMetrics    = RideMetricsFeature.State()
        var mapNavigation  = MapNavigationFeature.State()
        var radarDetail    = RadarDetailFeature.State()
        var selectedPage   = Page.rideMetrics
        // Radar state is owned here so RideMetricsFeature can subscribe to it.
        // The radar column is only rendered on the Ride Metrics page.
        var radarTargets: [RadarTarget] = []
        var isRadarPaired: Bool = false
    }

    enum Page: Int, CaseIterable, Equatable {
        case rideMetrics   = 0
        case mapNavigation = 1
        case radarDetail   = 2
    }

    enum Action {
        case rideMetrics(RideMetricsFeature.Action)
        case mapNavigation(MapNavigationFeature.Action)
        case radarDetail(RadarDetailFeature.Action)
        case pageSelected(Page)
        case radarTargetsUpdated([RadarTarget])
        case radarPairingChanged(Bool)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.rideMetrics,   action: \.rideMetrics)   { RideMetricsFeature() }
        Scope(state: \.mapNavigation, action: \.mapNavigation)  { MapNavigationFeature() }
        Scope(state: \.radarDetail,   action: \.radarDetail)    { RadarDetailFeature() }

        Reduce { state, action in
            switch action {
            case .pageSelected(let page):
                state.selectedPage = page
                return .none
            case .radarTargetsUpdated(let targets):
                state.radarTargets = targets
                return .none
            case .radarPairingChanged(let paired):
                state.isRadarPaired = paired
                return .none
            default:
                return .none
            }
        }
    }
}
SWIFT

cat > "$APP/App/AppView.swift" << 'SWIFT'
import SwiftUI
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        // Paged navigation — three full-screen swipeable pages.
        // Page 1: Ride Metrics (hosts the radar column internally)
        // Page 2: Map / Navigation
        // Page 3: Radar Detail
        TabView(selection: $store.selectedPage.sending(\.pageSelected)) {
            RideMetricsView(
                store: store.scope(state: \.rideMetrics, action: \.rideMetrics)
            )
            .tag(AppFeature.Page.rideMetrics)

            MapNavigationView(
                store: store.scope(state: \.mapNavigation, action: \.mapNavigation)
            )
            .tag(AppFeature.Page.mapNavigation)

            RadarDetailView(
                store: store.scope(state: \.radarDetail, action: \.radarDetail)
            )
            .tag(AppFeature.Page.radarDetail)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}
SWIFT

ok "App entry point written."

# ── 3. Features ───────────────────────────────────────────────────────────────

log "Writing Features/..."

# ── RideMetrics ──

cat > "$APP/Features/RideMetrics/RideMetricsFeature.swift" << 'SWIFT'
import ComposableArchitecture

/// Page 1 — Primary ride dashboard.
/// Hero: speed (82 pt). Secondary grid: HR zone, cadence, distance, elapsed time.
@Reducer
struct RideMetricsFeature {

    @ObservableState
    struct State: Equatable {
        var speedKPH:       Double = 0.0
        var heartRateBPM:   Int    = 0
        var hrZone:         Int    = 0     // 1–5; computed from Karvonen at query time
        var cadenceRPM:     Int    = 0
        var distanceKM:     Double = 0.0
        var elapsedSeconds: Int    = 0
        var isRiding:       Bool   = false
        var isPaused:       Bool   = false
        // HealthKit parameters for Karvonen formula
        var maxHeartRate:     Int  = 190
        var restingHeartRate: Int  = 55
    }

    enum Action {
        case onAppear
        case onDisappear
        case speedUpdated(Double)
        case heartRateUpdated(Int)
        case cadenceUpdated(Int)
        case elapsedTick
        case startRideTapped
        case pauseRideTapped
        case resumeRideTapped
        case stopRideTapped
        case healthKitValuesLoaded(maxHR: Int, restingHR: Int)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // TODO: start BLE subscriptions, HealthKit fetch
                return .none

            case .onDisappear:
                return .none

            case .speedUpdated(let kph):
                state.speedKPH = kph
                return .none

            case .heartRateUpdated(let bpm):
                state.heartRateBPM = bpm
                state.hrZone = HeartRateZone.zone(
                    bpm: bpm,
                    maxHR: state.maxHeartRate,
                    restingHR: state.restingHeartRate
                ).rawValue
                return .none

            case .cadenceUpdated(let rpm):
                state.cadenceRPM = rpm
                return .none

            case .elapsedTick:
                if state.isRiding && !state.isPaused {
                    state.elapsedSeconds += 1
                }
                return .none

            case .startRideTapped:
                state.isRiding = true
                state.isPaused = false
                return .none

            case .pauseRideTapped:
                state.isPaused = true
                return .none

            case .resumeRideTapped:
                state.isPaused = false
                return .none

            case .stopRideTapped:
                state.isRiding = false
                state.isPaused = false
                return .none

            case .healthKitValuesLoaded(let maxHR, let restingHR):
                state.maxHeartRate     = maxHR
                state.restingHeartRate = restingHR
                return .none
            }
        }
    }
}
SWIFT

cat > "$APP/Features/RideMetrics/RideMetricsView.swift" << 'SWIFT'
import SwiftUI
import ComposableArchitecture

struct RideMetricsView: View {
    let store: StoreOf<RideMetricsFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()

            // ── Root layout: metrics content + 24pt radar column ────────────
            // The radar column is part of the layout — it takes real horizontal
            // space from the widget grid. It collapses to zero width (not hidden
            // with opacity) when no Varia device is paired.
            HStack(spacing: 0) {

                // ── Left: all ride metrics ───────────────────────────────────
                VStack(spacing: 0) {
                    Spacer()

                    // Hero speed
                    VStack(spacing: 4) {
                        Text(String(format: "%.1f", store.speedKPH))
                            .font(.cyHeroSpeed)
                            .foregroundStyle(Color.cyTextPrimary)
                            .monospacedDigit()

                        Text("km/h")
                            .font(.cyLabel)
                            .foregroundStyle(Color.cyTextSecondary)
                            .textCase(.uppercase)
                            .tracking(2)
                    }
                    .padding(.bottom, 32)

                    // Secondary metrics grid (2 columns)
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        MetricTileView(
                            label: "Heart Rate",
                            value: "\(store.heartRateBPM)",
                            unit: "bpm",
                            borderColor: Color.hrZone(store.hrZone)
                        )
                        MetricTileView(label: "Cadence",  value: "\(store.cadenceRPM)",                      unit: "rpm")
                        MetricTileView(label: "Distance", value: String(format: "%.2f", store.distanceKM),   unit: "km")
                        MetricTileView(label: "Time",     value: store.elapsedSeconds.formattedElapsed,      unit: "")
                    }
                    .padding(.horizontal, 16)

                    Spacer()

                    // Controls
                    HStack(spacing: 20) {
                        if !store.isRiding {
                            CYButton(label: "Start", style: .primary) {
                                store.send(.startRideTapped)
                            }
                        } else if store.isPaused {
                            CYButton(label: "Resume", style: .primary)      { store.send(.resumeRideTapped) }
                            CYButton(label: "Stop",   style: .destructive)  { store.send(.stopRideTapped) }
                        } else {
                            CYButton(label: "Pause",  style: .secondary)    { store.send(.pauseRideTapped) }
                            CYButton(label: "Stop",   style: .destructive)  { store.send(.stopRideTapped) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 48)
                }

                // ── Right: 24pt radar column (S06 spec) ──────────────────────
                // Vehicles positioned top (closest/critical) → bottom (furthest).
                // Zero-width when unpaired — takes no space, causes no reflow.
                if store.isRadarPaired {
                    RadarColumnView(targets: store.radarTargets)
                        .frame(width: 24)
                }
            }
        }
        .onAppear   { store.send(.onAppear) }
        .onDisappear { store.send(.onDisappear) }
    }
}

// MARK: - Button Component (local stub; move to Components/ if reused widely)

private struct CYButton: View {
    enum Style { case primary, secondary, destructive }
    let label: String
    let style: Style
    let action: () -> Void

    var bgColor: Color {
        switch style {
        case .primary:     return .cyPrimary
        case .secondary:   return .cyBgSecondary
        case .destructive: return .cyDestructive
        }
    }

    var fgColor: Color {
        style == .secondary ? .cyTextPrimary : .cyTextOnPrimary
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(fgColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Helpers

private extension Int {
    var formattedElapsed: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
SWIFT

# ── MapNavigation ──

cat > "$APP/Features/MapNavigation/MapNavigationFeature.swift" << 'SWIFT'
import ComposableArchitecture
import CoreLocation

/// Page 2 — Live map with GPX route overlay and turn-by-turn cues.
/// Navigation: GPX import only (no MKDirections routing). tribos.studio integration planned.
@Reducer
struct MapNavigationFeature {

    @ObservableState
    struct State: Equatable {
        var currentLocation: CLLocationCoordinate2D?
        var isNavigating: Bool = false
        var gpxRouteLoaded: Bool = false
        var currentTurnInstruction: String = ""
        var distanceToNextTurnM: Double = 0
    }

    enum Action {
        case onAppear
        case locationUpdated(CLLocationCoordinate2D)
        case loadGPXRoute(URL)
        case gpxRouteLoadedSuccessfully
        case gpxRouteLoadFailed(String)
        case startNavigation
        case stopNavigation
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            case .locationUpdated(let coord):
                state.currentLocation = coord
                return .none
            case .loadGPXRoute:
                // TODO: Parse GPX, build route
                return .none
            case .gpxRouteLoadedSuccessfully:
                state.gpxRouteLoaded = true
                return .none
            case .gpxRouteLoadFailed:
                state.gpxRouteLoaded = false
                return .none
            case .startNavigation:
                state.isNavigating = true
                return .none
            case .stopNavigation:
                state.isNavigating = false
                return .none
            }
        }
    }
}
SWIFT

cat > "$APP/Features/MapNavigation/MapNavigationView.swift" << 'SWIFT'
import SwiftUI
import ComposableArchitecture
import MapKit

struct MapNavigationView: View {
    let store: StoreOf<MapNavigationFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()
            // TODO: MapKit view with GPX route polyline overlay
            // TODO: Turn instruction strip at bottom
            VStack {
                Spacer()
                Text("Map & Navigation")
                    .font(.cyMetricMedium)
                    .foregroundStyle(Color.cyTextPrimary)
                Spacer()
            }
        }
        .onAppear { store.send(.onAppear) }
    }
}
SWIFT

# ── RadarDetail ──

cat > "$APP/Features/RadarDetail/RadarDetailFeature.swift" << 'SWIFT'
import ComposableArchitecture

/// Page 3 — Full-screen radar visualisation.
/// Entire page (and tab indicator dot) hidden when no Varia device is paired.
/// Target hardware: Garmin Varia RTL515 / RCT715 via raw CoreBluetooth BLE.
@Reducer
struct RadarDetailFeature {

    @ObservableState
    struct State: Equatable {
        var isRadarPaired: Bool = false
        var targets: [RadarTarget] = []
        var signalStrength: Int = 0   // RSSI dBm
    }

    enum Action {
        case onAppear
        case radarTargetsUpdated([RadarTarget])
        case pairingStatusChanged(Bool)
        case signalStrengthUpdated(Int)
        case pairNewDeviceTapped
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .none
            case .radarTargetsUpdated(let targets):
                state.targets = targets
                return .none
            case .pairingStatusChanged(let paired):
                state.isRadarPaired = paired
                return .none
            case .signalStrengthUpdated(let rssi):
                state.signalStrength = rssi
                return .none
            case .pairNewDeviceTapped:
                // TODO: Launch BLE pairing flow
                return .none
            }
        }
    }
}
SWIFT

cat > "$APP/Features/RadarDetail/RadarDetailView.swift" << 'SWIFT'
import SwiftUI
import ComposableArchitecture

struct RadarDetailView: View {
    let store: StoreOf<RadarDetailFeature>

    var body: some View {
        ZStack {
            Color.cyBgPrimary.ignoresSafeArea()

            if store.isRadarPaired {
                VStack {
                    Text("Radar Detail")
                        .font(.cyMetricMedium)
                        .foregroundStyle(Color.cyTextPrimary)
                    // TODO: Radar visualisation canvas
                    // (arc / linear strip / threat dots per PRD options)
                    ForEach(store.targets) { target in
                        Text("Vehicle @ \(Int(target.rangeMetre))m")
                            .foregroundStyle(Color.cyTextSecondary)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.cyTextTertiary)
                    Text("No radar paired")
                        .font(.cyMetricSmall)
                        .foregroundStyle(Color.cyTextSecondary)
                    Button("Pair Varia Radar") {
                        store.send(.pairNewDeviceTapped)
                    }
                    .foregroundStyle(Color.cyPrimary)
                }
            }
        }
        .onAppear { store.send(.onAppear) }
    }
}
SWIFT

ok "Features written."

# ── 4. TCA Clients ────────────────────────────────────────────────────────────

log "Writing Clients/..."

cat > "$APP/Clients/BLE/BLEClient.swift" << 'SWIFT'
import ComposableArchitecture
import CoreBluetooth

/// TCA dependency interface for CoreBluetooth central management.
struct BLEClient {
    var startScanning:  @Sendable ([CBUUID]) async -> Void
    var stopScanning:   @Sendable () async -> Void
    var peripherals:    @Sendable () -> AsyncStream<CBPeripheral>
}

extension BLEClient: DependencyKey {
    static let liveValue = BLEClient(
        startScanning:  { _ in /* CoreBluetooth live impl */ },
        stopScanning:   { /* CoreBluetooth live impl */ },
        peripherals:    { AsyncStream { _ in } }
    )
    static let testValue = BLEClient(
        startScanning:  { _ in },
        stopScanning:   { },
        peripherals:    { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var bleClient: BLEClient {
        get { self[BLEClient.self] }
        set { self[BLEClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/BLE/VariaRadarClient.swift" << 'SWIFT'
import ComposableArchitecture

/// TCA dependency for Garmin Varia RTL515 / RCT715 radar data over raw BLE.
/// Protocol: Garmin Radar Data BLE Program.
/// Reference: pycycling RDR module (open-source Python implementation).
/// Note: RearVue 820 excluded — secured BLE protocol.
struct VariaRadarClient {
    var radarTargets:       @Sendable () -> AsyncStream<[RadarTarget]>
    var connect:            @Sendable (String) async throws -> Void   // peripheral UUID string
    var disconnect:         @Sendable () async -> Void
    var pairingStatus:      @Sendable () -> AsyncStream<Bool>
}

extension VariaRadarClient: DependencyKey {
    static let liveValue = VariaRadarClient(
        radarTargets:   { AsyncStream { _ in } },
        connect:        { _ in },
        disconnect:     { },
        pairingStatus:  { AsyncStream { _ in } }
    )
    static let testValue = VariaRadarClient(
        radarTargets:   { AsyncStream { $0.finish() } },
        connect:        { _ in },
        disconnect:     { },
        pairingStatus:  { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var variaRadarClient: VariaRadarClient {
        get { self[VariaRadarClient.self] }
        set { self[VariaRadarClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/Location/LocationClient.swift" << 'SWIFT'
import ComposableArchitecture
import CoreLocation

/// TCA dependency wrapping CoreLocation.
/// BLE sensor speed takes priority; GPS is the fallback per architecture spec.
struct LocationClient {
    var requestAuthorization: @Sendable () async -> Void
    var locationStream:       @Sendable () -> AsyncStream<CLLocation>
    var speedStream:          @Sendable () -> AsyncStream<Double>   // m/s, GPS-derived
}

extension LocationClient: DependencyKey {
    static let liveValue = LocationClient(
        requestAuthorization: { },
        locationStream:       { AsyncStream { _ in } },
        speedStream:          { AsyncStream { _ in } }
    )
    static let testValue = LocationClient(
        requestAuthorization: { },
        locationStream:       { AsyncStream { $0.finish() } },
        speedStream:          { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/HealthKit/HealthKitClient.swift" << 'SWIFT'
import ComposableArchitecture
import HealthKit

/// TCA dependency for HealthKit.
/// maxHeartRate and restingHeartRate drive Karvonen HR zone computation.
/// Manual entry in Settings is the fallback when HealthKit is unavailable.
struct HealthKitClient {
    var requestAuthorization:  @Sendable () async throws -> Void
    var fetchMaxHeartRate:     @Sendable () async throws -> Int
    var fetchRestingHeartRate: @Sendable () async throws -> Int
    var heartRateStream:       @Sendable () -> AsyncStream<Int>     // live BPM from Watch / HR strap
}

extension HealthKitClient: DependencyKey {
    static let liveValue = HealthKitClient(
        requestAuthorization:  { },
        fetchMaxHeartRate:     { 190 },
        fetchRestingHeartRate: { 55 },
        heartRateStream:       { AsyncStream { _ in } }
    )
    static let testValue = HealthKitClient(
        requestAuthorization:  { },
        fetchMaxHeartRate:     { 190 },
        fetchRestingHeartRate: { 55 },
        heartRateStream:       { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/Haptics/HapticsClient.swift" << 'SWIFT'
import ComposableArchitecture
import CoreHaptics

/// TCA dependency for eyes-free haptic safety alerts.
/// L0 / L2 / L3 map to Audio.md alert levels.
struct HapticsClient {
    var playAllClear: @Sendable () async -> Void   // L0 — threat resolved
    var playWarning:  @Sendable () async -> Void   // L2 — vehicle approaching
    var playDanger:   @Sendable () async -> Void   // L3 — immediate threat
    var isAvailable:  @Sendable () -> Bool
}

extension HapticsClient: DependencyKey {
    static let liveValue = HapticsClient(
        playAllClear: { /* CoreHaptics impl */ },
        playWarning:  { /* CoreHaptics impl */ },
        playDanger:   { /* CoreHaptics impl */ },
        isAvailable:  { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    )
    static let testValue = HapticsClient(
        playAllClear: { },
        playWarning:  { },
        playDanger:   { },
        isAvailable:  { true }
    )
}

extension DependencyValues {
    var hapticsClient: HapticsClient {
        get { self[HapticsClient.self] }
        set { self[HapticsClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/Audio/AudioClient.swift" << 'SWIFT'
import ComposableArchitecture
import AVFoundation

/// TCA dependency for three-tone audio safety alerts (per Audio.md spec).
///
///   L0 All Clear : 880 Hz sine,             200 ms — jersey-pocket audible
///   L2 Warning   : 1046 Hz triangle,        300 ms — double-pulsed
///   L3 Danger    : 1318 Hz + 1046 Hz chord, 600 ms — overrides Silent Mode (user opt-in)
struct AudioClient {
    var playAllClear:           @Sendable () async -> Void
    var playWarning:            @Sendable () async -> Void
    var playDanger:             @Sendable () async -> Void
    var setOverridesSilentMode: @Sendable (Bool) async -> Void
}

extension AudioClient: DependencyKey {
    static let liveValue = AudioClient(
        playAllClear:           { /* AVFoundation impl */ },
        playWarning:            { /* AVFoundation impl */ },
        playDanger:             { /* AVFoundation impl */ },
        setOverridesSilentMode: { enabled in
            // Use AVAudioSession.sharedInstance().setCategory(.playback, ...) when enabled
        }
    )
    static let testValue = AudioClient(
        playAllClear:           { },
        playWarning:            { },
        playDanger:             { },
        setOverridesSilentMode: { _ in }
    )
}

extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}
SWIFT

cat > "$APP/Clients/Persistence/SwiftDataStack.swift" << 'SWIFT'
import SwiftData
import Foundation

/// SwiftData stack — ride summaries, user profile, settings metadata.
/// High-frequency time-series data lives in CoreDataStack (NSBatchInsertRequest).
@MainActor
final class SwiftDataStack {
    static let shared = SwiftDataStack()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            // TODO: RideSummary.self, UserProfile.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }
}
SWIFT

cat > "$APP/Clients/Persistence/CoreDataStack.swift" << 'SWIFT'
import CoreData
import Foundation

/// CoreData stack — high-frequency time-series ride data.
/// Writes via NSBatchInsertRequest for performance at 1 Hz+ sampling.
/// Separate from SwiftData to avoid mixing concerns.
final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "CyclometerTimeSeries")
        container.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
SWIFT

ok "Clients written."

# ── 5. Domain Models ──────────────────────────────────────────────────────────

log "Writing Models/..."

cat > "$APP/Models/RadarTarget.swift" << 'SWIFT'
import Foundation

/// A vehicle detected by the Garmin Varia radar.
/// RTL515 / RCT715 report up to 8 targets within ~140 m.
struct RadarTarget: Equatable, Identifiable, Sendable {
    let id: UUID
    /// Relative closing velocity in m/s (positive = approaching).
    var relativeVelocityMPS: Double
    /// Range to target in metres (0–140 m).
    var rangeMetres: Double
    /// Derived threat classification.
    var threatLevel: ThreatLevel

    enum ThreatLevel: Equatable, Sendable {
        case allClear   // L0 — no active threats
        case warning    // L2 — vehicle approaching, time to act
        case danger     // L3 — immediate threat, full alert
    }
}
SWIFT

cat > "$APP/Models/HeartRateZone.swift" << 'SWIFT'
import Foundation

/// Karvonen heart-rate reserve zone model.
/// Zone is computed at query time — never stored as persisted state.
enum HeartRateZone: Int, CaseIterable, Equatable {
    case zone1 = 1  // Recovery       < 60% HRR
    case zone2 = 2  // Endurance      60–70% HRR
    case zone3 = 3  // Tempo          70–80% HRR
    case zone4 = 4  // Threshold      80–90% HRR
    case zone5 = 5  // VO₂ Max        ≥ 90% HRR

    /// Karvonen formula: intensity = (bpm − restingHR) / (maxHR − restingHR)
    static func zone(bpm: Int, maxHR: Int, restingHR: Int) -> HeartRateZone {
        let hrr = Double(maxHR - restingHR)
        guard hrr > 0 else { return .zone1 }
        let intensity = Double(bpm - restingHR) / hrr
        switch intensity {
        case ..<0.60: return .zone1
        case ..<0.70: return .zone2
        case ..<0.80: return .zone3
        case ..<0.90: return .zone4
        default:      return .zone5
        }
    }
}
SWIFT

cat > "$APP/Models/Ride.swift" << 'SWIFT'
import Foundation

/// Top-level ride summary stored in SwiftData.
/// High-frequency samples (speed, HR, GPS) stored separately in CoreData.
struct Ride: Identifiable {
    let id: UUID
    var startDate: Date
    var endDate: Date?
    var distanceMetres: Double
    var averageSpeedKPH: Double
    var maxSpeedKPH: Double
    var averageHeartRate: Int
    var maxHeartRate: Int
    var elevationGainMetres: Double
    var radarVehiclePassCount: Int     // GPX cyc: namespace extension (PRD spec)
    var gpxFileURL: URL?
}
SWIFT

ok "Models written."

# ── 6. Design System ──────────────────────────────────────────────────────────

log "Writing UI/DesignSystem/..."

cat > "$APP/UI/DesignSystem/Color+Cyclometer.swift" << 'SWIFT'
import SwiftUI

// MARK: - Cyclometer Design Tokens
// Primary brand : #60BD10 (Cyclometer green)
// Token prefix  : cy  (Cyclometer)
// Theme         : Dark-primary, outdoor sunlight optimised
// Contrast      : WCAG AA+ on all foreground/background pairs

extension Color {

    // MARK: Primary Brand
    /// Brand green — CTAs, active states, highlights
    static let cyPrimary      = Color("cyPrimary")
    /// Pressed / hover state
    static let cyPrimaryDark  = Color("cyPrimaryDark")
    /// Tinted backgrounds, chips
    static let cyPrimaryLight = Color("cyPrimaryLight")
    /// Secondary accents, inactive icons
    static let cyPrimaryMuted = Color("cyPrimaryMuted")

    // MARK: Backgrounds
    static let cyBgPrimary   = Color("cyBgPrimary")     // Main app background
    static let cyBgSecondary = Color("cyBgSecondary")   // Cards, grouped sections
    static let cyBgTertiary  = Color("cyBgTertiary")    // Inset fields, wells
    static let cyBgElevated  = Color("cyBgElevated")    // Modals, sheets, popovers

    // MARK: Text
    static let cyTextPrimary   = Color("cyTextPrimary")   // Headlines, critical values
    static let cyTextSecondary = Color("cyTextSecondary") // Descriptions, timestamps
    static let cyTextTertiary  = Color("cyTextTertiary")  // Placeholders, captions
    static let cyTextOnPrimary = Color("cyTextOnPrimary") // Text on primary buttons
    static let cyTextInverted  = Color("cyTextInverted")  // Text on inverted surfaces

    // MARK: Borders & Separators
    static let cyBorder       = Color("cyBorder")
    static let cyBorderSubtle = Color("cyBorderSubtle")
    static let cyBorderStrong = Color("cyBorderStrong")

    // MARK: Ratings
    static let cyRatingBad    = Color("cyRatingBad")
    static let cyRatingBadBg  = Color("cyRatingBadBg")
    static let cyRatingOkay   = Color("cyRatingOkay")
    static let cyRatingOkayBg = Color("cyRatingOkayBg")
    static let cyRatingGood   = Color("cyRatingGood")
    static let cyRatingGoodBg = Color("cyRatingGoodBg")

    // MARK: Heart Rate Zones
    static let cyHRZone1 = Color("cyHRZone1")  // Recovery   — light blue
    static let cyHRZone2 = Color("cyHRZone2")  // Endurance  — blue
    static let cyHRZone3 = Color("cyHRZone3")  // Tempo      — green (= cyPrimary)
    static let cyHRZone4 = Color("cyHRZone4")  // Threshold  — orange
    static let cyHRZone5 = Color("cyHRZone5")  // VO₂ Max    — red

    // MARK: System
    static let cyDestructive = Color("cyDestructive")
    static let cyInfo        = Color("cyInfo")
}

// MARK: - Semantic Helpers

extension Color {
    /// HR zone colour for zone 1–5. Returns cyTextTertiary for out-of-range values.
    static func hrZone(_ zone: Int) -> Color {
        switch zone {
        case 1: return .cyHRZone1
        case 2: return .cyHRZone2
        case 3: return .cyHRZone3
        case 4: return .cyHRZone4
        case 5: return .cyHRZone5
        default: return .cyTextTertiary
        }
    }

    /// Foreground rating colour for a normalised score (0.0–1.0).
    static func rating(score: Double) -> Color {
        score < 0.33 ? .cyRatingBad : score < 0.66 ? .cyRatingOkay : .cyRatingGood
    }

    /// Background tint for a normalised score (0.0–1.0).
    static func ratingBackground(score: Double) -> Color {
        score < 0.33 ? .cyRatingBadBg : score < 0.66 ? .cyRatingOkayBg : .cyRatingGoodBg
    }
}
SWIFT

cat > "$APP/UI/DesignSystem/Typography.swift" << 'SWIFT'
import SwiftUI

// MARK: - Cyclometer Typography
// Primary typeface: D-DIN (installed in Resources/Fonts, declared in Info.plist)
// Fallback:         SF Pro Display

extension Font {
    static func ddin(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("D-DIN", size: size).weight(weight)
    }

    // ── Metric display ──────────────────────────────────────────────────────
    /// 82 pt — hero speed readout
    static let cyHeroSpeed    = Font.ddin(size: 82, weight: .black)
    /// 32 pt — large secondary metric
    static let cyMetricLarge  = Font.ddin(size: 32, weight: .bold)
    /// 24 pt — standard metric tile value
    static let cyMetricMedium = Font.ddin(size: 24, weight: .bold)
    /// 18 pt — small metric or section heading
    static let cyMetricSmall  = Font.ddin(size: 18, weight: .semibold)

    // ── Labels ──────────────────────────────────────────────────────────────
    /// 12 pt — metric labels, unit strings, uppercase tags
    static let cyLabel   = Font.ddin(size: 12)
    /// 10 pt — captions, secondary metadata
    static let cyCaption = Font.ddin(size: 10)
}
SWIFT

ok "Design system written."

# ── 7. UI Components ──────────────────────────────────────────────────────────

log "Writing UI/Components/..."

cat > "$APP/UI/Components/RadarColumn/RadarColumnView.swift" << 'SWIFT'
import SwiftUI

/// 24pt fixed-width radar column — right edge of the Ride Metrics dashboard (S06).
///
/// Layout (per S06 layer data):
///   • Background: full-height, colour-coded by dominant threat level
///   • Vehicle glyphs: 16pt wide, positioned top → bottom by proximity
///     - Top    = critical / closest threat   (L3)
///     - Middle = warning / approaching       (L2)
///     - Bottom = car / distant               (L0)
///
/// Visibility:
///   • Rendered only when a Varia device is paired (caller gates via `if store.isRadarPaired`)
///   • Zero-width when unpaired — the HStack in RideMetricsView collapses it with no reflow
///
/// Target hardware: Garmin Varia RTL515 / RCT715 (up to 8 targets, range 0–140 m)
struct RadarColumnView: View {
    let targets: [RadarTarget]

    // Dominant threat drives background colour
    private var dominantThreat: RadarTarget.ThreatLevel {
        if targets.contains(where: { $0.threatLevel == .danger })  { return .danger }
        if targets.contains(where: { $0.threatLevel == .warning }) { return .warning }
        return .allClear
    }

    private var columnBackground: Color {
        switch dominantThreat {
        case .allClear: return Color.cyBgSecondary
        case .warning:  return Color.cyRatingOkayBg
        case .danger:   return Color.cyRatingBadBg
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Background fill
                columnBackground
                    .animation(.easeInOut(duration: 0.2), value: dominantThreat)

                // Vehicle glyphs — sorted by range ascending so closest is at top.
                // Each glyph is 16×16pt, centred in the 24pt column.
                // Y position maps range (0–140 m) linearly to column height.
                let sorted = targets.sorted { $0.rangeMetres < $1.rangeMetres }
                ForEach(sorted) { target in
                    VehicleGlyphView(threatLevel: target.threatLevel)
                        .frame(width: 16, height: 16)
                        .position(
                            x: 12,   // centre of 24pt column
                            y: yPosition(for: target.rangeMetres, in: geo.size.height)
                        )
                }
            }
        }
    }

    /// Maps vehicle range (0–140 m) to a Y position within the column.
    /// Closest vehicle (0 m) → top; furthest (140 m) → bottom.
    private func yPosition(for rangeMetres: Double, in height: CGFloat) -> CGFloat {
        let maxRange: Double = 140
        let fraction = min(rangeMetres / maxRange, 1.0)
        // Reserve 12pt padding top and bottom so glyphs don't clip at edges
        let usable = Double(height) - 24
        return CGFloat(12 + fraction * usable)
    }
}

// MARK: - Vehicle Glyph

/// Single vehicle indicator — shape and colour encode threat level.
private struct VehicleGlyphView: View {
    let threatLevel: RadarTarget.ThreatLevel

    private var glyphColor: Color {
        switch threatLevel {
        case .allClear: return .cyRatingGood
        case .warning:  return .cyRatingOkay
        case .danger:   return .cyRatingBad
        }
    }

    var body: some View {
        Image(systemName: "car.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(glyphColor)
            .animation(.easeInOut(duration: 0.15), value: threatLevel)
    }
}
SWIFT

cat > "$APP/UI/Components/MetricTile/MetricTileView.swift" << 'SWIFT'
import SwiftUI

/// Reusable secondary metric tile — used in the two-column grid on the Ride Metrics page.
/// HR tile uses the zone colour as its border treatment.
struct MetricTileView: View {
    let label: String
    let value: String
    let unit: String
    var borderColor: Color = Color.cyBorderSubtle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.cyCaption)
                .foregroundStyle(Color.cyTextSecondary)
                .textCase(.uppercase)
                .tracking(1.5)

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.cyMetricMedium)
                    .foregroundStyle(Color.cyTextPrimary)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.cyCaption)
                        .foregroundStyle(Color.cyTextSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
    }
}
SWIFT

cat > "$APP/UI/Components/HRZoneBadge/HRZoneBadgeView.swift" << 'SWIFT'
import SwiftUI

/// Compact heart-rate zone badge — "Z4" with zone colour.
struct HRZoneBadgeView: View {
    let zone: Int   // 1–5

    var body: some View {
        Text("Z\(zone)")
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .foregroundStyle(Color.hrZone(zone))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.hrZone(zone).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
SWIFT

ok "UI components written."

# ── 8. xcassets JSON stubs ────────────────────────────────────────────────────

log "Writing xcassets stubs..."

cat > "$APP/Resources/Assets.xcassets/Contents.json" << 'JSON'
{ "info": { "author": "xcode", "version": 1 } }
JSON

cat > "$APP/Resources/Assets.xcassets/AccentColor.colorset/Contents.json" << 'JSON'
{
  "colors": [
    {
      "color": {
        "color-space": "srgb",
        "components": { "red": "0.376", "green": "0.741", "blue": "0.063", "alpha": "1.000" }
      },
      "idiom": "universal"
    }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON

cat > "$APP/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" << 'JSON'
{
  "images": [
    { "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
JSON

ok "xcassets stubs written."

# ── 9. Test targets ───────────────────────────────────────────────────────────

log "Writing CyclometerTests/..."

cat > "$TESTS/Features/RideMetricsTests.swift" << 'SWIFT'
import Testing
import ComposableArchitecture
@testable import Cyclometer

@Suite("RideMetricsFeature")
struct RideMetricsTests {

    @Test("Initial speed is zero")
    func initialSpeedIsZero() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        #expect(store.state.speedKPH == 0.0)
    }

    @Test("Speed update reflects in state")
    func speedUpdate() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.speedUpdated(28.4)) {
            $0.speedKPH = 28.4
        }
    }

    @Test("Start ride sets isRiding")
    func startRide() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.startRideTapped) {
            $0.isRiding = true
            $0.isPaused = false
        }
    }

    @Test("Pause ride sets isPaused")
    func pauseRide() async {
        let store = TestStore(initialState: RideMetricsFeature.State()) {
            RideMetricsFeature()
        }
        await store.send(.startRideTapped) { $0.isRiding = true }
        await store.send(.pauseRideTapped) { $0.isPaused = true }
    }

    @Test("HR update computes correct zone via Karvonen")
    func hrZoneUpdate() async {
        // maxHR=190, restingHR=55, HRR=135
        // 183 bpm → 95% HRR → Zone 5
        var state = RideMetricsFeature.State()
        state.maxHeartRate     = 190
        state.restingHeartRate = 55
        let store = TestStore(initialState: state) { RideMetricsFeature() }
        await store.send(.heartRateUpdated(183)) {
            $0.heartRateBPM = 183
            $0.hrZone       = 5
        }
    }

    @Test("Elapsed tick increments only when riding and not paused")
    func elapsedTick() async {
        var state = RideMetricsFeature.State()
        state.isRiding = true
        state.isPaused = false
        let store = TestStore(initialState: state) { RideMetricsFeature() }
        await store.send(.elapsedTick) { $0.elapsedSeconds = 1 }
    }
}
SWIFT

cat > "$TESTS/Models/HeartRateZoneTests.swift" << 'SWIFT'
import Testing
@testable import Cyclometer

@Suite("HeartRateZone — Karvonen formula")
struct HeartRateZoneTests {
    // Fixture: maxHR=190, restingHR=55, HRR=135

    @Test("48% HRR → Zone 1 (Recovery)")
    func zone1() {
        // 48% of 135 = 64.8 + 55 = 119.8 bpm
        let z = HeartRateZone.zone(bpm: 119, maxHR: 190, restingHR: 55)
        #expect(z == .zone1)
    }

    @Test("65% HRR → Zone 2 (Endurance)")
    func zone2() {
        // 65% of 135 = 87.75 + 55 = 142.75 bpm
        let z = HeartRateZone.zone(bpm: 142, maxHR: 190, restingHR: 55)
        #expect(z == .zone2)
    }

    @Test("75% HRR → Zone 3 (Tempo)")
    func zone3() {
        // 75% of 135 = 101.25 + 55 = 156.25 bpm
        let z = HeartRateZone.zone(bpm: 156, maxHR: 190, restingHR: 55)
        #expect(z == .zone3)
    }

    @Test("85% HRR → Zone 4 (Threshold)")
    func zone4() {
        // 85% of 135 = 114.75 + 55 = 169.75 bpm
        let z = HeartRateZone.zone(bpm: 169, maxHR: 190, restingHR: 55)
        #expect(z == .zone4)
    }

    @Test("95% HRR → Zone 5 (VO₂ Max)")
    func zone5() {
        // 95% of 135 = 128.25 + 55 = 183.25 bpm
        let z = HeartRateZone.zone(bpm: 183, maxHR: 190, restingHR: 55)
        #expect(z == .zone5)
    }

    @Test("Zero HRR guard returns Zone 1")
    func zeroHRR() {
        let z = HeartRateZone.zone(bpm: 150, maxHR: 170, restingHR: 170)
        #expect(z == .zone1)
    }
}
SWIFT

cat > "$TESTS/Models/RadarTargetTests.swift" << 'SWIFT'
import Testing
@testable import Cyclometer

@Suite("RadarTarget")
struct RadarTargetTests {

    @Test("Each target has a unique identity")
    func uniqueIDs() {
        let t1 = RadarTarget(id: UUID(), relativeVelocityMPS: 15, rangeMetres: 80, threatLevel: .warning)
        let t2 = RadarTarget(id: UUID(), relativeVelocityMPS: 15, rangeMetres: 80, threatLevel: .warning)
        #expect(t1.id != t2.id)
    }

    @Test("Threat levels are equatable")
    func threatEquality() {
        let t = RadarTarget(id: UUID(), relativeVelocityMPS: 20, rangeMetres: 30, threatLevel: .danger)
        #expect(t.threatLevel == .danger)
        #expect(t.threatLevel != .warning)
    }

    @Test("RadarTarget conforms to Equatable")
    func equatable() {
        let id = UUID()
        let t1 = RadarTarget(id: id, relativeVelocityMPS: 10, rangeMetres: 50, threatLevel: .allClear)
        let t2 = RadarTarget(id: id, relativeVelocityMPS: 10, rangeMetres: 50, threatLevel: .allClear)
        #expect(t1 == t2)
    }
}
SWIFT

cat > "$TESTS/Clients/VariaRadarClientTests.swift" << 'SWIFT'
import Testing
import ComposableArchitecture
@testable import Cyclometer

@Suite("VariaRadarClient — test value")
struct VariaRadarClientTests {

    @Test("Test value connect does not throw")
    func connectNoThrow() async throws {
        let client = VariaRadarClient.testValue
        try await client.connect("test-uuid")
    }

    @Test("Test value radar stream completes immediately")
    func streamCompletes() async {
        let client = VariaRadarClient.testValue
        var count = 0
        for await _ in client.radarTargets() {
            count += 1
        }
        #expect(count == 0)  // testValue stream finishes immediately
    }
}
SWIFT

cat > "$UI_TESTS/CyclometerUITests.swift" << 'SWIFT'
import XCTest

final class CyclometerUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testRideMetricsDashboardLoads() throws {
        // Hero speed label should show 0.0 on cold launch
        XCTAssertTrue(app.staticTexts["0.0"].waitForExistence(timeout: 5))
    }

    func testStartRideButtonExists() throws {
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
    }
}
SWIFT

ok "Tests written."

# ── 10. SPM packages reference ────────────────────────────────────────────────

log "Writing spm-packages.md..."

cat > "$ROOT/spm-packages.md" << 'MD'
# Cyclometer — SPM Package Dependencies

Add via **Xcode → File → Add Package Dependencies…**

---

## Required at project creation

| Package | Repository URL | Version rule |
|---------|---------------|-------------|
| The Composable Architecture | `https://github.com/pointfreeco/swift-composable-architecture` | Up to Next Major: **1.0.0** |

---

## Add when feature work begins

| Package | Repository URL | When |
|---------|---------------|------|
| swift-snapshot-testing | `https://github.com/pointfreeco/swift-snapshot-testing` | Before first UI component test |
| swift-custom-dump | `https://github.com/pointfreeco/swift-custom-dump` | With TCA test work (better diffs) |

---

## System frameworks — no SPM entry needed

| Framework | Used for |
|-----------|---------|
| CoreBluetooth | Varia RTL515 / RCT715 BLE radar data |
| CoreLocation | GPS speed + route tracking |
| HealthKit | maxHR / restingHR for Karvonen zones; live HR stream |
| CoreHaptics | Eyes-free haptic alerts (L0 / L2 / L3) |
| AVFoundation | Three-tone audio alert synthesis (Audio.md spec) |
| SwiftData | Ride summaries, user profile, settings |
| CoreData | High-frequency time-series ride data (NSBatchInsertRequest) |
| MapKit | Page 2 map rendering with GPX polyline overlay |

---

## Possible future additions (Phase 2+)

| Package | Notes |
|---------|-------|
| ActiveLook SDK | AR glasses integration (ENGO 2); not yet on SPM — check vendor |
| Garmin Radar Data BLE SDK | Evaluate vs raw CoreBluetooth; apply to program first |
MD

ok "spm-packages.md written."

# ── 11. Done ──────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}  Scaffold complete.${RESET}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Next steps"
echo "  ──────────"
echo "  1. Open Xcode → New Project → App"
echo "     Product name : Cyclometer"
echo "     Bundle ID    : name.glaeske.cyclometer"
echo "     Interface    : SwiftUI"
echo "     Language     : Swift"
echo "     Depl. target : iOS 26"
echo "     Save to      : $ROOT"
echo "     (let Xcode overwrite its generated folder, then add"
echo "      the scaffold files to the Xcode project groups)"
echo ""
echo "  2. File → Add Package Dependencies"
echo "     → https://github.com/pointfreeco/swift-composable-architecture"
echo "     → Up to Next Major: 1.0.0"
echo ""
echo "  3. Add CyclometerTests target (Testing + XCTest)"
echo "     Add CyclometerUITests target (XCUITest)"
echo ""
echo "  4. Copy D-DIN font files → Cyclometer/Resources/Fonts/"
echo "     Add UIAppFonts key to Info.plist with each filename."
echo ""
echo "  5. Add NSBluetoothAlwaysUsageDescription to Info.plist"
echo "     Add NSLocationWhenInUseUsageDescription"
echo "     Add NSHealthShareUsageDescription"
echo ""
echo "  6. Add Color Set entries in Assets.xcassets for all cy* tokens"
echo "     (values in BikeRider-ColorSystem.md → rename prefix br → cy)"
echo ""
echo "  See spm-packages.md for full dependency reference."
echo ""
