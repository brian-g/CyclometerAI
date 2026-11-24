import Foundation

/// The app's links to acmeapps.xyz, kept in one place so a page that moves is one edit.
enum AppLinks {
    /// The maintained privacy policy, and the URL App Store Connect points to (#598). The
    /// app links here rather than bundling a copy, which drifted from both the code and
    /// the site.
    static let privacyPolicy = URL(string: "https://acmeapps.xyz/ride/privacy/")!

    /// The Strava token service (#625, PRD §8.12): `token`, `refresh` and `revoke` add the
    /// client secret the app can't hold and forward to Strava. Stateless; it stores nothing.
    static let stravaTokenService = URL(string: "https://acmeapps.xyz/ride/api/strava/")!
}
