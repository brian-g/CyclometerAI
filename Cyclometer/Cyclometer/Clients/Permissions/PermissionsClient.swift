import ComposableArchitecture
@preconcurrency import CoreBluetooth
import CoreLocation
import CoreMotion
import HealthKit
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "permissions")

// MARK: - PermissionsClient

/// The app's single authorization surface, covering the four domains S01 presents
/// (UX.md §S01).
///
/// Features never touch `CBCentralManager.authorization`, `CLAuthorizationStatus`,
/// `CMAuthorizationStatus` or `HKHealthStore` directly — they ask here and get one
/// vocabulary back, so S01 renders four rows from a single switch. The sensor clients
/// keep owning their frameworks for *data*; only permission is centralised.
struct PermissionsClient: Sendable {
    /// Current authorization, read without presenting anything.
    var status:   @Sendable (PermissionDomain) async -> PermissionState
    /// Present the system prompt if — and only if — the domain is `.notDetermined`,
    /// then return the resolved state.
    var request:  @Sendable (PermissionDomain) async -> PermissionState
    /// Every authorization transition, including changes the rider makes in iOS
    /// Settings while the app is backgrounded — which is the only way back from a
    /// denial, so S01's recovery path depends on it.
    ///
    /// Each call returns a new stream; every active stream sees the same changes, and
    /// each replays the current state of all four domains on subscribe. This is a
    /// *state* feed rather than an event feed: a repeated value is meaningless but
    /// harmless, and only changes are broadcast.
    var statuses: @Sendable () -> AsyncStream<PermissionChange>
}

// MARK: - Framework status mapping

extension PermissionsClient {

    /// Bluetooth. Deliberately takes `CBManagerAuthorization` and not `CBManagerState`:
    /// a `.poweredOff` radio is a rider who switched Bluetooth off, not one who refused
    /// the app, and rendering that as a denial would send them to a Settings switch
    /// that is already on.
    static func state(cb: CBManagerAuthorization) -> PermissionState {
        switch cb {
        case .notDetermined: .notDetermined
        case .allowedAlways: .granted
        case .denied:        .denied
        case .restricted:    .restricted
        @unknown default:    .notDetermined
        }
    }

    /// Location. The only domain with two grant levels: onboarding asks for When In
    /// Use, and Always is escalated later at first ride start (UX.md §S01).
    static func state(cl: CLAuthorizationStatus) -> PermissionState {
        switch cl {
        case .notDetermined:       .notDetermined
        case .authorizedWhenInUse: .granted
        case .authorizedAlways:    .grantedAlways
        case .denied:              .denied
        case .restricted:          .restricted
        @unknown default:          .notDetermined
        }
    }

    /// Motion. `isAvailable` is checked first and wins: on the Simulator and on devices
    /// without a motion coprocessor `CMMotionActivityManager.isActivityAvailable()` is
    /// false and the status stays `.notDetermined` no matter how often it is asked, so
    /// without `.unavailable` S01's Next button would never enable.
    static func state(cm: CMAuthorizationStatus, isAvailable: Bool) -> PermissionState {
        guard isAvailable else { return .unavailable }
        return switch cm {
        case .notDetermined: .notDetermined
        case .authorized:    .granted
        case .denied:        .denied
        case .restricted:    .restricted
        @unknown default:    .notDetermined
        }
    }

    /// HealthKit, from `getRequestStatusForAuthorization` rather than
    /// `authorizationStatus(for:)`.
    ///
    /// This is the honesty requirement in #95. HealthKit will not tell an app that a
    /// *read* was denied — `authorizationStatus(for:)` reports `.notDetermined` both
    /// before the sheet and after a refusal, by design, so that an app cannot infer
    /// health facts from the shape of the refusal. An empty query result means the same
    /// thing and must not be read as denial either.
    ///
    /// So this domain can never return `.denied`. `.unnecessary` means "you have asked
    /// for everything you declared" — the most that is knowable, and what S01 shows as
    /// a checkmark rather than a red X (#106).
    static func state(health: HKAuthorizationRequestStatus, isAvailable: Bool) -> PermissionState {
        guard isAvailable else { return .unavailable }
        return switch health {
        case .shouldRequest: .notDetermined
        case .unnecessary:   .granted
        case .unknown:       .notDetermined
        @unknown default:    .notDetermined
        }
    }

    // MARK: HealthKit types

