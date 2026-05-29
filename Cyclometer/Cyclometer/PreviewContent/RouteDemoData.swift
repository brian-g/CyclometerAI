//
//  RouteDemoData.swift
//  Test-ToolbarAndAccessoryView
//

import Foundation
import MapKit

struct RouteStub: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let distance: String
    let elevationGain: String
    let windDirectionDegrees: Int
    let windSpeed: Int
    let coordinates: [CLLocationCoordinate2D]
    let elevationSamples: [Double]
    let stravaSegments: [RouteSegmentStub]
    let previousRides: [PreviousRouteRideStub]

    var windCompassDirection: String {
        let normalizedDegrees = ((windDirectionDegrees % 360) + 360) % 360
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(normalizedDegrees) / 45.0).rounded()) % directions.count
        return directions[index]
    }

    var startCoordinate: CLLocationCoordinate2D {
        coordinates.first ?? CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    }

    var finishCoordinate: CLLocationCoordinate2D {
        coordinates.last ?? startCoordinate
    }

    var mapRegion: MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? startCoordinate.latitude
        let maximumLatitude = latitudes.max() ?? startCoordinate.latitude
        let minimumLongitude = longitudes.min() ?? startCoordinate.longitude
        let maximumLongitude = longitudes.max() ?? startCoordinate.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.6, 0.015),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.6, 0.015)
            )
        )
    }

    static let openRide = RouteStub(
        name: "Open Ride",
        detail: "No predefined route",
        distance: "Open",
        elevationGain: "Open",
        windDirectionDegrees: 0,
        windSpeed: 0,
        coordinates: [
            CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            CLLocationCoordinate2D(latitude: 37.3370, longitude: -122.0050)
        ],
        elevationSamples: [50, 54, 52, 58],
        stravaSegments: [],
        previousRides: []
    )

    static let sampleRoutes: [RouteStub] = [
        RouteStub(
            name: "River Loop",
            detail: "22.4 • Rolling terrain",
            distance: "22.4",
            elevationGain: "840",
            windDirectionDegrees: 315,
            windSpeed: 9,
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0307),
                CLLocationCoordinate2D(latitude: 37.3387, longitude: -122.0454),
                CLLocationCoordinate2D(latitude: 37.3502, longitude: -122.0478),
                CLLocationCoordinate2D(latitude: 37.3600, longitude: -122.0381),
                CLLocationCoordinate2D(latitude: 37.3564, longitude: -122.0225),
                CLLocationCoordinate2D(latitude: 37.3421, longitude: -122.0191),
                CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0307)
            ],
            elevationSamples: [145, 154, 162, 188, 204, 196, 172, 158, 149, 145],
            stravaSegments: [
                RouteSegmentStub(name: "Creekside Sprint", distance: "0.7", bestTime: "1:42", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 4)),
                RouteSegmentStub(name: "North Bank Roller", distance: "2.1", bestTime: "6:18", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 4, day: 21)),
                RouteSegmentStub(name: "Bridge Return", distance: "1.4", bestTime: "4:05", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 3, day: 30))
            ],
            previousRides: [
                PreviousRouteRideStub(date: "May 4, 2026", elapsedTime: "1:18:32", condition: "Clear, light headwind"),
                PreviousRouteRideStub(date: "Apr 21, 2026", elapsedTime: "1:21:08", condition: "Cool, steady crosswind"),
                PreviousRouteRideStub(date: "Mar 30, 2026", elapsedTime: "1:24:47", condition: "Overcast")
            ]
        ),
        RouteStub(
            name: "Summit Climb",
            detail: "31.8 • 2,450 gain",
            distance: "31.8",
            elevationGain: "2,450",
            windDirectionDegrees: 270,
            windSpeed: 12,
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.3186, longitude: -122.0422),
                CLLocationCoordinate2D(latitude: 37.3265, longitude: -122.0608),
                CLLocationCoordinate2D(latitude: 37.3379, longitude: -122.0732),
                CLLocationCoordinate2D(latitude: 37.3497, longitude: -122.0814),
                CLLocationCoordinate2D(latitude: 37.3618, longitude: -122.0755),
                CLLocationCoordinate2D(latitude: 37.3702, longitude: -122.0604)
            ],
            elevationSamples: [210, 260, 410, 635, 900, 1220, 1480, 1695, 1510, 1325, 980, 640],
            stravaSegments: [
                RouteSegmentStub(name: "Lower Switchbacks", distance: "3.2", bestTime: "13:54", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 8)),
                RouteSegmentStub(name: "Summit Wall", distance: "1.1", bestTime: "7:26", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 4, day: 12)),
                RouteSegmentStub(name: "Ridge Tempo", distance: "4.8", bestTime: "15:39", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 3, day: 16))
            ],
            previousRides: [
                PreviousRouteRideStub(date: "May 8, 2026", elapsedTime: "2:11:05", condition: "Dry, west wind"),
                PreviousRouteRideStub(date: "Apr 12, 2026", elapsedTime: "2:18:44", condition: "Warm, gusty summit"),
                PreviousRouteRideStub(date: "Mar 16, 2026", elapsedTime: "2:25:10", condition: "Fog near the top")
            ]
        ),
        RouteStub(
            name: "Tempo Flats",
            detail: "18.1 • Fast and flat",
            distance: "18.1",
            elevationGain: "210",
            windDirectionDegrees: 180,
            windSpeed: 6,
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.3921, longitude: -122.0269),
                CLLocationCoordinate2D(latitude: 37.3995, longitude: -122.0124),
                CLLocationCoordinate2D(latitude: 37.4082, longitude: -121.9957),
                CLLocationCoordinate2D(latitude: 37.4164, longitude: -121.9843),
                CLLocationCoordinate2D(latitude: 37.4241, longitude: -121.9928),
                CLLocationCoordinate2D(latitude: 37.4140, longitude: -122.0102),
                CLLocationCoordinate2D(latitude: 37.3921, longitude: -122.0269)
            ],
            elevationSamples: [84, 88, 92, 90, 95, 98, 93, 87, 84],
            stravaSegments: [
                RouteSegmentStub(name: "Airport Straight", distance: "4.4", bestTime: "10:48", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 10)),
                RouteSegmentStub(name: "Tailwind Drag", distance: "2.6", bestTime: "6:02", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 4, day: 28))
            ],
            previousRides: [
                PreviousRouteRideStub(date: "May 10, 2026", elapsedTime: "54:16", condition: "Tailwind outbound"),
                PreviousRouteRideStub(date: "Apr 28, 2026", elapsedTime: "56:42", condition: "Calm"),
                PreviousRouteRideStub(date: "Apr 6, 2026", elapsedTime: "58:30", condition: "Light rain")
            ]
        ),
        RouteStub(
            name: "Coffee Spin",
            detail: "12.6 • Easy recovery pace",
            distance: "12.6",
            elevationGain: "320",
            windDirectionDegrees: 45,
            windSpeed: 5,
            coordinates: [
                CLLocationCoordinate2D(latitude: 37.3231, longitude: -122.0322),
                CLLocationCoordinate2D(latitude: 37.3294, longitude: -122.0244),
                CLLocationCoordinate2D(latitude: 37.3368, longitude: -122.0173),
                CLLocationCoordinate2D(latitude: 37.3446, longitude: -122.0217),
                CLLocationCoordinate2D(latitude: 37.3390, longitude: -122.0350),
                CLLocationCoordinate2D(latitude: 37.3231, longitude: -122.0322)
            ],
            elevationSamples: [130, 144, 151, 168, 160, 146, 136, 130],
            stravaSegments: [
                RouteSegmentStub(name: "Cafe Kick", distance: "0.5", bestTime: "1:28", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 11)),
                RouteSegmentStub(name: "Neighborhood Rise", distance: "1.2", bestTime: "4:52", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 2))
            ],
            previousRides: [
                PreviousRouteRideStub(date: "May 11, 2026", elapsedTime: "46:22", condition: "Recovery pace"),
                PreviousRouteRideStub(date: "May 2, 2026", elapsedTime: "44:55", condition: "Easy spin"),
                PreviousRouteRideStub(date: "Apr 19, 2026", elapsedTime: "48:11", condition: "Stop-and-go traffic")
            ]
        )
    ]
}



struct RouteSegmentStub: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let distance: String
    let bestTime: String
    let bestTimeDate: Date

    static func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(calendar: .current, year: year, month: month, day: day).date ?? .now
    }
}

struct PreviousRouteRideStub: Identifiable {
    let id = UUID()
    let date: String
    let elapsedTime: String
    let condition: String
}

extension RouteStub {
    static let availableRoutes: [RouteStub] = [.openRide] + sampleRoutes
}

extension RouteStub {
    var currentTemperature: String { "77°" }
}
