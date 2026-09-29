import CoreGraphics
import Testing
@testable import Cyclometer

/// #330 — when a drag on the dashboard's grabber minimises it:
/// `RideDashboardView.shouldDismiss(translation:predictedEndTranslation:)`.
@MainActor
@Suite("Ride dashboard — grabber dismiss")
struct DashboardDismissTests {

    private func dismisses(travel: CGSize, predicted: CGSize) -> Bool {
        RideDashboardView.shouldDismiss(translation: travel, predictedEndTranslation: predicted)
    }

    @Test("a long drag released at rest dismisses")
    func longDragDismisses() {
        #expect(dismisses(travel: CGSize(width: 0, height: 356), predicted: CGSize(width: 0, height: 356)))
    }

    @Test("a short fast flick dismisses, judged on where it was heading")
    func flickDismisses() {
        #expect(dismisses(travel: CGSize(width: 0, height: 80), predicted: CGSize(width: 0, height: 600)))
    }

    @Test("a short slow drag springs back")
    func shortSlowDragSpringsBack() {
        #expect(!dismisses(travel: CGSize(width: 0, height: 60), predicted: CGSize(width: 0, height: 60)))
    }

    @Test("a fast brush shorter than the minimum travel doesn't dismiss, however far it projects")
    func brushDoesNotDismiss() {
        let travel = CGSize(width: 0, height: RideDashboardView.dismissMinimumTravel - 1)
        #expect(!dismisses(travel: travel, predicted: CGSize(width: 0, height: 900)))
    }

    @Test("a diagonal fling that is more sideways than down doesn't dismiss")
    func diagonalDoesNotDismiss() {
        #expect(!dismisses(travel: CGSize(width: 90, height: 60), predicted: CGSize(width: 400, height: 300)))
    }

    @Test("an upward drag doesn't dismiss")
    func upwardDoesNotDismiss() {
        #expect(!dismisses(travel: CGSize(width: 0, height: -80), predicted: CGSize(width: 0, height: -400)))
    }

    @Test("the thresholds are the edges: exactly the travel counts, exactly the distance doesn't")
    func thresholdEdges() {
        let travel = CGSize(width: 0, height: RideDashboardView.dismissMinimumTravel)
        let past = CGSize(width: 0, height: RideDashboardView.dismissDistance + 1)
        let at = CGSize(width: 0, height: RideDashboardView.dismissDistance)
        #expect(dismisses(travel: travel, predicted: past))
        #expect(!dismisses(travel: travel, predicted: at))
    }
}
