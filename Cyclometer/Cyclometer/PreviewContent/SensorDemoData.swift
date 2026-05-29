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

struct SensorStub: Identifiable {
    let id = UUID()
    let name: String
    let systemImage: String
    let status: String
    let detail: String
    let tint: Color
}

extension SensorStub {
    static let newRideDemoSensors = [
        SensorStub(name: "Heart Rate", systemImage: "heart.fill", status: "Ready", detail: "Chest strap stub connected", tint: .red),
        SensorStub(name: "Speed", systemImage: "speedometer", status: "Searching", detail: "Wheel sensor stub scanning", tint: .orange),
        SensorStub(name: "GPS", systemImage: "location.fill", status: "Locked", detail: "High accuracy location stub", tint: .blue),
        SensorStub(name: "Cadence", systemImage: "dial.medium.fill", status: "Ready", detail: "Crank sensor stub connected", tint: .green),
        SensorStub(name: "RADAR", systemImage: "dot.radiowaves.forward", status: "Standby", detail: "Rear radar stub available", tint: .purple),
        SensorStub(name: "Power", systemImage: "bolt.fill", status: "Ready", detail: "Power meter stub connected", tint: .pink),
        SensorStub(name: "Heads Up Display", systemImage: "glasses.fill", status: "Ready", detail: "Engo 3 Glasses", tint: .yellow)
    ]
}

struct NewRideDemoData {
    static let bikeName = "Road Bike Stub"
    static let recordingSummary = "Auto-pause On"
}
