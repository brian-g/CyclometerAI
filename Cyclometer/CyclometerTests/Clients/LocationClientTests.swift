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

    @Test("testValue requestAuthorization returns authorizedWhenInUse")
    func testValueAuth() async {
        let client = LocationClient.testValue
        let status = await client.requestAuthorization()
        #expect(status == .authorizedWhenInUse)
    }

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
}
