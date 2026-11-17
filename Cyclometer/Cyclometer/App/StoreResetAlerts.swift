import ComposableArchitecture
import Foundation

/// The alerts of the rider's store reset (#206): the confirmation, then what it did. Worded
/// for whichever store failed. Losing history costs the ride list and routes, while losing
/// tracks costs past rides' maps and charts. Every one says the GPX files are untouched,
/// since for a rider whose history is gone they are what is left.
extension AlertState where Action == AppFeature.Action.StoreReset {
    static func confirmReset(_ status: PersistentStoreStatus) -> Self {
        AlertState {
            TextState(status.history != nil ? "Reset Ride History?" : "Reset Ride Tracks?")
        } actions: {
            ButtonState(role: .destructive, action: .confirm) {
                TextState("Reset")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState(status.history != nil
                ? "Starts a new, empty ride history and route library. The old history is kept on this iPhone for recovery. Ride GPX files in Files are not touched."
                : "Starts a new store for ride tracks. The old one is kept on this iPhone for recovery. Your rides and their GPX files are not touched.")
        }
    }

    /// Names what was preserved, so it can be found again: the rider's support request, or a
    /// copy pulled off the device, starts from the file name.
    static func resetFinished(_ reset: PersistentStoreReset) -> Self {
        guard !reset.status.isDegraded else {
            return AlertState {
                TextState("Couldn't Start Fresh")
            } message: {
                TextState("The new store couldn't be opened either. Make sure this iPhone has free storage, then try again. Nothing more was lost.")
            }
        }
        let names = reset.preservedStores.map(\.lastPathComponent)
        return AlertState {
            TextState("Reset Complete")
        } message: {
            TextState(names.isEmpty
                ? "A new store is ready. Ride GPX files in Files are not touched."
                : "The old store was kept on this iPhone as \(names.formatted(.list(type: .and))), in the app's Preserved Stores folder. Ride GPX files in Files are not touched.")
        }
    }

    static let resetFailed = AlertState {
        TextState("Couldn't Reset")
    } message: {
        TextState("Nothing was changed. Try again.")
    }
}
