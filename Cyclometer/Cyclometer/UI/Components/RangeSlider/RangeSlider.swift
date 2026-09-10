import SwiftUI

/// A slider with two thumbs, or one when only an upper bound is being chosen.
///
/// SwiftUI ships no range slider, and S19's distance filter needs a minimum *and* a maximum.
/// Two stacked `Slider`s would have worked, but the elevation-gain row next to it takes only a
/// maximum, and a system `Slider` beside a hand-built one reads as two different controls. One
/// component in two modes keeps the sheet looking like a single system.
///
/// Everything a custom control loses and has to be given back is here: per-thumb accessibility
/// (a single combined element leaves VoiceOver unable to set a *range* at all), a hit target
/// that stays at 44pt while the visible thumb does not, drag handling that survives the two
/// thumbs meeting, and a layout that is mirrored under right-to-left rather than assuming
/// `translation.width` runs the way the numbers do.
///
/// It draws the track and the thumbs only. The value labels belong to the caller, which knows
/// the rider's units and can lay them out for Dynamic Type.
struct RangeSlider: View {

    @Binding private var lowerValue: Double
    @Binding private var upperValue: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    private let showsLowerThumb: Bool
    private let lowerLabel: String
    private let upperLabel: String
    private let format: (Double) -> String

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var activeThumb: Thumb?

    private enum Thumb { case lower, upper }

    private let trackHeight: CGFloat = 4
    private let thumbDiameter: CGFloat = 27
    /// The control's own height, which is also the minimum comfortable touch target. The
    /// visible thumb stays at 27pt inside it.
    private let controlHeight: CGFloat = 44

    /// Both ends adjustable — S19's distance filter.
    init(
        lowerValue: Binding<Double>,
        upperValue: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        lowerLabel: String,
        upperLabel: String,
        format: @escaping (Double) -> String
    ) {
        self._lowerValue = lowerValue
        self._upperValue = upperValue
        self.bounds = bounds
        self.step = step
        self.showsLowerThumb = true
        self.lowerLabel = lowerLabel
        self.upperLabel = upperLabel
        self.format = format
    }

    /// Upper bound only — S19's elevation-gain filter, where "at most this much climbing" is
    /// the whole question. The fixed end is still announced as a bound so VoiceOver does not
    /// imply the range is open below.
    init(
        upperValue: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        label: String,
        format: @escaping (Double) -> String
    ) {
        self._lowerValue = .constant(bounds.lowerBound)
        self._upperValue = upperValue
        self.bounds = bounds
        self.step = step
        self.showsLowerThumb = false
        self.lowerLabel = ""
        self.upperLabel = label
        self.format = format
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.cyBorder)
                    .frame(height: trackHeight)
                    .accessibilityHidden(true)

                Capsule()
                    .fill(Color.cyPrimary)
                    .frame(width: filledWidth(in: width), height: trackHeight)
                    .offset(x: filledOrigin(in: width))
                    .accessibilityHidden(true)

