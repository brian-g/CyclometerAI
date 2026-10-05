import SwiftUI

/// UX.md's "Sheet: Ride metrics", shared by W1 Speed, W2 Avg Speed, W3 Duration and W6 Distance.
/// A placeholder until #144 builds the real sheet — one place for it to replace.
struct RideMetricsSheet: View {
    var body: some View {
        Text("Ride Metrics")
            .font(.headline)
            .presentationDetents([.medium])
    }
}