    /// Named once so `HealthKitClient`'s queries reference the exact identifiers this
    /// authorization set declares, rather than reconstructing them ad hoc and risking
    /// silent drift between what's requested and what's queried.
    static let heartRateType = HKQuantityType(.heartRate)
    static let restingHeartRateType = HKQuantityType(.restingHeartRate)
    static let dateOfBirthType = HKCharacteristicType(.dateOfBirth)

    /// PRD.md §9.4 — resting HR and max HR feed the Karvonen zones, date of birth backs
    /// the age-based max-HR estimate when no measured maximum exists.
    static var healthReadTypes: Set<HKObjectType> {
        [heartRateType, restingHeartRateType, dateOfBirthType]
    }

    /// UX.md §S10 — an `HKWorkout` is written at ride end so the ride lands in the
    /// Fitness app and counts toward Activity rings. Requested here, with the reads, so
    /// the rider answers one sheet in their lifetime rather than a second one months
    /// later at the end of their first ride.
    static var healthShareTypes: Set<HKSampleType> {
        [HKWorkoutType.workoutType()]
    }
}

// MARK: - DependencyKey

extension PermissionsClient: DependencyKey {

    /// Factory with injectable transport, matching `BLEHRClient.live(bleClient:)`.
    /// Bluetooth authorization is delegated rather than reimplemented because
    /// `BLEClient` owns the app's only `CBCentralManager`, and it is that manager's
    /// existence which raises the prompt.
    ///
    /// `probes` carries the other three domains' framework reads (#117). It defaults to
    /// the real ones, so this stays a one-argument factory everywhere in the app; tests
    /// of the subscriber table and the transition filter pass `.fixed(...)` instead and
    /// touch no framework at all.
    static func live(
        bleClient: BLEClient,
        probes: PermissionProbes = .live
    ) -> PermissionsClient {
        let state = PermissionsLiveState(bleClient: bleClient, probes: probes)
        return PermissionsClient(
            status:   { await state.status(for: $0) },
            request:  { await state.request($0) },
            statuses: { state.makeStatusStream() }
        )
    }

    static let liveValue = PermissionsClient.live(bleClient: .liveValue)

