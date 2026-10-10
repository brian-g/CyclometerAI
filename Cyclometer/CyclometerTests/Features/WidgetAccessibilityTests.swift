import Testing
import SwiftUI
import UIKit
@testable import Cyclometer

/// #361 — every widget whose tap opens a detail sheet is one VoiceOver button, reading its title and
/// what the card shows, and a double-tap opens the sheet a tap does.
///
/// Serialized: each element test owns a window and holds the process-wide automation switch, and
/// `Host.settle()` spins the main run loop, where a parallel test would otherwise run in between.
@MainActor
@Suite(.serialized)
struct WidgetAccessibilityTests {

    private let turn = Maneuver(
        coordinate: RouteCoordinate(latitude: 0, longitude: 0, elevationMeters: nil),
        direction: .right,
        name: "Turn right onto County Road S",
        distanceAlongRouteMeters: 1_000
    )

    // MARK: - Spoken text

    @Test func cadenceReadsWhatEachSizeShows() {
        let live = { (size: WidgetSize) in
            CadenceWidget(cadence: 92, cadenceHistory: [], averageCadence: 88, maxCadence: 110, size: size)
        }
        #expect(live(.oneByOne).accessibilityValue == "92 rpm")
        #expect(live(.twoByOne).accessibilityValue == "92 rpm, average 88, maximum 110")
    }

    @Test func cadenceNeverReadsADash() {
        let unpaired = CadenceWidget(cadence: nil, cadenceHistory: [], averageCadence: 0, maxCadence: 0, size: .twoByOne)
        #expect(unpaired.accessibilityValue == "No reading")
    }

