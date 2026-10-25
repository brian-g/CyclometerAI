import UIKit

/// Works around a UIKit bug (#365). Dismissing the dashboard's zoom cover leaves the tab bar
/// controller with stale safe-area insets (top 24 pt, bottom 0, no margins) while the window
/// and the hosting controller above it are right. Nothing recomputes them until the scene next
/// changes state, so the Rides title sits under the status bar until the app is backgrounded.
///
/// While a ride is on, the bottom accessory hides this: the tab bar re-lays out around it and
/// recomputes them. After Finish there's no accessory, so they're recomputed here. Only an
/// `additionalSafeAreaInsets` change does it; `setNeedsLayout` on the controller or its host
/// doesn't.
@MainActor
enum TabBarSafeAreaRepair {
    static func repairIfStale() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows {
            guard let tabBarController = window.rootViewController.flatMap(tabBarController(in:)) else { continue }
            let view = tabBarController.view!
            guard view.safeAreaInsets != window.safeAreaInsets else { return }
            let additional = tabBarController.additionalSafeAreaInsets
            tabBarController.additionalSafeAreaInsets.top = additional.top + 1
            view.layoutIfNeeded()
            tabBarController.additionalSafeAreaInsets = additional
            view.layoutIfNeeded()
            return
        }
    }

    private static func tabBarController(in viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController { return tabBarController }
        return viewController.children.lazy.compactMap(tabBarController(in:)).first
    }
}
