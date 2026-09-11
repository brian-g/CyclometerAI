import Foundation
import os

private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "routes")

/// What every screen that shows the saved-route library shares: its symbol, and what a failed read
/// says. S19 and S05.2 read the same library and fail the same way (#196), so a wording change made
/// in one and not the other would be a rider meeting two apps.
enum RouteLibrary {
    static let symbolName = "point.topleft.down.curvedto.point.bottomright.up"

    static let loadFailedTitle = "Couldn't Load Routes"
    static let loadFailedMessage = "Your saved routes couldn't be read. Try again in a moment."
}

extension PersistenceClient {
    /// `fetchRoutes`, logged and reduced to the rider-facing `PersistenceFailure` — the one read S19
    /// and S05.2 both make, so they cannot drift in how it fails.
    func loadRoutes() async -> Result<[RouteSummary], PersistenceFailure> {
        do {
            return .success(try await fetchRoutes())
        } catch {
            logger.error("fetchRoutes failed: \(error.localizedDescription, privacy: .public)")
            return .failure(PersistenceFailure())
        }
    }
}
