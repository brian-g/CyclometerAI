import ComposableArchitecture
import CoreMotion
import os

private let logger = Logger.cyclometer(.location)

/// One barometric altimeter reading (#387).
enum AltimeterReading: Equatable, Sendable {
    /// Metres above sea level, which Core Motion fuses from the barometer and GPS. `accuracy` is
    /// its one-sigma error in metres.
    case absolute(meters: Double, accuracy: Double)
    /// Metres climbed (negative: descended) since the stream started. The barometer alone, so it
    /// tracks change to a fraction of a metre but knows nothing about sea level.
    case relative(meters: Double)
}

// MARK: - AltimeterClient

/// The barometer, for altitude a GPS fix can't give (#387): GPS altitude moves by metres from one
/// fix to the next, enough to credit a flat road with climbing.
///
/// Absolute altitude where the device reports it, relative altitude otherwise, and a stream that
/// finishes at once where it can give neither — no barometer (the simulator), or Motion & Fitness
/// access denied. `AltitudeResolver` falls back to GPS for that.
struct AltimeterClient: Sendable {
    var updates: @Sendable () -> AsyncStream<AltimeterReading>
}

// MARK: - DependencyKey

extension AltimeterClient: DependencyKey {
    static let liveValue = AltimeterClient(
        updates: {
            AsyncStream { continuation in
                let session = AltimeterSession()
                continuation.onTermination = { _ in session.stop() }
                session.start(continuation)
            }
        }
    )

    static let testValue = AltimeterClient(
        updates: { AsyncStream { $0.finish() } }
    )
}

extension DependencyValues {
    var altimeterClient: AltimeterClient {
        get { self[AltimeterClient.self] }
        set { self[AltimeterClient.self] = newValue }
    }
}

// MARK: - Live session

/// One stream's `CMAltimeter`. A manager per stream, not a shared one: unlike CoreLocation,
/// Core Motion carries no app-wide delegate or authorization state to keep in one place.
///
/// `@unchecked Sendable`: `CMAltimeter` isn't `Sendable`, and its start and stop calls are safe
/// from any thread — Core Motion delivers on `queue`.
private final class AltimeterSession: @unchecked Sendable {
    private let altimeter = CMAltimeter()
    private let queue = OperationQueue()

    func start(_ continuation: AsyncStream<AltimeterReading>.Continuation) {
        switch CMAltimeter.authorizationStatus() {
        case .denied, .restricted:
            logger.notice("altimeter unavailable: motion access denied")
            continuation.finish()
            return
        default:
            break
        }

        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            logger.notice("altimeter: absolute")
            altimeter.startAbsoluteAltitudeUpdates(to: queue) { data, error in
                guard let data else {
                    logger.error("altimeter stopped: \(String(describing: error), privacy: .public)")
                    continuation.finish()
                    return
                }
                continuation.yield(.absolute(meters: data.altitude, accuracy: data.accuracy))
            }
        } else if CMAltimeter.isRelativeAltitudeAvailable() {
            logger.notice("altimeter: relative")
            altimeter.startRelativeAltitudeUpdates(to: queue) { data, error in
                guard let data else {
                    logger.error("altimeter stopped: \(String(describing: error), privacy: .public)")
                    continuation.finish()
                    return
                }
                continuation.yield(.relative(meters: data.relativeAltitude.doubleValue))
            }
        } else {
            logger.notice("altimeter unavailable on this device")
            continuation.finish()
        }
    }

    func stop() {
        altimeter.stopAbsoluteAltitudeUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}