    @Test func speedReadsWhatEachSizeShows() {
        let live = { (size: WidgetSize) in
            SpeedWidget(
                speed: 10, speedHistory: [], activeSpeedSource: .gps,
                distance: 12_400, elapsed: 3_753, averageSpeed: 8, maxSpeed: 12,
                unit: .metric, size: size
            )
        }
        #expect(live(.oneByOne).accessibilityValue == "36.0 kilometers per hour")
        #expect(live(.twoByOne).accessibilityValue == "36.0 kilometers per hour, average 28.8, maximum 43.2")
        #expect(
            live(.twoByTwo).accessibilityValue
                == "36.0 kilometers per hour, average 28.8, maximum 43.2, distance 12.4 kilometers, time 1 hour, 2 minutes, 33 seconds"
        )
    }

    @Test func speedNeverReadsADash() {
        let noFix = SpeedWidget(
            speed: nil, speedHistory: [], activeSpeedSource: .none,
            distance: 0, elapsed: 0, averageSpeed: 0, maxSpeed: 0, size: .oneByOne
        )
        #expect(noFix.accessibilityValue == "No reading")
    }

    @Test func paceReadsMinutesAndSeconds() {
        #expect(PaceWidget(speedMPS: 3, unit: .metric).accessibilityValue == "5 minutes, 33 seconds per kilometer")
        #expect(PaceWidget(speedMPS: 3, unit: .imperial).accessibilityValue == "8 minutes, 56 seconds per mile")
    }

    @Test func paceNeverReadsADash() {
        #expect(PaceWidget(speedMPS: 0, unit: .metric).accessibilityValue == "No reading")
    }

    @Test func directionsReadsItsThreeStates() {
        let withTurn = DirectionsWidget(hasRoute: true, nextTurn: turn, distanceMeters: 347, unit: .metric)
        let noTurn = DirectionsWidget(hasRoute: true, nextTurn: nil, distanceMeters: nil, unit: .metric)
        let noRoute = DirectionsWidget(hasRoute: false, nextTurn: nil, distanceMeters: nil, unit: .metric)
        #expect(withTurn.accessibilityValue == "Turn right onto County Road S in 350 meters")
        #expect(noTurn.accessibilityValue == "No turn ahead")
        #expect(noRoute.accessibilityValue == "No route")
    }

    @Test func heartRateReadsItsThreeStates() {
        #expect(HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap).accessibilityValue
            == "156 beats per minute, zone 3")
        #expect(HeartRateWidget(bpm: 0, zone: 0, source: .bleStrap).accessibilityValue == "No reading")
        #expect(HeartRateWidget(bpm: 0, zone: 0, source: .none).accessibilityValue == "No HR source")
    }

    @Test func heartRateReadsTrendAndTwoByOneStats() {
        let rising = HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap, trend: .up,
                                     averageBPM: 148, maxBPM: 171, size: .twoByOne)
        #expect(rising.accessibilityValue == "156 beats per minute, zone 3, rising, average 148, maximum 171")
        let falling = HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap, trend: .down, averageBPM: 148)
        #expect(falling.accessibilityValue == "156 beats per minute, zone 3, falling")
    }

    /// Time recorded before a dropout is still read; only a ride with no source and no time is empty.
    @Test func hrZonesReadsTimeInZone() {
        let live = HRZonesWidget(zone: 3, source: .bleStrap, zoneSeconds: [0, 125, 60, 0, 0])
        #expect(live.accessibilityValue == "Zone 3; zone 2 2 minutes, 5 seconds; zone 3 1 minute")
        let dropped = HRZonesWidget(zone: 0, source: .none, zoneSeconds: [0, 125, 0, 0, 0])
        #expect(dropped.accessibilityValue == "No reading; zone 2 2 minutes, 5 seconds")
    }

    @Test func hrZonesReadsItsThreeStates() {
        #expect(HRZonesWidget(zone: 3, source: .healthKit).accessibilityValue == "Zone 3")
        #expect(HRZonesWidget(zone: 0, source: .bleStrap).accessibilityValue == "No reading")
        #expect(HRZonesWidget(zone: 0, source: .none).accessibilityValue == "No HR source")
    }

    @Test func elevationReadsInWordsWithNoDash() {
        #expect(ElevationTotalWidget(title: "Ascent", meters: 412, unit: .imperial).accessibilityValue == "1,352 feet")
        #expect(GradeWidget(percent: 4.4).accessibilityValue == "4 percent")
        #expect(GradeWidget(percent: nil).accessibilityValue == "No reading")
        #expect(ElevationWidget(altitude: nil, gradePercent: nil, history: [], unit: .metric).accessibilityValue
            == "No reading")
        #expect(ElevationWidget(altitude: 284, gradePercent: nil, history: [], unit: .metric).accessibilityValue
            == "284 meters")
    }

    // MARK: - Element shape and activation

    /// Map's run in `MapWidgetAccessibilityTests`, which CI skips.
    @Test(arguments: TappableWidget.withoutMap)
    func widgetIsOneButton(_ widget: TappableWidget) throws {
        try ElementChecks.isOneButton(widget)
    }

    @Test(arguments: TappableWidget.withoutMap)
    func doubleTapOpensTheSheet(_ widget: TappableWidget) throws {
        try ElementChecks.doubleTapOpensTheSheet(widget)
    }

    @Test(arguments: TappableWidget.withoutMap)
    func editModeIsNotAButton(_ widget: TappableWidget) throws {
        try ElementChecks.editModeIsNotAButton(widget)
    }

    /// #144: the open Ride Metrics sheet follows the ride by itself, not only when the card that
    /// opened it redraws. W3's card here never changes, as while stopped. With the metrics read in
    /// the `.sheet` builder this failed about one fresh run in seven: the builder re-ran with the
    /// new value, but the open sheet kept the old one. Checked on the top row:
    /// rows below the medium detent aren't in the accessibility tree.
    @Test func rideMetricsSheetFollowsTheRideWhileOpen() throws {
        let ride = LiveRide()
        let host = try Host(DurationWidget(movingSeconds: 0, metrics: { ride.metrics }))
        defer { host.tearDown() }

        #expect(try host.onlyElement().accessibilityActivate())
        host.settle()
        #expect(host.presentedText().contains("Current No reading"))

        ride.metrics.speedMPS = 10
        host.settle { host.presentedText().contains("36.0 kilometers per hour") }
        #expect(host.presentedText().contains("Current 36.0 kilometers per hour"))
    }

    /// #145: the same for the Heart Rate sheet, opened from W12, whose card here never changes.
    @Test func heartRateSheetFollowsTheRideWhileOpen() throws {
        let ride = LiveRide()
        let host = try Host(HRZonesWidget(zone: 0, source: .none, metrics: { ride.heartRate }))
        defer { host.tearDown() }

        #expect(try host.onlyElement().accessibilityActivate())
        host.settle()
        #expect(host.presentedText().contains("Heart Rate No HR source"))

        ride.heartRate = .sample
        host.settle { host.presentedText().contains("156 beats per minute") }
        #expect(host.presentedText().contains("Heart Rate 156 beats per minute"))
    }
}

