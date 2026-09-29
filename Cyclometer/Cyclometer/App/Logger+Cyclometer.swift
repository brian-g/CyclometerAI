import os

extension Logger {
    /// One subsystem for the whole app, so a single `log stream` predicate catches everything.
    static let subsystem = "com.xavier.cyclometer"

    /// Category names as they appear in Console. The raw values are what saved log filters match;
    /// don't rename a case without treating it as a filter-breaking change.
    enum Category: String {
        case alerts, audio, ble, csc, healthkit, hr, location, navigation, network
        case permissions, persistence, radar, recording, routes
    }

    static func cyclometer(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
