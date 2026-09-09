import SwiftUI

/// The button itself, so a screen with toolbar items of its own can place it among them.
/// Items in separate `.toolbar` modifiers sort by ancestry — the outermost lands leftmost,
/// wherever it sits in the chain — while items inside one modifier keep their written order.
/// Routes wants Start Ride *last*, so it declares this alongside its own items (S19, #193).
struct StartRideButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Start ride", systemImage: "play.fill")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .foregroundStyle(Color.cyPrimary)
        .accessibilityLabel("Start ride")
    }
}

extension View {
    /// Adds the global `play.fill` "Start ride" toolbar button. Any tab opts in with one line.
    /// Hidden while a ride is active.
    func startRideToolbarItem(isHidden: Bool, action: @escaping () -> Void) -> some View {
        toolbar {
            if !isHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    StartRideButton(action: action)
                }
            }
        }
    }
}

#Preview("Start Ride Toolbar") {
    NavigationStack {
        Text("Rides")
            .navigationTitle("Rides")
            .startRideToolbarItem(isHidden: false) {}
    }
}

#Preview("Start Ride Toolbar — hidden") {
    NavigationStack {
        Text("Rides")
            .navigationTitle("Rides")
            .startRideToolbarItem(isHidden: true) {}
    }
}
