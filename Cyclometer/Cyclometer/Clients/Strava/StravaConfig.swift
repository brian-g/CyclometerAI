import Foundation

/// Strava's OAuth settings (PRD §8.12). Nothing here is secret: the client id and redirect appear
/// in every authorize URL. The client secret lives only in the token service (`AppLinks`).
enum StravaConfig {
    /// The Strava API application's client id.
    static let clientID = "300241"

    /// Where Strava sends the rider back. The host must match the Authorization Callback Domain
    /// in Strava's API settings; the scheme is registered in `CFBundleURLTypes`, which the Strava
    /// app's redirect needs (the web session catches it without registration).
    static let redirectScheme = "cyclometer"
    static let redirectHost = "acmeapps.xyz"
    static let redirectPath = "/strava"
    static let redirectURI = "\(redirectScheme)://\(redirectHost)\(redirectPath)"

    /// Requested at connect. Strava's consent screen lets the rider untick any of them, so what
    /// was granted is read from the callback, never assumed from this list.
    static let requestedScopes = ["read", "read_all", "profile:read_all", "activity:read_all", "activity:write"]

    /// `kSecAttrAccount` of the Keychain item holding Strava's `OAuthTokens`.
    static let keychainAccount = "strava"

    /// A token with less than this left is refreshed before use (PRD §8.12).
    static let refreshMargin: TimeInterval = 5 * 60

    /// The Strava app's authorize URL, opened when `canOpenURL` accepts `strava://`.
    static func appAuthorizeURL(state: String) -> URL {
        authorizeURL(base: "strava://oauth/mobile/authorize", state: state)
    }

    /// The web authorize URL, shown in an `ASWebAuthenticationSession` when the Strava app isn't
    /// installed.
    static func webAuthorizeURL(state: String) -> URL {
        authorizeURL(base: "https://www.strava.com/oauth/mobile/authorize", state: state)
    }

    /// Whether `url` is Strava sending the rider back, rather than another URL the app was
    /// handed.
    static func isRedirect(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectScheme
            && url.host()?.lowercased() == redirectHost
            && url.path() == redirectPath
    }

    private static func authorizeURL(base: String, state: String) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: requestedScopes.joined(separator: ",")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}
