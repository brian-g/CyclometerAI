import Foundation
import Synchronization
import os

/// One JSON-backed column of a `Ride` or `Route`, and the only way its accessor reads or writes
/// it (#563). It exists because a `try?` on either side turns a failure into silent data loss: an
/// undecodable value read as empty, and the next checkpoint wrote the post-resume remainder over
/// it; a NaN made the encode throw, and the column was set to nil (lessons, #191).
///
/// - A value that doesn't decode reads as absent, and its stored bytes are kept: `write` refuses
///   to replace them. A later build may be able to read them again; once overwritten, nothing can.
/// - A value that doesn't encode leaves the column as it was.
/// - A value that encodes to the bytes already stored isn't written again.
///
/// Every failure is logged once per column per row per launch, with the column and the row's id,
/// never the payload: an undecodable column is read on every resume, list fetch and checkpoint,
/// and would otherwise log on each.
struct JSONColumn {
    /// The model's name, as the log line shows it: `Ride` or `Route`.
    let entity: String
    /// The stored property's name, e.g. `weatherData`.
    let name: String
    /// The row's id.
    let owner: UUID

    /// The decoded value; nil when there is none, or when it doesn't decode (logged). An empty
    /// `Data` is none: `RoutePersistenceActor.backfillRouteTerrain` stores one on purpose, and no
    /// encode ever produces one.
    func read<Value: Decodable>(_ type: Value.Type, from stored: Data?) -> Value? {
        guard let stored, !stored.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(type, from: stored)
        } catch {
            report(.unreadable, error)
            return nil
        }
    }

    /// Stores `value`, or nil when it is nil, through `store` — which isn't called at all when the
    /// column is to stay as it is: when `value` doesn't encode, when it encodes to the bytes
    /// already stored, or when the stored bytes don't decode as `Value`. In that last case `value`
    /// is lost, since there is no way to merge it into bytes this build can't read; that is logged
    /// unless `value` is nil, which loses nothing.
    func write<Value: Codable>(_ value: Value?, over stored: Data?, store: (Data?) -> Void) {
        let encoded: Data?
        if let value {
            guard let data = encode(value) else { return }
            encoded = data
        } else {
            encoded = nil
        }
        guard encoded != stored else { return }
        if let stored, !stored.isEmpty {
            do {
                _ = try JSONDecoder().decode(Value.self, from: stored)
            } catch {
                if encoded != nil { report(.writeDropped, error) }
                return
            }
        }
        store(encoded)
    }

    /// The encoded value; nil when it doesn't encode (logged) — JSON has no NaN or infinity.
    /// Keys are sorted, so an unchanged dictionary encodes to unchanged bytes and `write` can
    /// tell it hasn't changed.
    func encode<Value: Encodable>(_ value: Value) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(value)
        } catch {
            report(.unencodable, error)
            return nil
        }
    }

    // MARK: - Logging

    enum Failure: String {
        case unreadable, unencodable, writeDropped
    }

    /// Whether this launch has logged `failure` for this column of this row: for the tests, which
    /// can't read the log.
    func hasReported(_ failure: Failure) -> Bool {
        Self.reported.withLock { $0.contains(key(failure)) }
    }

    private static let logger = Logger.cyclometer(.persistence)
    private static let reported = Mutex<Set<String>>([])

    private func key(_ failure: Failure) -> String {
        "\(entity).\(name) \(owner) \(failure.rawValue)"
    }

    private func report(_ failure: Failure, _ error: any Error) {
        guard Self.reported.withLock({ $0.insert(key(failure)).inserted }) else { return }
        let column = "\(entity).\(name)"
        let reason = Self.describe(error)
        switch failure {
        case .unreadable:
            Self.logger.error("\(column, privacy: .public) on \(owner, privacy: .public) doesn't decode (\(reason, privacy: .public)); it reads as empty, and its stored bytes are kept")
        case .unencodable:
            Self.logger.error("\(column, privacy: .public) on \(owner, privacy: .public) didn't encode (\(reason, privacy: .public)); the stored value is left as it was")
        case .writeDropped:
            Self.logger.error("\(column, privacy: .public) on \(owner, privacy: .public) holds bytes that don't decode (\(reason, privacy: .public)); a write was dropped to keep them, and what it held is lost")
        }
    }

    /// The error's kind and where in the value it struck, never a value: a `DecodingError`'s own
    /// description can quote the offending one.
    private static func describe(_ error: any Error) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.isEmpty ? "top level" : codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            return "keyNotFound \(key.stringValue) at \(path(context.codingPath))"
        case DecodingError.typeMismatch(let type, let context):
            return "typeMismatch \(type) at \(path(context.codingPath))"
        case DecodingError.valueNotFound(let type, let context):
            return "valueNotFound \(type) at \(path(context.codingPath))"
        case DecodingError.dataCorrupted(let context):
            return "dataCorrupted at \(path(context.codingPath))"
        case EncodingError.invalidValue(_, let context):
            return "invalidValue at \(path(context.codingPath))"
        default:
            return String(describing: type(of: error))
        }
    }
}
