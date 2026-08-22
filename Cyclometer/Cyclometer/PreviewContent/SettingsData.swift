//
//  SettingsData.swift
//  Cyclometer
//

import Foundation

struct SettingsData {
    static let privacyPolicyParagraphs = [
        "Cyclometer records your GPS route, heart rate, speed, cadence, and radar alerts during a ride. Ride history and GPX route files are stored only in Cyclometer's private storage on your device.",
        "Cyclometer asks for When In Use access to record your route, and Always access so an in-progress recording keeps running if you lock your phone or switch apps mid-ride. GPS is off whenever you are not recording.",
        "Cyclometer reads your resting heart rate, maximum heart rate, and date of birth from Apple Health to calculate your personal HR zones, and writes each completed ride to Apple Health as a workout so it appears in the Fitness app and counts toward your Activity rings. You can review or revoke this access anytime in the Health app.",
        "Cyclometer connects over Bluetooth to the sensors you pair — heart rate strap, speed/cadence sensor, and radar (e.g. Garmin Varia). Each paired sensor's Bluetooth identifier is stored on your device so it can reconnect automatically; sensor data is never shared with anyone else.",
        "Cyclometer doesn't require an account or login. Your ride and location data stay on your device unless you explicitly export a GPX file or link a connected service — we never sell your data or share it with third parties for advertising. You can change location, Bluetooth, motion, or Health permissions anytime in iOS Settings; deleting the app removes all locally stored ride data."
    ]
}
