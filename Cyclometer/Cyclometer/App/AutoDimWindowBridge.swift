import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Auto-dim's two window-level pieces (#110, #333). They sit on windows rather than on
/// the dashboard because the dashboard isn't the only thing on screen during a ride: it's
/// a presentation with sheets of its own (the map sheet, the Speed and Cadence details),
/// and a zoom dismiss drag that belongs to UIKit, not to any SwiftUI view.
///
/// - **Touch presence**: a recognizer on the app window reports the first finger down and
///   the last one up, so the countdown pauses under any touch, a drag included. A SwiftUI
///   `simultaneousGesture` can't do this: it is cancelled when the pager or the dismiss
///   drag takes the touch, and would report "ended" with the finger still down.
/// - **Blocker**: while dimmed, a window above the app takes every touch, so nothing below
///   sees one. Only a tap wakes the screen; a swipe, a drag or a long-press does nothing.
struct AutoDimWindowBridge: UIViewRepresentable {
    /// Whether touches are reported. Off while no dashboard is up, where the
    /// countdown isn't running and the reports would only be noise.
    let isTracking: Bool
    let isDimmed: Bool
    let onTouchBegan: () -> Void
    let onTouchEnded: () -> Void
    let onWake: () -> Void

    /// How far a wake tap may move and how long it may be held. Past either, it's a
    /// drag or a long-press (UIKit's own long-press starts at 0.5s), and does nothing.
    static let wakeTapMaxTravel: CGFloat = 10
    static let wakeTapMaxDuration: TimeInterval = 0.5

    /// Whether one finger's touch counts as the tap that wakes a dim.
    static func isWakeTap(translation: CGSize, duration: TimeInterval) -> Bool {
        hypot(translation.width, translation.height) <= wakeTapMaxTravel
            && duration < wakeTapMaxDuration
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowProbe {
        let probe = WindowProbe()
        probe.onWindow = { [coordinator = context.coordinator] window in
            coordinator.attach(to: window)
        }
        return probe
    }

    func updateUIView(_ uiView: WindowProbe, context: Context) {
        let coordinator = context.coordinator
        coordinator.touches.onBegan = onTouchBegan
        coordinator.touches.onEnded = onTouchEnded
        coordinator.touches.isEnabled = isTracking
        coordinator.onWake = onWake
        coordinator.isDimmed = isDimmed
    }

    static func dismantleUIView(_ uiView: WindowProbe, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        let touches = TouchPresenceRecognizer()
        var onWake: () -> Void = {}
        var isDimmed = false {
            didSet { if isDimmed != oldValue { applyDim() } }
        }
        private weak var window: UIWindow?
        private var blocker: UIWindow?

        func attach(to window: UIWindow) {
            guard self.window !== window else { return }
            self.window?.removeGestureRecognizer(touches)
            window.addGestureRecognizer(touches)
            self.window = window
            applyDim()
        }

        func detach() {
            window?.removeGestureRecognizer(touches)
            blocker?.isHidden = true
            blocker = nil
        }

        /// Shown with `isHidden`, not `makeKeyAndVisible`, so the app window keeps key status.
        private func applyDim() {
            if isDimmed, blocker == nil, let scene = window?.windowScene {
                let blocker = UIWindow(windowScene: scene)
                blocker.windowLevel = .normal + 1
                blocker.rootViewController = DimBlockerController { [weak self] in self?.onWake() }
                blocker.isHidden = false
                self.blocker = blocker
                // `accessibilityViewIsModal` doesn't reach across windows, so VoiceOver
                // focus is moved onto the blocker; left on a dashboard control, a
                // double-tap would activate it through the dim.
                UIAccessibility.post(notification: .screenChanged, argument: blocker.rootViewController?.view)
            } else if !isDimmed, let blocker {
                blocker.isHidden = true
                self.blocker = nil
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
    }

    /// Reports the window it lands in. Takes no touches itself.
    final class WindowProbe: UIView {
        var onWindow: (UIWindow) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

/// Sees every touch in its window without taking any. It never recognizes, can't be
/// prevented, and runs alongside everything, so the pager, the zoom's dismiss drag and
/// every button behave as if it weren't there.
final class TouchPresenceRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onBegan: () -> Void = {}
    var onEnded: () -> Void = {}
    private var fingers = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if fingers == 0 { onBegan() }
        fingers += touches.count
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        lift(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        lift(touches)
    }

    private func lift(_ touches: Set<UITouch>) {
        fingers = max(0, fingers - touches.count)
        guard fingers == 0 else { return }
        onEnded()
        state = .failed
    }

    /// Also reached when tracking is switched off mid-touch; the countdown must not be
    /// left believing a finger is still down.
    override func reset() {
        if fingers > 0 {
            fingers = 0
            onEnded()
        }
        super.reset()
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
}

/// The dim blocker's root. Clear, full-screen, and it swallows every touch; only a
/// one-finger tap (`AutoDimWindowBridge.isWakeTap`) wakes the screen.
private final class DimBlockerController: UIViewController {
    private let onWake: () -> Void

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = DimBlockerView(onWake: onWake)
    }
}

private final class DimBlockerView: UIView {
    private let onWake: () -> Void
    private var fingers = 0
    private var candidate: (touch: UITouch, point: CGPoint, time: TimeInterval)?

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = "Screen dimmed. Tap to wake."
        accessibilityTraits = .button
        accessibilityViewIsModal = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        fingers += touches.count
        // A second finger means it isn't a tap.
        if fingers == 1, let touch = touches.first {
            candidate = (touch, touch.location(in: self), touch.timestamp)
        } else {
            candidate = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        fingers = max(0, fingers - touches.count)
        guard let candidate, touches.contains(candidate.touch) else { return }
        self.candidate = nil
        let end = candidate.touch.location(in: self)
        let translation = CGSize(width: end.x - candidate.point.x, height: end.y - candidate.point.y)
        if AutoDimWindowBridge.isWakeTap(
            translation: translation,
            duration: candidate.touch.timestamp - candidate.time
        ) {
            onWake()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        fingers = max(0, fingers - touches.count)
        candidate = nil
    }

    override func accessibilityActivate() -> Bool {
        onWake()
        return true
    }
}
