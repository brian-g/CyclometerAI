//
//  SettingsDemoData.swift
//  Test-ToolbarAndAccessoryView
//

import Foundation

struct HeartRateZoneSetting: Identifiable, Equatable {
    let id: Int
    let name: String
    var lowerBound: Int
    var upperBound: Int

    static let standardZones = [
        HeartRateZoneSetting(id: 1, name: "Zone 1", lowerBound: 95, upperBound: 113),
        HeartRateZoneSetting(id: 2, name: "Zone 2", lowerBound: 114, upperBound: 132),
        HeartRateZoneSetting(id: 3, name: "Zone 3", lowerBound: 133, upperBound: 151),
        HeartRateZoneSetting(id: 4, name: "Zone 4", lowerBound: 152, upperBound: 170),
        HeartRateZoneSetting(id: 5, name: "Zone 5", lowerBound: 171, upperBound: 190)
    ]
}



struct SettingsDemoData {
    static let units = ["Imperial", "Metric"]
    static let stravaAccountStatus = "Not Connected"
    static let rideWithGPSAccountStatus = "Not Connected"
    static let privacyPolicyParagraphs = [
        "Ride data, sensor readings, and account connections stay on this device unless you choose to connect a third-party service. Connected services may receive the ride details needed to sync your activity.",
        "Location information is used to record and display rides. You can change location, notification, and health permissions in the system Settings app at any time.",
        "This test app does not sell personal information or use ride data for advertising."
    ]
}
