import ComposableArchitecture
import SwiftUI
import UIKit

/// Finish slides the dashboard down off the screen rather than zooming it back into the
/// accessory (#365), which goes away with the ride.
///
/// A zoom dismissal with nothing to zoom into scales the root view while it runs, and the tab
/// bar controller works out its safe-area insets from that scaled frame and never again: the
/// Rides title sits under the status bar until the app is backgrounded. Cover-vertical scales
/// nothing. The zoom stays for opening the dashboard and for dragging it back down.
///
/// SwiftUI can't switch `.navigationTransition` on a cover that's already up without rebuilding
/// its content, which also closes the Finish alert. So this sets the presented controller's
/// transition in UIKit, which reads it when the cover is dismissed.
struct DashboardFinishTransition: View {
    let store: StoreOf<ActiveRideFeature>

    var body: some View {
        // Read here, not in the cover's content closure. Re-running that closure re-applies
        // `.navigationTransition`, and SwiftUI puts a fresh zoom back on the cover.
        CoverTransition(isFinishing: store.finishAlert != nil || store.recordingState == .ended)
    }
}

private struct CoverTransition: UIViewRepresentable {
    /// From the Finish alert on. Cancel turns it off again, and the zoom comes back.
    let isFinishing: Bool

    func makeUIView(context: Context) -> CoverView {
        let view = CoverView()
        // Takes no touches, as `AutoDimWindowBridge.WindowProbe`.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: CoverView, context: Context) {
        view.isFinishing = isFinishing
    }

    final class CoverView: UIView {
        var isFinishing = false {
            didSet { apply() }
        }
        private let slideDown = UIViewController.Transition.coverVertical
        /// The cover's own zoom, kept while the slide stands in for it.
        private var zoom: UIViewController.Transition?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // An auto-end raises the Finish alert with the dashboard minimized, so it can be up
            // as the cover opens. SwiftUI sets the cover's transition while it opens, so the
            // slide goes in once the opening is done. A coordinator that can't queue the
            // completion never calls it, so that case applies now.
            let isQueued = cover?.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                self?.apply()
            } ?? false
            if !isQueued { apply() }
        }

        private func apply() {
            guard let cover else { return }
            if isFinishing {
                guard cover.preferredTransition !== slideDown else { return }
                zoom = cover.preferredTransition
                cover.preferredTransition = slideDown
            } else if let zoom {
                cover.preferredTransition = zoom
                self.zoom = nil
            }
        }

        /// The controller the dashboard is presented in.
        private var cover: UIViewController? {
            var responder = next
            while let current = responder, !(current is UIViewController) {
                responder = current.next
            }
            guard var controller = responder as? UIViewController else { return nil }
            while let parent = controller.parent { controller = parent }
            return controller.presentingViewController == nil ? nil : controller
        }
    }
}
