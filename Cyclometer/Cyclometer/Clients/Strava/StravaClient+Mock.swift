import ComposableArchitecture
import Foundation

extension StravaClient {
    /// A scripted Strava for reducers (#630 onward) and previews. Anything not scripted answers
    /// 404, like a Strava id that doesn't exist.
    ///
    /// - Parameter uploadStatuses: Answered in order by successive `uploadStatus` calls, the last
    ///   one repeating, so a test can walk an upload through `.processing` to `.ready`.
    /// - Parameter routes: The first page; later pages are empty.
    static func mock(
        uploadID: StravaUploadID = StravaUploadID(rawValue: "1"),
        uploadStatuses: [StravaUploadStatus] = [.ready(activityID: "1")],
        efforts: [String: [StravaSegmentEffort]] = [:],
        routes: [StravaRouteSummary] = [],
        routeDetails: [String: StravaRouteDetail] = [:],
        gpx: [String: Data] = [:],
        bikes: [StravaGear] = [],
        onUpload: @escaping @Sendable (StravaUpload) -> Void = { _ in },
        onSetGear: @escaping @Sendable (_ activityID: String, _ gearID: String) -> Void = { _, _ in }
    ) -> StravaClient {
        let polls = LockIsolated(0)
        return StravaClient(
            upload: { upload in
                onUpload(upload)
                return uploadID
            },
            uploadStatus: { id in
                guard id == uploadID, !uploadStatuses.isEmpty else { throw StravaError.http(status: 404) }
                let index = polls.withValue { count in
                    defer { count += 1 }
                    return min(count, uploadStatuses.count - 1)
                }
                return uploadStatuses[index]
            },
            segmentEfforts: { activityID in
                guard let efforts = efforts[activityID] else { throw StravaError.http(status: 404) }
                return efforts
            },
            routes: { page in page == 1 ? routes : [] },
            route: { routeID in
                guard let detail = routeDetails[routeID] else { throw StravaError.http(status: 404) }
                return detail
            },
            routeGPX: { routeID in
                guard let data = gpx[routeID] else { throw StravaError.http(status: 404) }
                return data
            },
            bikes: { bikes },
            setGear: { activityID, gearID in onSetGear(activityID, gearID) }
        )
    }
}
