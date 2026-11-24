import Testing
import Foundation
import ComposableArchitecture
@testable import Cyclometer

/// "Open in Cyclometer" on a `.gpx` from Files, Mail or Safari, which `CFBundleDocumentTypes`
/// advertises, and Strava's sign-in redirect through the `cyclometer` scheme (#626). Both arrive
/// through `AppView.onOpenURL`.
///
/// The import itself is `RoutesFeatureTests`' business — what matters here is that the file
/// reaches `.fileSelected` at all, and that the rider is looking at the list it lands in
/// rather than whatever tab they opened the file from.
@MainActor
@Suite("AppFeature — an opened URL")
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
                .route(RouteDetailFeature.State(summary: RouteSummary.previewRoutes[0]))
            )
            return state
        }
    }

    @Test("Selects the Routes tab, pops to the list, and forwards the file")
    func forwardsToTheImporter() async {
        let store = makeStore()
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.urlOpened(Self.opened)) {
            $0.selectedTab = .routes
            $0.routes.path.removeAll()
        }
        await store.receive(\.routes.fileSelected, Self.opened)
        await store.finish()
    }

    /// Strava's redirect goes to the sign-in waiting for it, and nothing else moves: the rider
    /// is back on the screen where they tapped Connect.
    @Test("Hands Strava's redirect to the sign-in, leaving the tab and stack alone")
    func forwardsTheStravaRedirect() async {
        let handed = LockIsolated<[URL]>([])
        let store = makeStore()
        store.dependencies.stravaAuth.handleRedirect = { url in
            handed.withValue { $0.append(url) }
            return true
        }
        let redirect = URL(string: "cyclometer://acmeapps.xyz/strava?state=s&code=c&scope=read")!

        await store.send(.urlOpened(redirect))
        await store.finish()
        #expect(handed.value == [redirect])
    }

    /// A non-file URL that isn't Strava's redirect is something the app was handed by mistake:
    /// it must not select a tab or throw away the rider's place in the stack.
    @Test("Ignores a URL that is neither a file nor Strava's redirect")
    func ignoresOtherURLs() async {
        let store = makeStore()

        await store.send(.urlOpened(URL(string: "https://example.com/route.gpx")!))
        await store.finish()
    }
}