/// The element checks for W8 Map, apart so CI can skip them, as it does every suite that renders a
/// live map (`.github/workflows/tests.yml`). On the CI runner the first `Host` holding a `MapWidget`
/// never returned, and the job hit its 30-minute timeout; locally the suite passes.
@MainActor
@Suite(.serialized)
struct MapWidgetAccessibilityTests {
    @Test func mapIsOneButton() throws { try ElementChecks.isOneButton(.map) }
    @Test func mapDoubleTapOpensTheSheet() throws { try ElementChecks.doubleTapOpensTheSheet(.map) }
    @Test func mapInEditModeIsNotAButton() throws { try ElementChecks.editModeIsNotAButton(.map) }
}

/// One widget's VoiceOver element, checked in a `Host`.
@MainActor
private enum ElementChecks {
    /// One element per widget, a button, labelled with its title and carrying its spoken value.
    static func isOneButton(_ widget: TappableWidget) throws {
        let host = try Host(widget.view)
        defer { host.tearDown() }

        let element = try host.onlyElement()
        #expect(element.accessibilityLabel == widget.title)
        #expect((element.accessibilityValue ?? "") == widget.value)
        #expect(element.isButton == true)
    }

    static func doubleTapOpensTheSheet(_ widget: TappableWidget) throws {
        let host = try Host(widget.view)
        defer { host.tearDown() }

        let element = try host.onlyElement()
        #expect(element.accessibilityActivate())
        host.settle()
        #expect(host.controller.presentedViewController != nil)
    }

    /// S07: a tap does nothing while editing, so the widget isn't a button and a double-tap opens nothing.
    static func editModeIsNotAButton(_ widget: TappableWidget) throws {
        let host = try Host(widget.view.environment(\.isEditingDashboard, true))
        defer { host.tearDown() }

        let element = try host.onlyElement()
        #expect(element.isButton == false)
        _ = element.accessibilityActivate()
        host.settle()
        #expect(host.controller.presentedViewController == nil)
    }
}

/// Ride state as the store holds it: observable, read through a widget's `metrics` closure.
@Observable
private final class LiveRide {
    var metrics = RideMetrics()
    var heartRate = HeartRateMetrics()
}

/// The widgets that adopt `.widgetDetail`.
enum TappableWidget: CaseIterable, CustomTestStringConvertible {
    case map, cadence, speed, averageSpeed, duration, distance, pace, directions, heartRate, hrZones
    case ascent, descent, grade, elevation, routeElevation, routeElevationWithoutRoute

    var testDescription: String { title }

    /// Every widget but the live map, which CI can't render (see `MapWidgetAccessibilityTests`).
    static let withoutMap = allCases.filter { $0 != .map }

    var title: String {
        switch self {
        case .map: "Map"
        case .cadence: "Cadence"
        case .speed: "Speed"
        case .averageSpeed: "Average Speed"
        case .duration: "Duration"
        case .distance: "Distance"
        case .pace: "Pace"
        case .directions: "Directions"
        case .heartRate: "Heart Rate"
        case .hrZones: "HR Zones"
        case .ascent: "Ascent"
        case .descent: "Descent"
        case .grade: "Grade"
        case .elevation: "Elevation"
        case .routeElevation, .routeElevationWithoutRoute: "Route Elevation"
        }
    }

