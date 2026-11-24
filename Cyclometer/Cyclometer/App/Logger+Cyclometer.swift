import os

extension Logger {
    /// One subsystem for the whole app, so a single `log stream` predicate catches everything.
    static let subsystem = "xyz.acmeapps.ride"

    /// Category names as they appear in Console. The raw values are what saved log filters match;
    /// don't rename a case without treating it as a filter-breaking change.
    enum Category: String {
        /// Connected services (S12 Accounts, PRD §8.12): sign-in, tokens and their Keychain items.
        case accounts
        case alerts, audio, ble, csc, healthkit, hr, location, navigation, network
        case permissions, persistence, radar, recording, routes
        /// Lowercase like the rest, so a filter written in their style matches.
        case liveActivity = "liveactivity"
    }

    static func cyclometer(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
