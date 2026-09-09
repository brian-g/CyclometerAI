import Foundation
import Testing
import CoreLocation
@testable import Cyclometer

@Suite("LocationClient")
struct LocationClientTests {

    // MARK: - Model equality

    @Test("Coordinate equality compares latitude and longitude")
    func coordinateEquality() {
        let a = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let b = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let c = Coordinate(latitude: 43.0732, longitude: -89.4012)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Coordinate is hashable")
    func coordinateHashable() {
        let a = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let b = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let set: Set<Coordinate> = [a, b]
        #expect(set.count == 1)
    }

    @Test("Coordinate bridges to CLLocationCoordinate2D")
    func coordinateBridge() {
        let coord = Coordinate(latitude: 43.0731, longitude: -89.4012)
        let cl = coord.clLocationCoordinate2D
        #expect(cl.latitude == 43.0731)
        #expect(cl.longitude == -89.4012)
    }

    @Test("LocationUpdate equality compares all fields")
    func locationUpdateEquality() {
        let ts = Date(timeIntervalSince1970: 1_000_000)
        let a = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 8.5,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        let b = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 8.5,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        let c = LocationUpdate(
            coordinate: Coordinate(latitude: 43.0731, longitude: -89.4012),
            altitude: 280.0,
            speed: 9.0,
            horizontalAccuracy: 5.0,
            heading: 90.0,
            timestamp: ts
        )
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - testValue behaviour

    @Test("testValue startUpdates stream completes immediately")
    func testValueStream() async {
        let client = LocationClient.testValue
        var count = 0
        for await _ in client.startUpdates() { count += 1 }
        #expect(count == 0)
    }

    @Test("testValue stopUpdates does not crash")
    func testValueStop() async {
        let client = LocationClient.testValue
        await client.stopUpdates()
    }

    /// Nil rather than a fabricated coordinate: a feature that has not overridden the
    /// dependency should exercise its no-fix branch, which for S19 is the one a rider with
    /// location denied actually sees (#193).
    @Test("testValue currentCoordinate returns no fix")
    func testValueCurrentCoordinate() async {
        #expect(await LocationClient.testValue.currentCoordinate() == nil)
    }
}

// MARK: - One-shot fix (#193)

/// `LocationManagerState` is a singleton with a private `init`, so these drive the shared
/// instance. That is enough to cover what the one-shot actually risks: the continuation table
/// is what a double resume would crash on, and a waiter that is never resumed hangs forever.
///
/// The simulator has no location set under `xcodebuild test`, so `requestLocation()` never
/// delivers — which is precisely the timeout path.
@Suite("LocationManagerState — one-shot fix")
struct LocationOneShotTests {

    @Test("A request with no fix available resolves nil rather than hanging")
    func timeoutResolvesNil() async {
        let coordinate = await LocationManagerState.shared.currentCoordinate(timeout: .milliseconds(200))
        #expect(coordinate == nil)
    }

    /// Every waiter has its own id in the table, and `drainOneShots` resumes all of them at
    /// once while the per-waiter timers race it. If removal-under-lock were not what gates a
    /// resume, this is where a double resume would trap.
    @Test("Concurrent requests each get exactly one answer")
    func concurrentRequestsAllResolve() async {
        let answers = await withTaskGroup(of: Coordinate?.self, returning: [Coordinate?].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await LocationManagerState.shared.currentCoordinate(timeout: .milliseconds(200))
                }
            }
            var collected: [Coordinate?] = []
            for await answer in group { collected.append(answer) }
            return collected
        }
        #expect(answers.count == 8)
    }

    /// The whole point of the one-shot is that it never touches `stopUpdates()`, which would
    /// end a recording ride's stream. This pins the pairing: a live subscriber survives it.
    @Test("Asking for a one-shot leaves an active update stream running")
    func oneShotDoesNotDisturbAnActiveStream() async {
        let stream = LocationManagerState.shared.makeUpdateStream()
        var iterator = stream.makeAsyncIterator()

        _ = await LocationManagerState.shared.currentCoordinate(timeout: .milliseconds(200))

        // Finishing the stream would make the next element nil immediately; instead this
        // races the (never-arriving) first fix, so a timeout means the stream is still open.
        let finished = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { _ = await iterator.next(); return true }
            group.addTask { try? await Task.sleep(for: .milliseconds(300)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(finished == false, "the one-shot finished a live update stream")

        await LocationManagerState.shared.stopUpdates()
    }
}
