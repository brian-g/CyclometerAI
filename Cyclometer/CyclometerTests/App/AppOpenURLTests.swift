import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// "Open in Cyclometer" on a `.gpx` from Files, Mail or Safari, which `CFBundleDocumentTypes`
/// advertises and `AppView.onOpenURL` hands to the reducer.
///
/// The import itself is `RoutesFeatureTests`' business — what matters here is that the file
/// reaches `.fileSelected` at all, and that the rider is looking at the list it lands in
/// rather than whatever tab they opened the file from.
@MainActor
@Suite("AppFeature — an opened file")
struct AppOpenURLTests {
    typealias ScanCall = StartSheetPresentationTests.ScanCall

    /// Never read: the parse fails, which is enough to prove the URL was forwarded without
    /// making this suite depend on the importer or the store.
    private static let opened = FileManager.default.temporaryDirectory
        .appending(component: "AppOpenURLTests.gpx")

    /// Settings tab, with a route detail pushed on the Routes stack — the two pieces of
    /// state the rider would have to undo by hand if the open didn't.
    private func makeStore() -> TestStoreOf<AppFeature> {
        StartSheetPresentationTests.makeStore(into: LockIsolated<[ScanCall]>([])) {
            var state = AppFeature.State()
            state.selectedTab = .settings
            state.routes.path.append(
                .detail(RouteDetailFeature.State(summary: RouteSummary.previewRoutes[0]))
            )
            return state
        }
    }

    @Test("Selects the Routes tab, pops to the list, and forwards the file")
    func forwardsToTheImporter() async {
        let store = makeStore()
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.fileOpened(Self.opened)) {
            $0.selectedTab = .routes
            $0.routes.path.removeAll()
        }
        await store.receive(\.routes.fileSelected, Self.opened)
        await store.finish()
    }

    /// The app registers no custom scheme, so a non-file URL is something it was handed by
    /// mistake — it must not select a tab or throw away the rider's place in the stack.
    @Test("Ignores a URL that isn't a file")
    func ignoresNonFileURLs() async {
        let store = makeStore()

        await store.send(.fileOpened(URL(string: "https://example.com/route.gpx")!))
        await store.finish()
    }
}
