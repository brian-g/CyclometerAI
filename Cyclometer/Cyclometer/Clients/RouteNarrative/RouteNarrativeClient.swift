import ComposableArchitecture
import Foundation
import FoundationModels
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger.cyclometer(.routes)

/// TCA dependency for the on-device language model (`FoundationModels`), which writes S20's route
/// paragraph from a computed `RouteNarrativeInput` (#203). Nothing leaves the device (PRD §12,
/// Privacy).
struct RouteNarrativeClient: Sendable {
    /// False where the model cannot run: a device without Apple Intelligence, Apple Intelligence
    /// turned off, or the model not downloaded yet. S20 then shows its Summary as it always has.
    var isAvailable: @Sendable () -> Bool
    /// A paragraph that has passed `RouteNarrative.validated`. Throws when the model fails or its
    /// answer is rejected, so nothing that breaks the rules is ever stored.
    var narrate: @Sendable (RouteNarrativeInput) async throws -> String
}

enum RouteNarrativeError: Error, Equatable {
    /// The model answered, but with figures, units or a run-on paragraph.
    case rejected
    /// The inert test and preview value's answer: no model was asked.
    case unavailable
}

extension RouteNarrativeClient: DependencyKey {
    static let liveValue = RouteNarrativeClient(
        isAvailable: {
            guard case .available = SystemLanguageModel.default.availability else { return false }
            return true
        },
        narrate: { input in
            // A fresh session per route: a transcript carried over would let one route's facts
            // leak into the next one's paragraph.
            let session = LanguageModelSession(instructions: RouteNarrative.instructions)
            // Default sampling, not greedy: a rejected answer is asked for again on the next
            // launch, and greedy would give the same rejected answer every time.
            let response = try await session.respond(
                to: input.prompt, schema: try schema(sentenceCount: input.sections.count)
            )
            let sentences = try response.content.value([String].self, forProperty: "sentences")
            guard let text = RouteNarrative.paragraph(sentences) else {
                logger.error("route narrative rejected: \(sentences.joined(separator: " | "), privacy: .private)")
                throw RouteNarrativeError.rejected
            }
            logger.notice("route narrative generated, \(text.count, privacy: .public) characters")
            return text
        }
    )

    /// The model's answer: exactly one sentence per section, which `RouteNarrative.paragraph`
    /// tidies and joins. Built per route rather than declared `@Generable`, whose `.count` is fixed
    /// at compile time: allowed one to five, the model wrote five sentences about a route with one
    /// section and padded them with what it does not say. Structure only, never a terrain enum
    /// to classify into: that would not make the model's arithmetic more reliable, and S20 already
    /// shows the computed one.
    private static func schema(sentenceCount: Int) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(
            name: "RouteNarrative",
            properties: [DynamicGenerationSchema.Property(
                name: "sentences",
                description: "One complete sentence per section, in riding order, each starting with a capital letter and ending with a full stop.",
                schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self),
                                                minimumElements: sentenceCount, maximumElements: sentenceCount)
            )]
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Behaves like a device without Apple Intelligence, so no existing suite sees a new action
    /// and every snapshot stays deterministic.
    static let testValue = RouteNarrativeClient(
        isAvailable: { false },
        narrate: { _ in throw RouteNarrativeError.unavailable }
    )
    static let previewValue = testValue
}

extension DependencyValues {
    var routeNarrativeClient: RouteNarrativeClient {
        get { self[RouteNarrativeClient.self] }
        set { self[RouteNarrativeClient.self] = newValue }
    }
}
