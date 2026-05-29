import Foundation
import MapKit

struct RideDetail: Equatable {
    let title: String
    let date: Date
    let elapsedTime: String
    let distance: String
    let averageSpeed: String
    let maxSpeed: String
    let averageCadence: String
    let maxCadence: String
    // Stored as flat arrays to keep Equatable conformance (CLLocationCoordinate2D is non-Equatable)
    let latitudes: [Double]
    let longitudes: [Double]
    let elevationSamples: [Double]
    let heartRateSamples: [Int]
    let stravaSegments: [RouteSegmentStub]

    // Convenience initialiser accepting CLLocationCoordinate2D directly
    init(title: String, date: Date, elapsedTime: String, distance: String,
         averageSpeed: String, maxSpeed: String, averageCadence: String, maxCadence: String,
         coordinates: [CLLocationCoordinate2D],
         elevationSamples: [Double], heartRateSamples: [Int],
         stravaSegments: [RouteSegmentStub]) {
        self.title = title; self.date = date; self.elapsedTime = elapsedTime
        self.distance = distance; self.averageSpeed = averageSpeed; self.maxSpeed = maxSpeed
        self.averageCadence = averageCadence; self.maxCadence = maxCadence
        self.latitudes  = coordinates.map(\.latitude)
        self.longitudes = coordinates.map(\.longitude)
        self.elevationSamples = elevationSamples
        self.heartRateSamples = heartRateSamples
        self.stravaSegments = stravaSegments
    }

    var coordinates: [CLLocationCoordinate2D] {
        zip(latitudes, longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
    }

    var startCoordinate: CLLocationCoordinate2D {
        coordinates.first ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    }

    var finishCoordinate: CLLocationCoordinate2D {
        coordinates.last ?? startCoordinate
    }

    var mapRegion: MKCoordinateRegion {
        guard !latitudes.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        let minLat = latitudes.min()!; let maxLat = latitudes.max()!
        let minLon = longitudes.min()!; let maxLon = longitudes.max()!
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                           longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.6, 0.015),
                longitudeDelta: max((maxLon - minLon) * 1.6, 0.015)
            )
        )
    }

    static func recordedRide(timestamp: Date) -> RideDetail {
        RideDetail(
            title: "Recorded Ride", date: timestamp,
            elapsedTime: "00:18:42", distance: "8.4",
            averageSpeed: "18.7", maxSpeed: "27.2",
            averageCadence: "91", maxCadence: "110",
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                CLLocationCoordinate2D(latitude: 37.3372, longitude: -122.0140),
                CLLocationCoordinate2D(latitude: 37.3424, longitude: -122.0168),
                CLLocationCoordinate2D(latitude: 37.3467, longitude: -122.0119)
            ],
            elevationSamples: [104, 118, 126, 121, 130, 142, 136, 124],
            heartRateSamples: [108, 124, 136, 148, 151, 146, 139, 128],
            stravaSegments: [
                RouteSegmentStub(name: "Warmup Rise",    distance: "0.8", bestTime: "2:36", bestTimeDate: timestamp),
                RouteSegmentStub(name: "Campus Return",  distance: "1.5", bestTime: "4:42", bestTimeDate: timestamp)
            ]
        )
    }
}
