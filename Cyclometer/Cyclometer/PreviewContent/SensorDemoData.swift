//
//  SensorDemoData.swift
//  Test-ToolbarAndAccessoryView
//

import Foundation
import SwiftUI

struct SensorStatus: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let status: String
    let systemImage: String
    let tint: Color
}

extension SensorStatus {
    static let demoSensors = [
        SensorStatus(name: "Heart Rate", detail: "Chest strap", status: "Connected", systemImage: "heart.fill", tint: Color.red),
        SensorStatus(name: "Speed", detail: "Front hub", status: "Searching", systemImage: "speedometer", tint: Color.blue),
        SensorStatus(name: "Cadence", detail: "Crank arm", status: "Connected", systemImage: "metronome", tint: Color.orange)
    ]
}

struct NewRideDemoData {
    static let bikeName = "Road Bike Stub"
}
