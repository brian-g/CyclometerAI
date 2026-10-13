---
paths:
  - "Cyclometer/Cyclometer/**/*.swift"
  - "Cyclometer/CyclometerWidgets/**/*.swift"
---

**SwiftUI previews:**
- Every file that declares a non-private `View` has `#Preview`s at the bottom, under `// MARK: - Previews`. Add them when you create the view, and when you touch a file that lacks them.
- One preview per state the design calls out — e.g. empty / no reading, stale, paused, route vs no route, light and dark, metric and imperial, collapsed sizes. Name each after its state (`#Preview("Paused")`).
- Preview with sample data only: plain values, or a `Store` with an inline reducer state and `withDependencies` preview values. Never a live client, network, BLE or HealthKit.
- Private subviews are covered by their parent's previews; they don't need their own.
- States a canvas can't produce (a Live Activity's `isStale`, the Always-On display) go in a preview of the plain view with the environment or input set, and in a snapshot test.
- Previews don't replace snapshot tests (`testing.md`); they're for seeing a view's states while working on it.
