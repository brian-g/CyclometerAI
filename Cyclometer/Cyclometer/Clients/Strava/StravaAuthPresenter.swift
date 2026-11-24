import AuthenticationServices
import Foundation
import os
import UIKit

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.accounts)

/// Shows Strava's consent screen and returns the redirect it comes back with (PRD §8.12).
///
/// When `canOpenURL` accepts `strava://`, the Strava app handles sign-in, already signed in, and
/// sends the rider back through the `cyclometer` scheme: `AppFeature.urlOpened` hands that URL
/// to `handleRedirect`. Otherwise the web page opens in an `ASWebAuthenticationSession`, which
/// catches the redirect itself, so the rider never leaves the app.
///
/// Live-only glue: `StravaSession` takes it as a closure, and its tests script the redirect.
@MainActor
final class StravaAuthPresenter: NSObject {
    /// How long after the app becomes active again a redirect from the Strava app may still
    /// arrive. Coming back by the app switcher, without finishing sign-in, sends none, and
    /// without this wait the sign-in would never end. Whether the activation or the URL arrives
    /// first isn't documented, hence a window rather than an order.
    static let redirectGrace: Duration = .seconds(2)

    private var isAuthorizing = false
    private var pendingRedirect: CheckedContinuation<URL, any Error>?
    private var returnWatch: Task<Void, Never>?
    private var webSession: ASWebAuthenticationSession?

    /// Nonisolated so `StravaAuthClient.liveValue` can build it from whatever thread first
    /// resolves the dependency; everything it holds starts empty.
    nonisolated override init() {
        super.init()
    }

    func authorize(state: String) async throws -> URL {
        guard !isAuthorizing else { throw StravaAuthError.inProgress }
        isAuthorizing = true
        defer {
            isAuthorizing = false
            webSession = nil
        }

        let appURL = StravaConfig.appAuthorizeURL(state: state)
        if UIApplication.shared.canOpenURL(appURL), await UIApplication.shared.open(appURL) {
            return try await redirectFromStravaApp()
        }
        return try await redirectFromWeb(StravaConfig.webAuthorizeURL(state: state))
    }

    /// Takes Strava's redirect from the Strava app. True when `url` is that redirect, whether or
    /// not a sign-in was waiting for it.
    func handleRedirect(_ url: URL) -> Bool {
        guard StravaConfig.isRedirect(url) else { return false }
        if pendingRedirect == nil {
            logger.notice("a Strava redirect arrived with no sign-in waiting")
        }
        finishRedirect(.success(url))
        return true
    }

    // MARK: - Strava app

    private func redirectFromStravaApp() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRedirect = continuation
                watchForReturn()
            }
        } onCancel: {
            Task { @MainActor in self.finishRedirect(.failure(CancellationError())) }
        }
    }

    /// Ends the sign-in as cancelled when the rider is back in the app and no redirect follows
    /// within `redirectGrace`.
    private func watchForReturn() {
        returnWatch = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                try? await Task.sleep(for: Self.redirectGrace)
                guard !Task.isCancelled else { return }
                self?.finishRedirect(.failure(StravaAuthError.cancelled))
                return
            }
        }
    }

    private func finishRedirect(_ result: Result<URL, any Error>) {
        returnWatch?.cancel()
        returnWatch = nil
        guard let continuation = pendingRedirect else { return }
        pendingRedirect = nil
        continuation.resume(with: result)
    }

    // MARK: - Web

    private func redirectFromWeb(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callback: .customScheme(StravaConfig.redirectScheme)
                ) { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                    } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: StravaAuthError.cancelled)
                    } else {
                        logger.error("Strava web sign-in failed: \(String(describing: error), privacy: .public)")
                        continuation.resume(throwing: error ?? StravaAuthError.invalidCallback)
                    }
                }
                session.presentationContextProvider = self
                webSession = session
                // A session that fails to start never calls its completion handler.
                if !session.start() {
                    logger.error("Strava web sign-in didn't start")
                    continuation.resume(throwing: StravaAuthError.cancelled)
                }
            }
        } onCancel: {
            Task { @MainActor in self.webSession?.cancel() }
        }
    }
}

extension StravaAuthPresenter: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
    }
}
