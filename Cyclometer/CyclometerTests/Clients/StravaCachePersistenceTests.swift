import Foundation
import SwiftData
import Testing
@testable import Cyclometer

/// `PersistenceClient.clearStravaCaches`, run when Strava is disconnected (PRD §8.12,
/// DataModel.md §3.8.1): the segment data cached on rides and routes goes, and what the rider
/// keeps stays.
@Suite("PersistenceClient — Strava caches")
struct StravaCachePersistenceTests {
    @Test("Clears segment efforts and route segments, keeping sync records and the Strava route id")
    func clearsCachesKeepsRecords() async throws {
        let (client, stack) = PersistenceClientTests.makeLiveClient()
        let rideId = UUID()
        try await client.createRide(rideId, Date(timeIntervalSince1970: 1_800_000_000), nil)
        let routeId = try await client.importRoute(RoutePersistenceTests.climbingRoute()).id
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let syncRecord = RideSyncRecord(service: .strava, status: .synced, syncedAt: fetchedAt, remoteActivityId: "987")

        let seed = ModelContext(stack.container)
        let ride = try #require(try seed.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == rideId })).first)
        ride.stravaSegmentEffortsData = Data("[]".utf8)
        ride.stravaSegmentsFetchedAt = fetchedAt
        ride.syncRecords = [syncRecord]
        let route = try #require(try seed.fetch(FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeId })).first)
        route.stravaRouteID = "r-1"
        route.stravaSegmentsData = Data("[]".utf8)
        route.stravaSegmentsFetchedAt = fetchedAt
        try seed.save()

        try await client.clearStravaCaches()

        // A fresh context, so the assertions read the store rather than the seed's objects.
        let check = ModelContext(stack.container)
        let clearedRide = try #require(try check.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == rideId })).first)
        #expect(clearedRide.stravaSegmentEffortsData == nil)
        #expect(clearedRide.stravaSegmentsFetchedAt == nil)
        #expect(clearedRide.syncRecord(for: .strava)?.remoteActivityId == "987")
        let clearedRoute = try #require(try check.fetch(FetchDescriptor<Route>(predicate: #Predicate { $0.id == routeId })).first)
        #expect(clearedRoute.stravaSegmentsData == nil)
        #expect(clearedRoute.stravaSegmentsFetchedAt == nil)
        #expect(clearedRoute.stravaRouteID == "r-1")
    }

    @Test("With nothing cached, clearing is a no-op")
    func clearingNothing() async throws {
        let (client, _) = PersistenceClientTests.makeLiveClient()
        try await client.clearStravaCaches()
    }
}
