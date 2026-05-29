//
//  DemoRideData.swift
//  Test-ToolbarAndAccessoryView
//

import Foundation
import MapKit

struct DemoRide: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let date: Date
    let elapsedTime: String
    let distance: String
    let detail: RideDetail

    static let sampleRides: [DemoRide] = [
        DemoRide(
            title: "River Loop",
            date: date(year: 2026, month: 5, day: 17, hour: 7, minute: 12),
            elapsedTime: "1:18:32",
            distance: "22.4",
            detail: RideDetail(
                title: "River Loop",
                date: date(year: 2026, month: 5, day: 17, hour: 7, minute: 12),
                elapsedTime: "1:18:32",
                distance: "22.4",
                averageSpeed: "17.1",
                maxSpeed: "31.8",
                averageCadence: "86",
                maxCadence: "112",
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
                heartRateSamples: [112, 124, 138, 146, 152, 149, 141, 134, 128, 120],
                stravaSegments: [
                    RouteSegmentStub(name: "Creekside Sprint", distance: "0.7", bestTime: "1:42", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 17)),
                    RouteSegmentStub(name: "North Bank Roller", distance: "2.1", bestTime: "6:18", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 17))
                ]
            )
        ),
        DemoRide(
            title: "Summit Climb",
            date: date(year: 2026, month: 5, day: 15, hour: 6, minute: 45),
            elapsedTime: "2:11:05",
            distance: "31.8",
            detail: RideDetail(
                title: "Summit Climb",
                date: date(year: 2026, month: 5, day: 15, hour: 6, minute: 45),
                elapsedTime: "2:11:05",
                distance: "31.8",
                averageSpeed: "14.6",
                maxSpeed: "42.3",
                averageCadence: "79",
                maxCadence: "104",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3186, longitude: -122.0422),
                    CLLocationCoordinate2D(latitude: 37.3265, longitude: -122.0608),
                    CLLocationCoordinate2D(latitude: 37.3379, longitude: -122.0732),
                    CLLocationCoordinate2D(latitude: 37.3497, longitude: -122.0814),
                    CLLocationCoordinate2D(latitude: 37.3618, longitude: -122.0755),
                    CLLocationCoordinate2D(latitude: 37.3702, longitude: -122.0604)
                ],
                elevationSamples: [210, 260, 410, 635, 900, 1220, 1480, 1695, 1510, 1325, 980, 640],
                heartRateSamples: [118, 132, 145, 154, 163, 171, 176, 172, 164, 151, 138, 126],
                stravaSegments: [
                    RouteSegmentStub(name: "Lower Switchbacks", distance: "3.2", bestTime: "13:54", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 15)),
                    RouteSegmentStub(name: "Summit Wall", distance: "1.1", bestTime: "7:26", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 15))
                ]
            )
        ),
        DemoRide(
            title: "Tempo Flats",
            date: date(year: 2026, month: 5, day: 13, hour: 17, minute: 34),
            elapsedTime: "54:16",
            distance: "18.1",
            detail: RideDetail(
                title: "Tempo Flats",
                date: date(year: 2026, month: 5, day: 13, hour: 17, minute: 34),
                elapsedTime: "54:16",
                distance: "18.1",
                averageSpeed: "20.0",
                maxSpeed: "28.6",
                averageCadence: "94",
                maxCadence: "118",
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
                heartRateSamples: [116, 128, 140, 148, 151, 154, 149, 137, 122],
                stravaSegments: [
                    RouteSegmentStub(name: "Airport Straight", distance: "4.4", bestTime: "10:48", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 13)),
                    RouteSegmentStub(name: "Tailwind Drag", distance: "2.6", bestTime: "6:02", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 13))
                ]
            )
        ),
        DemoRide(
            title: "Coffee Spin",
            date: date(year: 2026, month: 5, day: 11, hour: 8, minute: 20),
            elapsedTime: "46:22",
            distance: "12.6",
            detail: RideDetail(
                title: "Coffee Spin",
                date: date(year: 2026, month: 5, day: 11, hour: 8, minute: 20),
                elapsedTime: "46:22",
                distance: "12.6",
                averageSpeed: "16.3",
                maxSpeed: "25.1",
                averageCadence: "82",
                maxCadence: "101",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3231, longitude: -122.0322),
                    CLLocationCoordinate2D(latitude: 37.3294, longitude: -122.0244),
                    CLLocationCoordinate2D(latitude: 37.3368, longitude: -122.0173),
                    CLLocationCoordinate2D(latitude: 37.3446, longitude: -122.0217),
                    CLLocationCoordinate2D(latitude: 37.3390, longitude: -122.0350),
                    CLLocationCoordinate2D(latitude: 37.3231, longitude: -122.0322)
                ],
                elevationSamples: [130, 144, 151, 168, 160, 146, 136, 130],
                heartRateSamples: [104, 112, 119, 126, 132, 124, 116, 108],
                stravaSegments: [
                    RouteSegmentStub(name: "Cafe Kick", distance: "0.5", bestTime: "1:28", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 11)),
                    RouteSegmentStub(name: "Neighborhood Rise", distance: "1.2", bestTime: "4:52", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 11))
                ]
            )
        ),
        DemoRide(
            title: "Evening Paceline",
            date: date(year: 2026, month: 5, day: 9, hour: 18, minute: 5),
            elapsedTime: "1:07:49",
            distance: "24.7",
            detail: RideDetail(
                title: "Evening Paceline",
                date: date(year: 2026, month: 5, day: 9, hour: 18, minute: 5),
                elapsedTime: "1:07:49",
                distance: "24.7",
                averageSpeed: "21.8",
                maxSpeed: "34.4",
                averageCadence: "97",
                maxCadence: "124",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3553, longitude: -122.0021),
                    CLLocationCoordinate2D(latitude: 37.3665, longitude: -121.9898),
                    CLLocationCoordinate2D(latitude: 37.3814, longitude: -121.9810),
                    CLLocationCoordinate2D(latitude: 37.3948, longitude: -121.9890),
                    CLLocationCoordinate2D(latitude: 37.3880, longitude: -122.0086),
                    CLLocationCoordinate2D(latitude: 37.3718, longitude: -122.0138),
                    CLLocationCoordinate2D(latitude: 37.3553, longitude: -122.0021)
                ],
                elevationSamples: [96, 104, 118, 126, 121, 112, 108, 101, 96],
                heartRateSamples: [124, 139, 151, 158, 164, 168, 162, 148, 133],
                stravaSegments: [
                    RouteSegmentStub(name: "Industrial Leadout", distance: "1.8", bestTime: "4:14", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 9)),
                    RouteSegmentStub(name: "Paceline Return", distance: "3.6", bestTime: "8:59", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 9))
                ]
            )
        ),
        DemoRide(
            title: "Harbor Rollers",
            date: date(year: 2026, month: 5, day: 7, hour: 6, minute: 58),
            elapsedTime: "1:32:14",
            distance: "27.9",
            detail: RideDetail(
                title: "Harbor Rollers",
                date: date(year: 2026, month: 5, day: 7, hour: 6, minute: 58),
                elapsedTime: "1:32:14",
                distance: "27.9",
                averageSpeed: "18.2",
                maxSpeed: "36.7",
                averageCadence: "88",
                maxCadence: "116",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3018, longitude: -122.0322),
                    CLLocationCoordinate2D(latitude: 37.3094, longitude: -122.0476),
                    CLLocationCoordinate2D(latitude: 37.3207, longitude: -122.0564),
                    CLLocationCoordinate2D(latitude: 37.3342, longitude: -122.0511),
                    CLLocationCoordinate2D(latitude: 37.3426, longitude: -122.0365),
                    CLLocationCoordinate2D(latitude: 37.3315, longitude: -122.0228),
                    CLLocationCoordinate2D(latitude: 37.3018, longitude: -122.0322)
                ],
                elevationSamples: [118, 132, 156, 172, 164, 189, 211, 184, 146, 118],
                heartRateSamples: [110, 126, 141, 150, 154, 159, 153, 144, 132, 118],
                stravaSegments: [
                    RouteSegmentStub(name: "Harbor Ramp", distance: "1.4", bestTime: "4:08", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 7)),
                    RouteSegmentStub(name: "Marina Rollers", distance: "2.9", bestTime: "8:31", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 7))
                ]
            )
        ),
        DemoRide(
            title: "Lunch Break Laps",
            date: date(year: 2026, month: 5, day: 5, hour: 12, minute: 14),
            elapsedTime: "38:49",
            distance: "10.8",
            detail: RideDetail(
                title: "Lunch Break Laps",
                date: date(year: 2026, month: 5, day: 5, hour: 12, minute: 14),
                elapsedTime: "38:49",
                distance: "10.8",
                averageSpeed: "16.7",
                maxSpeed: "24.9",
                averageCadence: "84",
                maxCadence: "106",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3480, longitude: -122.0414),
                    CLLocationCoordinate2D(latitude: 37.3534, longitude: -122.0350),
                    CLLocationCoordinate2D(latitude: 37.3592, longitude: -122.0261),
                    CLLocationCoordinate2D(latitude: 37.3656, longitude: -122.0312),
                    CLLocationCoordinate2D(latitude: 37.3584, longitude: -122.0448),
                    CLLocationCoordinate2D(latitude: 37.3480, longitude: -122.0414)
                ],
                elevationSamples: [92, 96, 104, 116, 111, 103, 98, 92],
                heartRateSamples: [104, 118, 132, 142, 146, 139, 126, 112],
                stravaSegments: [
                    RouteSegmentStub(name: "Park Lap", distance: "1.7", bestTime: "5:34", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 5)),
                    RouteSegmentStub(name: "Office Sprint", distance: "0.4", bestTime: "0:58", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 5))
                ]
            )
        ),
        DemoRide(
            title: "Canyon Tempo",
            date: date(year: 2026, month: 5, day: 3, hour: 7, minute: 30),
            elapsedTime: "1:46:03",
            distance: "34.2",
            detail: RideDetail(
                title: "Canyon Tempo",
                date: date(year: 2026, month: 5, day: 3, hour: 7, minute: 30),
                elapsedTime: "1:46:03",
                distance: "34.2",
                averageSpeed: "19.4",
                maxSpeed: "39.8",
                averageCadence: "92",
                maxCadence: "120",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.2896, longitude: -122.0716),
                    CLLocationCoordinate2D(latitude: 37.3008, longitude: -122.0840),
                    CLLocationCoordinate2D(latitude: 37.3159, longitude: -122.0918),
                    CLLocationCoordinate2D(latitude: 37.3322, longitude: -122.0872),
                    CLLocationCoordinate2D(latitude: 37.3415, longitude: -122.0749),
                    CLLocationCoordinate2D(latitude: 37.3304, longitude: -122.0611),
                    CLLocationCoordinate2D(latitude: 37.3070, longitude: -122.0582),
                    CLLocationCoordinate2D(latitude: 37.2896, longitude: -122.0716)
                ],
                elevationSamples: [220, 276, 340, 412, 476, 498, 442, 351, 274, 220],
                heartRateSamples: [116, 132, 146, 155, 162, 166, 159, 148, 136, 121],
                stravaSegments: [
                    RouteSegmentStub(name: "Canyon Pull", distance: "4.1", bestTime: "12:12", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 3)),
                    RouteSegmentStub(name: "Reservoir Descent", distance: "3.3", bestTime: "5:46", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 3))
                ]
            )
        ),
        DemoRide(
            title: "Recovery Greenway",
            date: date(year: 2026, month: 5, day: 1, hour: 16, minute: 42),
            elapsedTime: "52:07",
            distance: "14.3",
            detail: RideDetail(
                title: "Recovery Greenway",
                date: date(year: 2026, month: 5, day: 1, hour: 16, minute: 42),
                elapsedTime: "52:07",
                distance: "14.3",
                averageSpeed: "16.5",
                maxSpeed: "22.7",
                averageCadence: "80",
                maxCadence: "96",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3734, longitude: -122.0468),
                    CLLocationCoordinate2D(latitude: 37.3810, longitude: -122.0402),
                    CLLocationCoordinate2D(latitude: 37.3886, longitude: -122.0318),
                    CLLocationCoordinate2D(latitude: 37.3974, longitude: -122.0250),
                    CLLocationCoordinate2D(latitude: 37.4051, longitude: -122.0296),
                    CLLocationCoordinate2D(latitude: 37.3960, longitude: -122.0435),
                    CLLocationCoordinate2D(latitude: 37.3734, longitude: -122.0468)
                ],
                elevationSamples: [74, 78, 82, 88, 91, 86, 80, 74],
                heartRateSamples: [98, 104, 110, 116, 118, 112, 106, 100],
                stravaSegments: [
                    RouteSegmentStub(name: "Greenway Cruise", distance: "2.2", bestTime: "7:05", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 1)),
                    RouteSegmentStub(name: "Creek Path", distance: "1.6", bestTime: "5:18", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 5, day: 1))
                ]
            )
        ),
        DemoRide(
            title: "Rain Check Ride",
            date: date(year: 2026, month: 4, day: 29, hour: 9, minute: 6),
            elapsedTime: "1:12:36",
            distance: "19.5",
            detail: RideDetail(
                title: "Rain Check Ride",
                date: date(year: 2026, month: 4, day: 29, hour: 9, minute: 6),
                elapsedTime: "1:12:36",
                distance: "19.5",
                averageSpeed: "16.1",
                maxSpeed: "29.4",
                averageCadence: "83",
                maxCadence: "109",
                coordinates: [
                    CLLocationCoordinate2D(latitude: 37.3128, longitude: -122.0124),
                    CLLocationCoordinate2D(latitude: 37.3204, longitude: -122.0018),
                    CLLocationCoordinate2D(latitude: 37.3349, longitude: -121.9962),
                    CLLocationCoordinate2D(latitude: 37.3492, longitude: -122.0020),
                    CLLocationCoordinate2D(latitude: 37.3461, longitude: -122.0184),
                    CLLocationCoordinate2D(latitude: 37.3290, longitude: -122.0256),
                    CLLocationCoordinate2D(latitude: 37.3128, longitude: -122.0124)
                ],
                elevationSamples: [126, 139, 151, 147, 158, 174, 169, 145, 126],
                heartRateSamples: [109, 121, 133, 141, 145, 143, 136, 125, 114],
                stravaSegments: [
                    RouteSegmentStub(name: "Wet Pavement Rise", distance: "1.9", bestTime: "6:21", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 4, day: 29)),
                    RouteSegmentStub(name: "Shelter Sprint", distance: "0.6", bestTime: "1:33", bestTimeDate: RouteSegmentStub.date(year: 2026, month: 4, day: 29))
                ]
            )
        )
    ]

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(calendar: .current, year: year, month: month, day: day, hour: hour, minute: minute).date ?? .now
    }
}

