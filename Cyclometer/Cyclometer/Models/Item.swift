import Foundation
import SwiftData

/// Minimal SwiftData model representing a recorded ride.
/// This will be replaced by the full Ride model (PRD §10) when persistence is implemented in M7.
@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