                if showsLowerThumb {
                    thumb(for: .lower, in: width)
                }
                thumb(for: .upper, in: width)
            }
            .frame(width: width, height: controlHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(in: width))
        }
        .frame(height: controlHeight)
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: lowerValue)
        .sensoryFeedback(.selection, trigger: upperValue)
    }

    // MARK: - Thumbs

    private func thumb(for thumb: Thumb, in width: CGFloat) -> some View {
        let value = thumb == .lower ? lowerValue : upperValue
        return Circle()
            .fill(.white)
            .shadow(color: .black.opacity(Opacity.thumbShadow), radius: 2, y: 1)
            .frame(width: thumbDiameter, height: thumbDiameter)
            // The visible thumb stays at the system's 27pt while the element that has to be
            // reachable — by a finger and by VoiceOver's focus rectangle — is the full 44pt.
            .frame(width: controlHeight, height: controlHeight)
            .contentShape(Circle())
            .offset(x: centeredOffset(for: value, in: width))
            .accessibilityElement()
            .accessibilityLabel(thumb == .lower ? lowerLabel : upperLabel)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { direction in
                adjust(thumb, by: direction == .increment ? step : -step)
            }
    }

    /// One step, bounded by the other thumb so an increment cannot walk the two past each
    /// other and invert the range.
    private func adjust(_ thumb: Thumb, by delta: Double) {
        switch thumb {
        case .lower:
            lowerValue = clamp(lowerValue + delta, upper: upperValue)
        case .upper:
            upperValue = clamp(upperValue + delta, lower: showsLowerThumb ? lowerValue : nil)
        }
    }

    // MARK: - Dragging

    private func dragGesture(in width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let target = value(atX: gesture.location.x, in: width)
                let thumb = activeThumb ?? nearestThumb(to: target, translation: gesture.translation.width)
                activeThumb = thumb
                switch thumb {
                case .lower: lowerValue = clamp(target, upper: upperValue)
                case .upper: upperValue = clamp(target, lower: showsLowerThumb ? lowerValue : nil)
                }
            }
            .onEnded { _ in activeThumb = nil }
    }

    /// Which thumb the drag grabbed.
    ///
    /// Nearest wins, but a range dragged fully closed leaves both thumbs on the same value and
    /// "nearest" can no longer separate them — so the tie is broken by which way the finger is
    /// moving. Without that rule a closed range can never be reopened, which is the same
    /// dead-end a zero-width domain produces.
    private func nearestThumb(to target: Double, translation: CGFloat) -> Thumb {
        guard showsLowerThumb else { return .upper }
        let lowerDistance = abs(target - lowerValue)
        let upperDistance = abs(target - upperValue)
        if lowerDistance < upperDistance { return .lower }
        if upperDistance < lowerDistance { return .upper }
        let forwards = layoutDirection == .rightToLeft ? translation < 0 : translation > 0
        return forwards ? .upper : .lower
    }

    // MARK: - Geometry

    private var span: Double {
        let span = bounds.upperBound - bounds.lowerBound
        // The domain guarantees at least one step of width (`RouteFilterDomain.bracket`), but a
        // zero here would divide into NaN, offset the thumb off-screen and trip a CoreGraphics
        // assertion rather than merely looking wrong.
        return span > 0 ? span : 1
    }

    private var usableWidthInset: CGFloat { thumbDiameter / 2 }

    private func fraction(for value: Double) -> Double {
        min(max((value - bounds.lowerBound) / span, 0), 1)
    }

    /// Leading-edge offset of the thumb's 44pt frame, mirrored under right-to-left.
    private func centeredOffset(for value: Double, in width: CGFloat) -> CGFloat {
        let usable = max(width - thumbDiameter, 1)
        let fraction = layoutDirection == .rightToLeft
            ? 1 - self.fraction(for: value)
            : self.fraction(for: value)
        return usableWidthInset + usable * fraction - controlHeight / 2
    }

    private func trackX(for value: Double, in width: CGFloat) -> CGFloat {
        let usable = max(width - thumbDiameter, 1)
        let fraction = layoutDirection == .rightToLeft
            ? 1 - self.fraction(for: value)
            : self.fraction(for: value)
        return usableWidthInset + usable * fraction
    }

    /// Where the filled part of the track starts. With two thumbs that is the lower one; with
    /// one it is the track's own leading edge, not the position the domain's minimum would
    /// occupy — that sits half a thumb in, and the sliver of unfilled track it leaves behind
    /// reads as a rendering fault rather than as "no minimum".
    private func filledAnchor(in width: CGFloat) -> CGFloat {
        guard showsLowerThumb else { return layoutDirection == .rightToLeft ? width : 0 }
        return trackX(for: lowerValue, in: width)
    }

    private func filledOrigin(in width: CGFloat) -> CGFloat {
        min(filledAnchor(in: width), trackX(for: upperValue, in: width))
    }

    private func filledWidth(in width: CGFloat) -> CGFloat {
        abs(trackX(for: upperValue, in: width) - filledAnchor(in: width))
    }

    /// The value under a touch. `translation.width` runs with the screen, not with the numbers,
    /// so the fraction is flipped rather than the gesture.
    private func value(atX x: CGFloat, in width: CGFloat) -> Double {
        let usable = max(width - thumbDiameter, 1)
        var fraction = Double((x - usableWidthInset) / usable)
        if layoutDirection == .rightToLeft { fraction = 1 - fraction }
        return snap(bounds.lowerBound + min(max(fraction, 0), 1) * span)
    }

    private func snap(_ value: Double) -> Double {
        guard step > 0 else { return clamp(value) }
        let snapped = (value / step).rounded() * step
        return clamp(snapped)
    }

    private func clamp(_ value: Double, lower: Double? = nil, upper: Double? = nil) -> Double {
        min(max(value, max(bounds.lowerBound, lower ?? bounds.lowerBound)),
            min(bounds.upperBound, upper ?? bounds.upperBound))
    }
}
