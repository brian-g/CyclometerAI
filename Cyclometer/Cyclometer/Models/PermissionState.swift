import Foundation

/// The four system authorization domains S01 presents, in the order the screen
/// lists them (UX.md §S01).
///
/// A domain is *not* a framework — it is a thing the rider is asked for. Bluetooth
/// covers every BLE sensor rather than one per profile, because iOS prompts once for
/// the app, not once per peripheral.
enum PermissionDomain: String, CaseIterable, Sendable {
    case bluetooth
    case locationWhenInUse
    case motion
    case health
}

/// The uniform vocabulary every domain reports in, so S01 can render four rows from
/// one switch rather than four framework-specific ones.
///
/// Two cases go beyond the obvious four:
///
/// - `grantedAlways` exists because Location is the only domain with two useful
///   grant levels. Onboarding asks for When In Use; the escalation to Always is
///   raised at first ride start, where the reason is legible (UX.md §S01). Callers
///   that only care whether the domain is usable should ask `isGranted`.
/// - `unavailable` is the state a *capability* can be in that an *authorization*
///   cannot: the hardware isn't there. `CMMotionActivityManager.isActivityAvailable()`
///   is false on the Simulator and on some devices, and without this case motion
///   would sit at `notDetermined` forever — which S01 treats as "not yet granted",
///   deadlocking its Next button on every Simulator run. Treat it as non-blocking.
enum PermissionState: Equatable, Sendable {
    /// Never asked. The only state from which a prompt is worth presenting.
    case notDetermined
    /// Granted. For Location this means When In Use specifically.
    case granted
    /// Location only — background recording is authorized.
    case grantedAlways
    /// The rider said no. Only iOS Settings can undo this; the app cannot re-prompt.
    case denied
    /// Withheld by policy (Screen Time, MDM, parental controls) rather than by the
    /// rider. Indistinguishable from `denied` in what the app may do about it, but
    /// worth keeping separate so copy can stop telling a managed device to visit
    /// Settings, where the switch will be greyed out.
    case restricted
    /// The capability does not exist on this device. Not a refusal.
    case unavailable

    /// Whether the domain is usable. Collapses the two Location grant levels so
    /// callers that merely need "may I read this?" don't have to know Location is
    /// special.
    var isGranted: Bool {
        self == .granted || self == .grantedAlways
    }
}

/// One domain's status at a moment in time — the element type of the change stream.
///
/// A struct rather than a tuple so the stream is `Equatable` at the element level and
/// reads as `change.domain` at the call site.
struct PermissionChange: Equatable, Sendable {
    let domain: PermissionDomain
    let state: PermissionState
}
