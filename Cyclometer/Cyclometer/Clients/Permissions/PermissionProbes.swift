import ComposableArchitecture
import CoreLocation
import CoreMotion
import HealthKit
import UIKit
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "permissions")

// MARK: - PermissionProbes

/// Every framework read the live `PermissionsClient` makes, behind closures.
///
/// `PermissionsLiveState` has two jobs: talking to four frameworks, and keeping the
/// subscriber table, the transition filter and the observation lifecycle straight. Only
/// the second is interesting to test, and before #117 there was no way to reach it
/// without a `CLLocationManager`, a `CMMotionActivityManager` and an `HKHealthStore`
/// coming along — which made those tests hostage to simulator health and cost two CI
/// failures on stalled runners.
///
/// Bluetooth is deliberately absent: `BLEClient` is already injectable and owns the
/// app's only `CBCentralManager`, so it needs no second seam.
///
/// Everything here resolves to `PermissionState` rather than a framework type, so the
/// live state machine never sees `CLAuthorizationStatus` or `HKAuthorizationRequestStatus`
/// at all. The raw mappings stay on `PermissionsClient` as static functions and are
/// unit-tested directly.
struct PermissionProbes: Sendable {
    var locationStatus:  @Sendable () async -> PermissionState
    var requestLocation: @Sendable () async -> PermissionState
    /// Authorization transitions, including ones the rider makes in iOS Settings.
    var locationChanges: @Sendable () -> AsyncStream<PermissionState>

    var motionStatus:    @Sendable () async -> PermissionState
    var requestMotion:   @Sendable () async -> PermissionState

    var healthStatus:    @Sendable () async -> PermissionState
    var requestHealth:   @Sendable () async -> PermissionState

    /// Return to the foreground — the only signal Motion and HealthKit have, since
    /// neither tells an app that its permission changed while it was away.
    var foregrounded:    @Sendable () -> AsyncStream<Void>
}

// MARK: - Live

/// Holds the framework objects the live probes need for the process lifetime.
///
/// `@unchecked Sendable` for the reason `PermissionsLiveState` carries it: neither
/// `HKHealthStore` nor `CMMotionActivityManager` is `Sendable`, and access to both is
/// confined to the closures below.
private final class LiveFrameworkHandles: @unchecked Sendable {
    let healthStore = HKHealthStore()
    /// Retained deliberately: `queryActivityStarting` calls its handler asynchronously,
    /// and a manager released in the meantime never delivers.
    let motionManager = CMMotionActivityManager()
}

extension PermissionProbes {

    static let live: PermissionProbes = {
        let handles = LiveFrameworkHandles()
        return PermissionProbes(
            locationStatus: {
                PermissionsClient.state(cl: await LocationManagerState.shared.authorizationStatus())
            },
            requestLocation: {
                PermissionsClient.state(cl: await LocationManagerState.shared.requestAuthorization())
            },
            locationChanges: {
                AsyncStream { continuation in
                    let task = Task {
                        for await status in LocationManagerState.shared.makeAuthorizationStream() {
                            continuation.yield(PermissionsClient.state(cl: status))
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            motionStatus: {
                PermissionsClient.state(
                    cm: CMMotionActivityManager.authorizationStatus(),
                    isAvailable: CMMotionActivityManager.isActivityAvailable()
                )
            },
            requestMotion: { await Self.requestMotion(handles.motionManager) },
            healthStatus: { await Self.healthStatus(handles.healthStore) },
            requestHealth: { await Self.requestHealth(handles.healthStore) },
            foregrounded: {
                AsyncStream { continuation in
                    let task = Task {
                        let notifications = NotificationCenter.default.notifications(
                            named: await UIApplication.didBecomeActiveNotification
                        )
                        for await _ in notifications { continuation.yield(()) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            }
        )
    }()

    /// CoreMotion has no request API. The prompt is raised by the first query against
    /// activity data, so a throwaway one-second query over the past is the documented
    /// way to ask; the handler fires once the rider has answered, and the real answer is
    /// then read back from `authorizationStatus()`.
    ///
    /// Requires `NSMotionUsageDescription` in Info.plist — without it this call traps.
    private static func requestMotion(_ manager: CMMotionActivityManager) async -> PermissionState {
        guard CMMotionActivityManager.isActivityAvailable() else { return .unavailable }

        let end = Date()
        let start = end.addingTimeInterval(-1)
        let queue = OperationQueue()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let hasResumed = LockIsolated(false)
            manager.queryActivityStarting(from: start, to: end, to: queue) { _, error in
                // The handler is documented as one-shot, but a double resume is a crash
                // rather than a bug report — guard it rather than trust it.
                let shouldResume = hasResumed.withValue { resumed -> Bool in
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
                guard shouldResume else { return }
                if let error {
                    // A refusal surfaces here as CMErrorMotionActivityNotAuthorized.
                    // Not an error condition — authorizationStatus() has the answer.
                    logger.notice("motion query returned \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }

        return PermissionsClient.state(
            cm: CMMotionActivityManager.authorizationStatus(),
            isAvailable: CMMotionActivityManager.isActivityAvailable()
        )
    }

    private static func healthStatus(_ store: HKHealthStore) async -> PermissionState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            let requestStatus = try await store.statusForAuthorizationRequest(
                toShare: PermissionsClient.healthShareTypes,
                read: PermissionsClient.healthReadTypes
            )
            return PermissionsClient.state(health: requestStatus, isAvailable: true)
        } catch {
            // A failure here says nothing about the rider's answer, so it must not be
            // reported as one. notDetermined keeps the row tappable.
            logger.error("health request status failed: \(error.localizedDescription)")
            return .notDetermined
        }
    }

    private static func requestHealth(_ store: HKHealthStore) async -> PermissionState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        do {
            try await store.requestAuthorization(
                toShare: PermissionsClient.healthShareTypes,
                read: PermissionsClient.healthReadTypes
            )
        } catch {
            logger.error("health authorization failed: \(error.localizedDescription)")
        }
        // Re-read rather than assume: the sheet having been dismissed says nothing
        // about which switches the rider left on, and HealthKit will not say either.
        return await healthStatus(store)
    }
}

// MARK: - Test support

extension PermissionProbes {

    /// Probes that answer instantly from fixed values and never stream.
    ///
    /// For tests of the subscriber table and the transition filter, which are about
    /// bluetooth and bookkeeping and have no business constructing an `HKHealthStore`.
    /// The two streams finish immediately, so the observation task group winds those
    /// children down and leaves only the BLE observer the tests actually drive.
    static func fixed(
        location: PermissionState = .notDetermined,
        motion: PermissionState = .notDetermined,
        health: PermissionState = .notDetermined
    ) -> PermissionProbes {
        PermissionProbes(
            locationStatus:  { location },
            requestLocation: { location },
            locationChanges: { AsyncStream { $0.finish() } },
            motionStatus:    { motion },
            requestMotion:   { motion },
            healthStatus:    { health },
            requestHealth:   { health },
            foregrounded:    { AsyncStream { $0.finish() } }
        )
    }
}
