import Foundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.network)

/// The live `StravaClient` (TCA.md §4.15, PRD §8.12): builds each request, signs it, retries once
/// after a 401, and reads the rate-limit headers. Injected with a transport and an auth client, so
/// it is tested against recorded answers.
struct StravaAPI: Sendable {
    var transport: StravaTransport
    var auth: StravaAuthClient
    /// The connected athlete's id, which the routes endpoint needs.
    var athleteID: @Sendable () -> String?
    var now: @Sendable () -> Date

    var client: StravaClient {
        StravaClient(
            upload: { try await upload($0) },
            uploadStatus: { id in
                try StravaWire.upload(from: try await fetch(Request(name: "uploadStatus", path: "uploads/\(id.rawValue)"))).status
            },
            segmentEfforts: { activityID in
                try StravaWire.segmentEfforts(from: try await fetch(Request(
                    name: "activity",
                    path: "activities/\(activityID)",
                    query: [URLQueryItem(name: "include_all_efforts", value: "true")]
                )))
            },
            routes: { page in
                guard let athleteID = athleteID() else { throw StravaAuthError.notConnected }
                return try StravaWire.routes(from: try await fetch(Request(
                    name: "routes",
                    path: "athletes/\(athleteID)/routes",
                    query: [
                        URLQueryItem(name: "page", value: String(page)),
                        URLQueryItem(name: "per_page", value: String(StravaConfig.routesPerPage)),
                    ]
                )))
            },
            route: { routeID in
                try StravaWire.routeDetail(from: try await fetch(Request(name: "route", path: "routes/\(routeID)")))
            },
            routeGPX: { routeID in
                try await fetch(Request(name: "routeGPX", path: "routes/\(routeID)/export_gpx"))
            },
            athlete: {
                try StravaWire.athlete(from: try await fetch(Request(name: "athlete", path: "athlete")))
            },
            bikes: {
                try StravaWire.bikes(from: try await fetch(Request(name: "athlete", path: "athlete")))
            },
            setGear: { activityID, gearID in
                _ = try await fetch(Request(
                    name: "setGear",
                    method: "PUT",
                    path: "activities/\(activityID)",
                    body: try JSONEncoder().encode(["gear_id": gearID]),
                    contentType: "application/json"
                ))
            },
            activityExists: { activityID in
                do {
                    _ = try await fetch(Request(name: "activityExists", path: "activities/\(activityID)"))
                    return true
                } catch StravaError.http(status: 404) {
                    return false
                }
            }
        )
    }

    // MARK: - Upload

    /// `POST /uploads`, multipart, the GPX gzipped. Strava answers 201 while it processes, or 400
    /// when it rejected the file. Either way an answer with an id is returned, and polling it
    /// reports the duplicate or failure, so the queue has one path for both.
    private func upload(_ upload: StravaUpload) async throws -> StravaUploadID {
        var form = MultipartForm()
        form.add("data_type", "gpx.gz")
        form.add("sport_type", "Ride")
        form.add("name", upload.name)
        if let description = upload.description, !description.isEmpty { form.add("description", description) }
        form.add("external_id", upload.externalID)
        form.addFile("file", filename: "\(upload.externalID).gpx.gz", contentType: "application/gzip", data: try upload.gpx.gzipped())

        let (data, status) = try await perform(Request(
            name: "upload", method: "POST", path: "uploads", body: form.body, contentType: form.contentType, isUpload: true
        ))
        if (200..<300).contains(status) || status == 400, let id = (try? StravaWire.upload(from: data))?.id {
            if status == 400 { logger.notice("strava upload answered 400; polling reports why") }
            return id
        }
        guard (200..<300).contains(status) else { throw StravaError.http(status: status) }
        throw StravaError.invalidResponse
    }

    // MARK: - Transport

    struct Request {
        /// The endpoint, for logs: never the ids in the path.
        var name: String
        var method = "GET"
        var path: String
        var query: [URLQueryItem] = []
        var body: Data?
        var contentType: String?
        /// `POST /uploads`, which counts against the overall rate limit only, not the read one.
        var isUpload = false

        func urlRequest(token: String) -> URLRequest {
            var url = StravaConfig.apiBaseURL.appending(path: path)
            if !query.isEmpty { url.append(queryItems: query) }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
    }

    /// A 2xx answer's body. Any other status throws.
    private func fetch(_ request: Request) async throws -> Data {
        let (data, status) = try await perform(request)
        guard (200..<300).contains(status) else { throw StravaError.http(status: status) }
        return data
    }

    /// Sends a signed request and answers with its body and status. A 401 is retried once with a
    /// refreshed token: Strava revokes tokens the clock can't know about. Strava's refresh hands
    /// back the same token while it has over an hour left, and resending that only spends the
    /// shared rate limit, so it isn't resent. A 401 after the refresh throws `.unauthorized`, and a
    /// 429 throws `.rateLimited`. Other statuses are the caller's.
    private func perform(_ request: Request) async throws -> (Data, Int) {
        let token = try await auth.accessToken()
        var (data, response) = try await transport.send(request.urlRequest(token: token))
        if response.statusCode == 401 {
            let refreshed = try await auth.refreshAccessToken(token)
            if refreshed != token {
                (data, response) = try await transport.send(request.urlRequest(token: refreshed))
            }
        }

        let rateLimit = StravaRateLimit(response)
        if let rateLimit {
            logger.debug("strava \(request.name, privacy: .public): \(response.statusCode, privacy: .public), usage \(rateLimit.logDescription, privacy: .public)")
        }
        switch response.statusCode {
        case 401:
            logger.notice("strava \(request.name, privacy: .public): 401 after a refresh")
            throw StravaError.unauthorized
        case 429:
            let until = rateLimit?.resetDate(after: now(), isUpload: request.isUpload) ?? StravaRateLimit.nextQuarterHour(after: now())
            logger.notice("strava \(request.name, privacy: .public): rate limited until \(until, privacy: .public)")
            throw StravaError.rateLimited(until: until)
        case 200..<300:
            break
        default:
            logger.error("strava \(request.name, privacy: .public): \(response.statusCode, privacy: .public)")
        }
        return (data, response.statusCode)
    }
}

// MARK: - Multipart

/// A `multipart/form-data` body.
private struct MultipartForm {
    let boundary = "cyclometer-\(UUID().uuidString)"
    private var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    var body: Data { parts + Data("--\(boundary)--\r\n".utf8) }

    mutating func add(_ name: String, _ value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        parts.append(data)
        parts.append(Data("\r\n".utf8))
    }
}

private extension StravaRateLimit {
    /// "overall 12/200 340/2000, read 10/100 300/1000".
    var logDescription: String {
        func describe(_ windows: Windows?) -> String {
            guard let windows else { return "–" }
            return "\(windows.fifteenMinutes.usage)/\(windows.fifteenMinutes.limit) \(windows.daily.usage)/\(windows.daily.limit)"
        }
        return "overall \(describe(overall)), read \(describe(read))"
    }
}
