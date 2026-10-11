import SwiftUI
import WidgetKit

/// The extension holds one thing: the ride's Live Activity (PRD §8.10). No Home Screen widgets,
/// no controls.
@main
struct CyclometerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}