    static let testValue = PermissionsClient(
        status:   { _ in .granted },
        request:  { _ in .granted },
        statuses: { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var permissionsClient: PermissionsClient {
        get { self[PermissionsClient.self] }
        set { self[PermissionsClient.self] = newValue }
    }
}

// MARK: - Live implementation

/// The subscriber table, the transition filter and the observation lifecycle. Framework
/// contact lives in `PermissionProbes` (#117) — apart from Bluetooth, which is delegated
/// to `BLEClient` because that type owns the app's only `CBCentralManager`.
///
/// `@unchecked Sendable`: thread safety is enforced manually — `lock` guards the
/// subscriber table, and every framework call is confined to a probe.
private final class PermissionsLiveState: NSObject, @unchecked Sendable {

    private let bleClient: BLEClient
    private let probes: PermissionProbes

    private var subscribers: [Int: AsyncStream<PermissionChange>.Continuation] = [:]
    private var nextSubscriberID = 0
    /// Last value broadcast per domain, so observers emit transitions rather than a
    /// repeat every time a framework callback fires. Guarded by `lock`.
    private var lastKnown: [PermissionDomain: PermissionState] = [:]
    /// Runs only while someone is subscribed. Guarded by `lock`.
    private var observationTask: Task<Void, Never>?
    private let lock = NSLock()

    init(bleClient: BLEClient, probes: PermissionProbes) {
        self.bleClient = bleClient
        self.probes = probes
        super.init()
    }

    // MARK: Status

    func status(for domain: PermissionDomain) async -> PermissionState {
        switch domain {
        case .bluetooth:        return PermissionsClient.state(cb: bleClient.authorization())
        case .locationWhenInUse: return await probes.locationStatus()
        case .motion:           return await probes.motionStatus()
        case .health:           return await probes.healthStatus()
        }
    }

    // MARK: Request

    func request(_ domain: PermissionDomain) async -> PermissionState {
        let current = await status(for: domain)

        // Only .notDetermined can be answered by a prompt. Asking again after a denial
        // presents nothing — iOS silently no-ops — so short-circuit and let the caller
        // route the rider to Settings instead of waiting on a sheet that never appears.
        guard current == .notDetermined else {
            logger.notice("\(domain.rawValue, privacy: .public) already resolved — no prompt")
            return current
        }

        logger.notice("requesting \(domain.rawValue, privacy: .public)")
        let resolved: PermissionState

        switch domain {
        case .bluetooth:        resolved = PermissionsClient.state(cb: await bleClient.requestAuthorization())
        case .locationWhenInUse: resolved = await probes.requestLocation()
        case .motion:           resolved = await probes.requestMotion()
        case .health:           resolved = await probes.requestHealth()
        }

        broadcastIfChanged(domain, resolved)
        return resolved
    }

    // MARK: Change stream

    func makeStatusStream() -> AsyncStream<PermissionChange> {
        let (stream, continuation) = AsyncStream<PermissionChange>.makeStream()
        let (id, isFirstSubscriber) = lock.withLock { () -> (Int, Bool) in
            let current = nextSubscriberID
            nextSubscriberID += 1
            let wasEmpty = subscribers.isEmpty
            subscribers[current] = continuation
            return (current, wasEmpty)
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            let isLastSubscriber = self.lock.withLock { () -> Bool in
                self.subscribers.removeValue(forKey: id)
                return self.subscribers.isEmpty
            }
            if isLastSubscriber { self.stopObserving() }
        }

        // Framework observation costs a CLLocationManager delegate, a BLE event
        // subscription and a notification observer, so it runs only while someone is
        // listening rather than for the process lifetime.
        if isFirstSubscriber { startObserving() }

        // Replay every domain's current state. Without this, a row whose status
        // resolved before the view subscribed would render as an unanswered oval until
        // some later change arrived — and for a granted domain no later change ever
        // does.
        Task { [weak self] in
            guard let self else { return }
            for domain in PermissionDomain.allCases {
                let state = await status(for: domain)
                lock.withLock { lastKnown[domain] = state }
                continuation.yield(PermissionChange(domain: domain, state: state))
            }
        }

        return stream
    }

    /// Broadcast only on an actual transition.
    ///
    /// Every source here re-reads the whole domain rather than being handed a delta —
    /// `centralManagerDidUpdateState` fires for radio power, the foreground re-poll
    /// fires on every app activation — so without this filter subscribers would see a
    /// storm of repeats and S01 would rebuild its rows for nothing.
    private func broadcastIfChanged(_ domain: PermissionDomain, _ state: PermissionState) {
        let observers = lock.withLock { () -> [AsyncStream<PermissionChange>.Continuation]? in
            guard lastKnown[domain] != state else { return nil }
            lastKnown[domain] = state
            return Array(subscribers.values)
        }
        guard let observers else { return }
        logger.notice(
            "\(domain.rawValue, privacy: .public) changed → \(String(describing: state), privacy: .public)"
        )
        let change = PermissionChange(domain: domain, state: state)
        for continuation in observers { continuation.yield(change) }
    }

    // MARK: Framework observation

    /// Three sources, because the four domains do not report alike.
    ///
    /// Location and Bluetooth have real framework callbacks and are observed directly.
    /// Motion and HealthKit have none at all — nothing tells an app that Motion & Fitness
    /// was switched off in Settings — so the only way to honour the stream's contract for
    /// them is to re-read on return to the foreground, which is exactly when a rider
    /// coming back from Settings arrives. The re-poll covers all four rather than just
    /// the two, since `broadcastIfChanged` makes a redundant read free.
    private func startObserving() {
        // `weak` so that dropping the client stops observation on its own. The strong
        // reference is re-established for the duration of each loop, which is bounded by
        // `stopObserving` cancelling the group.
        let task = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    guard let probes = self?.probes else { return }
                    for await state in probes.locationChanges() {
                        guard let self else { return }
                        self.broadcastIfChanged(.locationWhenInUse, state)
                    }
                }
                group.addTask { [weak self] in
                    guard let bleClient = self?.bleClient else { return }
                    for await event in bleClient.events() {
                        guard case .stateChanged = event else { continue }
                        guard let self else { return }
                        // The event carries CBManagerState, which is the radio, not the
                        // permission — re-read authorization rather than mapping it.
                        self.broadcastIfChanged(.bluetooth, PermissionsClient.state(cb: bleClient.authorization()))
                    }
                }
                group.addTask { [weak self] in
                    guard let probes = self?.probes else { return }
                    for await _ in probes.foregrounded() {
                        guard let self else { return }
                        for domain in PermissionDomain.allCases {
                            self.broadcastIfChanged(domain, await self.status(for: domain))
                        }
                    }
                }
            }
        }
        lock.withLock { observationTask = task }
    }

    private func stopObserving() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let t = observationTask
            observationTask = nil
            return t
        }
        task?.cancel()
    }
}
