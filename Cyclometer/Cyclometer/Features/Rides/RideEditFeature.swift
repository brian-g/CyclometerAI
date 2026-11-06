import ComposableArchitecture
import Foundation

/// S15's Edit sheet (#538): the ride's title and notes.
///
/// Writes nothing itself. Save hands the edit to `RideDetailFeature`, which closes the sheet and
/// writes it: S15 stays on the stack, so its effects outlive the sheet's.
@Reducer
struct RideEditFeature {
    @ObservableState
    struct State: Equatable {
        /// What the ride had when the sheet opened, so Save stays off until something changes.
        let originalTitle: String
        let originalNotes: String
        var title: String
        var notes: String

        init(title: String, notes: String) {
            originalTitle = title
            originalNotes = notes
            self.title = title
            self.notes = notes
        }

        /// What Save writes. Surrounding whitespace is dropped, so notes of only spaces are no
        /// notes, and S15 shows nothing under its title.
        var titleToSave: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
        var notesToSave: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

        /// A ride always keeps a title: S15 has nothing to fall back on but "Ride".
        var canSave: Bool {
            !titleToSave.isEmpty && (titleToSave != originalTitle || notesToSave != originalNotes)
        }
    }

    enum Action: Equatable {
        case titleChanged(String)
        case notesChanged(String)
        case saveTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case save(title: String, notes: String)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .titleChanged(let title):
                state.title = title
                return .none
            case .notesChanged(let notes):
                state.notes = notes
                return .none
            case .saveTapped:
                guard state.canSave else { return .none }
                return .send(.delegate(.save(title: state.titleToSave, notes: state.notesToSave)))
            case .delegate:
                return .none
            }
        }
    }
}
