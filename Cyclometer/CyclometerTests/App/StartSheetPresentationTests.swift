import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// The Start sheet's pairing scan, exercised through the presentation that owns it.
///
/// `StartSheetFeatureTests` drives the reducer directly and so cannot see this: the sheet
/// is a `@Presents` child, and every dismissal path clears `AppFeature.State.startSheet`
/// *before* SwiftUI runs `onDisappear` — so an action sent from there reaches an absent
/// destination and TCA drops it. A scan balanced from `.onDisappear` therefore never was,
/// leaking a reference on all three clients per sheet open and leaving the radio on for
/// the rest of the process. The release is tied to the effect's own cancellation instead,
/// and only a test at this level proves it.
@MainActor
@Suite("AppFeature — Start sheet pairing scan")
struct StartSheetPresentationTests {

    /// One log across all three clients, so the *balance* between them is what is
    /// asserted rather than three counters that each look plausible alone.
    enum ScanCall: Equatable {
        case begin(SensorKind)
        case end(SensorKind)
    }

    static func makeStore(into log: LockIsolated<[ScanCall]>) -> TestStoreOf<AppFeature> {
        let storage = FileStorage.inMemory
        return withDependencies {
            $0.defaultFileStorage = storage
        } operation: {
            var csc = BLECSCClient.testValue
            csc.beginPairingScan = { log.withValue { $0.append(.begin(.speedCadence)) } }
            csc.endPairingScan = { log.withValue { $0.append(.end(.speedCadence)) } }
            var radar = VariaRadarClient.testValue
            radar.beginPairingScan = { log.withValue { $0.append(.begin(.radar)) } }
            radar.endPairingScan = { log.withValue { $0.append(.end(.radar)) } }
            var hr = BLEHRClient.testValue
            hr.beginPairingScan = { log.withValue { $0.append(.begin(.heartRate)) } }
            hr.endPairingScan = { log.withValue { $0.append(.end(.heartRate)) } }

            return TestStore(initialState: AppFeature.State()) {
                AppFeature()
            } withDependencies: {
                $0.bleCSCClient = csc
                $0.variaRadarClient = radar
                $0.bleHRClient = hr
                $0.defaultFileStorage = storage
                // The ride-start path runs `activeRide(.task)` on its way past. Its own
                // behaviour is `ActiveRideFeatureTests`' business; here it only has to
                // not fail on an unimplemented dependency while the scan is released.
                $0.continuousClock = TestClock()
                $0.date = .constant(Date(timeIntervalSince1970: 1_000_000))
                $0.uuid = .incrementing
                $0.hapticsClient = .testValue
                $0.locationClient = .testValue
                $0.permissionsClient = .testValue
            }
        }
    }

    private static let begun: [ScanCall] = [.begin(.speedCadence), .begin(.radar), .begin(.heartRate)]
    private static let ended: [ScanCall] = [.end(.speedCadence), .end(.radar), .end(.heartRate)]

    /// Cancel, and the swipe-to-dismiss gesture, both arrive as `.dismiss`.
    @Test("Dismissing the sheet releases every scan it took")
    func dismissReleasesTheScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        #expect(log.value == Self.begun)

        await store.send(.startSheet(.dismiss))
        await store.finish()

        #expect(log.value == Self.begun + Self.ended)
    }

    /// The other path: the parent nils the presented state itself when the ride starts.
    @Test("Starting the ride releases every scan the sheet took")
    func startingTheRideReleasesTheScan() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.startRideButtonTapped)
        await store.send(.startSheet(.presented(.task)))
        #expect(log.value == Self.begun)

        await store.send(.startSheet(.presented(.delegate(.startRide))))
        await store.finish()

        #expect(log.value == Self.begun + Self.ended)
    }

    /// Opening the sheet twice must not leave the radio holding two references.
    @Test("Two sheet openings balance to zero")
    func repeatedOpeningsBalance() async {
        let log = LockIsolated<[ScanCall]>([])
        let store = Self.makeStore(into: log)
        store.exhaustivity = .off(showSkippedAssertions: false)

        for _ in 0..<2 {
            await store.send(.startRideButtonTapped)
            await store.send(.startSheet(.presented(.task)))
            await store.send(.startSheet(.dismiss))
        }
        await store.finish()

        let begins = log.value.filter { if case .begin = $0 { return true } else { return false } }
        let ends = log.value.filter { if case .end = $0 { return true } else { return false } }
        #expect(begins.count == 6)
        #expect(ends.count == 6)
    }
}
