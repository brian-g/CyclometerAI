import Testing
import SwiftUI
import UIKit
@testable import Cyclometer

/// #361 — every widget whose tap opens a detail sheet is one VoiceOver button, reading its title and
/// what the card shows, and a double-tap opens the sheet a tap does.
///
/// Serialized: each element test owns the key window and the process-wide automation switch, and
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
        #expect(live(.oneByOne).accessibilityValue == "36.0 km/h")
        #expect(live(.twoByOne).accessibilityValue == "36.0 km/h, average 28.8, maximum 43.2")
        #expect(
            live(.twoByTwo).accessibilityValue
                == "36.0 km/h, average 28.8, maximum 43.2, distance 12.4 km, time 1 hour, 2 minutes, 33 seconds"
        )
    }

    @Test func speedNeverReadsADash() {
        let noFix = SpeedWidget(
            speed: nil, speedHistory: [], activeSpeedSource: .none,
            distance: 0, elapsed: 0, averageSpeed: 0, maxSpeed: 0, size: .oneByOne
        )
        #expect(noFix.accessibilityValue == "No reading")
    }

    @Test func directionsReadsItsThreeStates() {
        let withTurn = DirectionsWidget(hasRoute: true, nextTurn: turn, distanceMeters: 347, unit: .metric)
        let noTurn = DirectionsWidget(hasRoute: true, nextTurn: nil, distanceMeters: nil, unit: .metric)
        let noRoute = DirectionsWidget(hasRoute: false, nextTurn: nil, distanceMeters: nil, unit: .metric)
        #expect(withTurn.accessibilityValue == "Turn right onto County Road S in 350 m")
        #expect(noTurn.accessibilityValue == "No turn ahead")
        #expect(noRoute.accessibilityValue == "No route")
    }

    // MARK: - Element shape and activation

    /// One element per widget, a button, labelled with its title.
    @Test(arguments: TappableWidget.allCases)
    func widgetIsOneButton(_ widget: TappableWidget) throws {
        let host = Host(widget.view)
        defer { host.tearDown() }

        let element = try #require(host.elements.only)
        #expect(element.accessibilityLabel == widget.title)
        #expect(element.isButton == true)
    }

    @Test(arguments: TappableWidget.allCases)
    func doubleTapOpensTheSheet(_ widget: TappableWidget) throws {
        let host = Host(widget.view)
        defer { host.tearDown() }

        let element = try #require(host.elements.only)
        #expect(element.accessibilityActivate())
        host.settle()
        #expect(host.controller.presentedViewController != nil)
    }

    /// S07: a tap does nothing while editing, so the widget isn't a button and a double-tap opens nothing.
    @Test(arguments: TappableWidget.allCases)
    func editModeIsNotAButton(_ widget: TappableWidget) throws {
        let host = Host(widget.view.environment(\.isEditingDashboard, true))
        defer { host.tearDown() }

        let element = try #require(host.elements.only)
        #expect(element.isButton == false)
        _ = element.accessibilityActivate()
        host.settle()
        #expect(host.controller.presentedViewController == nil)
    }
}

/// The widgets that adopt `.widgetDetail`.
enum TappableWidget: CaseIterable, CustomTestStringConvertible {
    case map, cadence, speed, directions

    var testDescription: String { title }

    var title: String {
        switch self {
        case .map: "Map"
        case .cadence: "Cadence"
        case .speed: "Speed"
        case .directions: "Directions"
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
        case .directions:
            AnyView(DirectionsWidget(hasRoute: false, nextTurn: nil, distanceMeters: nil, unit: .metric))
        }
    }
}

/// A widget in a key window, so its accessibility tree is built and its sheet can present.
///
/// SwiftUI builds no accessibility tree until an assistive technology asks for one, so in a plain
/// unit test every widget has zero elements. `AccessibilityAutomation` turns on the switch that
/// VoiceOver and XCUITest flip, for the life of the host only.
@MainActor
private final class Host {
    let window: UIWindow
    let controller: UIHostingController<AnyView>

    init<V: View>(_ view: V) {
        AccessibilityAutomation.isEnabled = true
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 400)
        controller = UIHostingController(rootView: AnyView(view.frame(width: 393, height: 200)))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        settle()
    }

    /// Every accessibility element under the hosting view.
    var elements: [NSObject] { Self.elements(in: controller.view) }

    /// Lets layout, the accessibility tree and any presentation catch up.
    func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    func tearDown() {
        controller.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        AccessibilityAutomation.isEnabled = false
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

/// libAccessibility's automation switch, private API, used by tests only. If a future iOS drops the
/// symbol, setting it does nothing, the tree stays empty, and every element test fails at
/// `#require(host.elements.only)`. That is loud, not silently green.
@MainActor
private enum AccessibilityAutomation {
    private typealias SetEnabled = @convention(c) (Int32) -> Void

    private static let setEnabled: SetEnabled? = {
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSSetAutomationEnabled") else { return nil }
        return unsafeBitCast(symbol, to: SetEnabled.self)
    }()

    static var isEnabled = false {
        didSet { setEnabled?(isEnabled ? 1 : 0) }
    }
}

private extension NSObject {
    /// Through a plain `Bool`: `#expect(!element.accessibilityTraits.contains(.button))` failed while
    /// its own expansion showed `contains → false`, so the macro's reading of the traits can't be trusted.
    var isButton: Bool { accessibilityTraits.contains(.button) }
}

private extension Array {
    /// The sole element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
