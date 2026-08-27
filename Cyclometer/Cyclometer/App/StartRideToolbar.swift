import SwiftUI

extension View {
    /// Adds the global `play.fill` "Start ride" toolbar button. Any tab opts in with one line.
    /// Hidden while a ride is active.
    func startRideToolbarItem(isHidden: Bool, action: @escaping () -> Void) -> some View {
        toolbar {
            if !isHidden {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: action) {
                        Label("Start ride", systemImage: "play.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .foregroundStyle(Color.cyPrimary)
                    .accessibilityLabel("Start ride")
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