    /// What `view` reads after its title.
    var value: String {
        switch self {
        case .map: ""
        case .cadence: "92 rpm, average 88, maximum 110"
        case .speed: "36.0 kilometers per hour, average 28.8, maximum 43.2, distance 12.4 kilometers, time 1 hour, 2 minutes, 33 seconds"
        case .averageSpeed: "28.8 kilometers per hour"
        case .duration: "1 hour, 2 minutes, 33 seconds"
        case .distance: "12.4 kilometers"
        case .pace: "5 minutes, 33 seconds per kilometer"
        case .directions: "No route"
        case .heartRate: "156 beats per minute, zone 3"
        case .hrZones: "Zone 3"
        case .ascent: "412 meters"
        case .descent: "368 meters"
        case .grade: "-3 percent"
        case .elevation: "284 meters, grade 4 percent"
        case .routeElevation, .routeElevationWithoutRoute: "284 meters, grade 4 percent"
        }
    }

    @MainActor
    var view: AnyView {
        switch self {
        case .map:
            AnyView(MapWidget(trackSegments: [[]]))
        case .cadence:
            AnyView(CadenceWidget(cadence: 92, cadenceHistory: [], averageCadence: 88, maxCadence: 110))
        case .speed:
            AnyView(SpeedWidget(
                speed: 10, speedHistory: [], activeSpeedSource: .gps,
                distance: 12_400, elapsed: 3_753, averageSpeed: 8, maxSpeed: 12
            ))
        case .averageSpeed:
            AnyView(AverageSpeedWidget(averageSpeed: 8, speedHistory: [], averageHistory: []))
        case .duration:
            AnyView(DurationWidget(movingSeconds: 3_753))
        case .distance:
            AnyView(DistanceWidget(distance: 12_400, unit: .metric))
        case .pace:
            AnyView(PaceWidget(speedMPS: 3, unit: .metric))
        case .directions:
            AnyView(DirectionsWidget(hasRoute: false, nextTurn: nil, distanceMeters: nil, unit: .metric))
        case .heartRate:
            AnyView(HeartRateWidget(bpm: 156, zone: 3, source: .bleStrap))
        case .hrZones:
            AnyView(HRZonesWidget(zone: 3, source: .bleStrap))
        case .ascent:
            AnyView(ElevationTotalWidget(title: "Ascent", meters: 412, unit: .metric))
        case .descent:
            AnyView(ElevationTotalWidget(title: "Descent", meters: 368, unit: .metric))
        case .grade:
            AnyView(GradeWidget(percent: -3.2))
        case .elevation:
            AnyView(ElevationWidget(altitude: 284, gradePercent: 4.4, history: [], unit: .metric))
        case .routeElevation:
            AnyView(RouteElevationWidget(
                altitude: 284, gradePercent: 4.4, routeProfile: [250, 300, 260], routeProgress: 0.5,
                history: [], unit: .metric
            ))
        case .routeElevationWithoutRoute:
            // W17's face, still named for W18.
            AnyView(RouteElevationWidget(
                altitude: 284, gradePercent: 4.4, routeProfile: nil, routeProgress: nil, history: [], unit: .metric
            ))
        }
    }
}

/// A widget in a visible window, so its accessibility tree is built and its sheet can present.
///
/// SwiftUI builds no accessibility tree until an assistive technology asks for one, so in a plain
/// unit test every widget has zero elements. `AccessibilityAutomation` turns on the switch that
/// VoiceOver and XCUITest flip, for the life of the host only.
///
/// The window is shown but never made key: `settle()` spins the main run loop, where other suites'
/// tests run, and key-window snapshot tests (`drawHierarchyInKeyWindow`) must not find this one.
@MainActor
private final class Host {
    let window: UIWindow
    let controller: UIHostingController<AnyView>

