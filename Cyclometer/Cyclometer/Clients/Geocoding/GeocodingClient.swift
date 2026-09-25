import ComposableArchitecture
import CoreLocation
import Foundation
import MapKit
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "network")

/// TCA dependency for Apple's reverse geocoder, which names the place a ride started in for
/// S10's default ride name (#283). It sends one coordinate — a free ride's start — and nothing
/// else (PRD §12, Privacy).
struct GeocodingClient: Sendable {
    /// The town or city `coordinate` lies in, or nil where there is none (open water, say).
    var locality: @Sendable (RouteCoordinate) async throws -> String?
}

enum GeocodingError: Error, Equatable {
    /// The inert test and preview value's answer: nothing was asked, so nothing is known.
    case unavailable
}

extension GeocodingClient: DependencyKey {
    static let liveValue = GeocodingClient { coordinate in
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let locality = try await request.mapItems.first?.addressRepresentations?.cityName
            logger.notice("reverse geocode returned \(locality == nil ? "no locality" : "a locality", privacy: .public)")
            return locality
        } catch {
            logger.error("reverse geocode failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static let testValue = GeocodingClient { _ in throw GeocodingError.unavailable }
    static let previewValue = testValue
}

extension DependencyValues {
    var geocodingClient: GeocodingClient {
        get { self[GeocodingClient.self] }
        set { self[GeocodingClient.self] = newValue }
    }
}
