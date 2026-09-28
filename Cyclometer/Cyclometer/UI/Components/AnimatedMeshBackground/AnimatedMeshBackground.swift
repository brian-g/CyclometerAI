import SwiftUI

/// Subtle, slow-drifting mesh gradient behind onboarding's Welcome and Add Sensors
/// screens (#328). Callers gate this on `colorSchemeContrast` themselves — this view
/// only owns the motion, stopping in place rather than animating when Reduce Motion
/// is on (`accessibilityReduceMotion`), so a still frame is always available instead
/// of nothing rendering.
struct AnimatedMeshBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            MeshGradient(width: 3, height: 3, points: Self.points(phase: 0), colors: Self.colors)
        } else {
            TimelineView(.animation) { context in
                MeshGradient(
                    width: 3, height: 3,
                    points: Self.points(phase: context.date.timeIntervalSinceReferenceDate),
                    colors: Self.colors
                )
            }
        }
    }

    // The tint sits in the lower-trailing corner rather than the center, so it reads
    // as a corner glow instead of a blob sitting in the middle of the screen.
    private static let colors: [Color] = [
        .cyPrimaryLight, .cyBgPrimary, .cyBgPrimary,
        .cyBgPrimary, .cyBgPrimary, .cyPrimaryLight.opacity(0.3),
        .cyBgPrimary, .cyPrimaryLight.opacity(0.45), .cyPrimaryMuted.opacity(0.3)
    ]

    /// Corners stay pinned; edges and the center drift a few percent of the frame
    /// along slow, mismatched sine periods so the mesh never repeats a pose.
    private static func points(phase: TimeInterval) -> [SIMD2<Float>] {
        func drift(_ base: SIMD2<Float>, speed: Double, amplitude: Float) -> SIMD2<Float> {
            SIMD2(
                base.x + amplitude * Float(sin(phase * speed)),
                base.y + amplitude * Float(cos(phase * speed * 0.8))
            )
        }
        return [
            .init(0, 0), drift(.init(0.5, 0), speed: 0.15, amplitude: 0.08), .init(1, 0),
            drift(.init(0, 0.5), speed: 0.12, amplitude: 0.08),
            drift(.init(0.5, 0.5), speed: 0.1, amplitude: 0.1),
            drift(.init(1, 0.5), speed: 0.13, amplitude: 0.08),
            .init(0, 1), drift(.init(0.5, 1), speed: 0.14, amplitude: 0.08), .init(1, 1)
        ]
    }
}

#Preview("Animated") {
    AnimatedMeshBackground().ignoresSafeArea()
}