    init<V: View>(_ view: V) throws {
        try #require(AccessibilityAutomation.isAvailable, AccessibilityAutomation.missingSymbol)
        AccessibilityAutomation.acquire()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 400)
        controller = UIHostingController(rootView: AnyView(view.frame(width: 393, height: 200)))
        window.rootViewController = controller
        window.isHidden = false
        settle()
    }

    /// The widget's one accessibility element. No elements at all is the signature of the automation
    /// switch no longer working, so that failure names it rather than reading as a widget bug.
    func onlyElement() throws -> NSObject {
        let elements = Self.elements(in: controller.view)
        try #require(!elements.isEmpty, AccessibilityAutomation.emptyTree)
        try #require(elements.count == 1, "\(elements.count) accessibility elements; a tappable widget must be one")
        return elements[0]
    }

    /// Every label and value in the presented sheet, joined.
    func presentedText() -> String {
        guard let sheet = controller.presentedViewController else { return "" }
        return Self.elements(in: sheet.view)
            .map { "\($0.accessibilityLabel ?? "") \($0.accessibilityValue ?? "")" }
            .joined(separator: "\n")
    }

    /// Lets layout, the accessibility tree and any presentation catch up.
    func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    /// Settles until `condition` holds, or `limit` passes. Under a loaded run an update can reach
    /// the accessibility tree after `settle()`'s fixed half second.
    func settle(limit: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: limit)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }

    func tearDown() {
        controller.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        AccessibilityAutomation.release()
    }

    private static func elements(in node: NSObject) -> [NSObject] {
        if node.isAccessibilityElement { return [node] }
        let children: [NSObject]
        if let listed = node.accessibilityElements as? [NSObject] {
            children = listed
        } else {
            let count = node.accessibilityElementCount()
            children = count == NSNotFound || count == 0
                ? ((node as? UIView)?.subviews ?? [])
                : (0..<count).compactMap { node.accessibilityElement(at: $0) as? NSObject }
        }
        return children.flatMap { elements(in: $0) }
    }
}

/// libAccessibility's automation switch, `_AXSSetAutomationEnabled(Int32)`. **Private Apple API,
/// test target only, never linked into the app.** It is the switch VoiceOver and XCUITest turn on;
/// with it on, SwiftUI builds its accessibility tree in-process, and `accessibilityActivate()` runs a
/// view's default action exactly as a VoiceOver double-tap does. Added in #361 (iOS 27, Xcode 27) and
/// kept deliberately over an XCUITest, which can't perform a VoiceOver activation.
///
/// When an iOS release breaks it, the element tests fail in one of two ways, each naming this type:
/// - The symbol is gone: `Host.init` fails with `missingSymbol`.
/// - The symbol is there but no longer builds SwiftUI's tree: every widget has zero elements, and
///   `Host.onlyElement()` fails with `emptyTree`.
///
/// Then: look for a renamed symbol (`nm -gU` on the simulator runtime's `libAccessibility.dylib`),
/// or move the element checks to `CyclometerUITests` (`app.buttons["Cadence"]` and its `value`). That
/// keeps label/value/trait coverage but loses activation, which then needs a VoiceOver check on a device.
/// The spoken-text tests above don't use the switch and keep running either way.
@MainActor
private enum AccessibilityAutomation {
    private typealias SetEnabled = @convention(c) (Int32) -> Void

    private static let symbolName = "_AXSSetAutomationEnabled"

    private static let setEnabled: SetEnabled? = {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, symbolName) else { return nil }
        return unsafeBitCast(symbol, to: SetEnabled.self)
    }()

    static var isAvailable: Bool { setEnabled != nil }

    /// Hosts alive now. Counted rather than a flag, so one host's teardown can't switch automation
    /// off under another.
    private static var holders = 0

    static func acquire() {
        holders += 1
        if holders == 1 { setEnabled?(1) }
    }

    static func release() {
        holders -= 1
        if holders == 0 { setEnabled?(0) }
    }

    static let missingSymbol: Comment = """
        Private API \(symbolName) not found in libAccessibility.dylib. This iOS dropped or renamed it; \
        see AccessibilityAutomation in WidgetAccessibilityTests.swift.
        """

    static let emptyTree: Comment = """
        No accessibility elements at all. Either the widget exposes none, or the private \
        \(symbolName) switch no longer makes SwiftUI build its tree on this iOS; see \
        AccessibilityAutomation in WidgetAccessibilityTests.swift.
        """
}

private extension NSObject {
    /// Through a plain `Bool`: `#expect(!element.accessibilityTraits.contains(.button))` failed while
    /// its own expansion showed `contains → false`, so the macro's reading of the traits can't be trusted.
    var isButton: Bool { accessibilityTraits.contains(.button) }
}
