import Foundation

/// What S20's route paragraph is written from (#203): the route's terrain, already computed, handed
/// to the on-device model to put into words. **The model narrates; it does not classify.** Every
/// fact here — the character, the gradient spread, where each climb sits — is arithmetic done
/// before the model sees it, so the paragraph can only rephrase what `RouteTerrain` decided.
///
/// The route goes in as sections in riding order, split where the terrain changes — each
/// categorized climb, and the stretches between — with one sentence asked for per section.
/// Both halves of that came from running the model:
/// - A fact without a position invites the model to invent one. Given one gradient spread for the
///   whole route, it wrote "the final third drops gently" about a route flat end to end.
/// - The model keeps about one fact per sentence. Given more sections than sentences, it merged
///   them and dropped one, most often the hardest climb.
struct RouteNarrativeInput: Sendable, Equatable {
    var character: RouteCharacter
    var sections: [Section]

    struct Section: Sendable, Equatable {
        /// Where it starts and ends, as shares of the route's distance.
        var from: Double
        var to: Double
        /// In riding order. One, unless sections were merged to fit `maximumSections`.
        var parts: [Part]
    }

    enum Part: Sendable, Equatable {
        /// The share of the stretch's distance in each band, 0...1.
        case stretch([GradeBand: Double])
        case climb(ClimbPlacement)
    }

    struct ClimbPlacement: Sendable, Equatable {
        var category: ClimbCategory
        var averageGradePercent: Double
        /// The highest FIETS score on a route with more than one climb, as S20's Hardest Climb
        /// row reads it.
        var isHardest: Bool
    }

    /// One sentence each, so no more than the model is asked to write.
    static let maximumSections = RouteNarrative.sentenceCount.upperBound

    /// A stretch between climbs shorter than this share of the route is left out rather than made
    /// a section of its own: a sentence about a few hundred metres of false flat would crowd out
    /// one about a climb. The same share is how close to either end counts as the start or finish.
    static let minimumStretchShare = 0.05

    /// Nil for a route without a terrain analysis — no `<ele>`, or no length — which is never
    /// narrated: S20's Summary section already has nothing to say about it.
    init?(summary: RouteSummary, coordinates: [RouteCoordinate]) {
        guard let terrain = summary.terrain,
              summary.distanceMeters > 0,
              let grades = RouteTerrain.gradeProfile(coordinates)?.grades,
              !grades.isEmpty
        else { return nil }
        let distance = summary.distanceMeters
        let hardest = terrain.climbs.count > 1 ? terrain.hardestClimb : nil

        func stretch(_ from: Double, _ to: Double) -> Section {
            Section(from: from, to: to, parts: [.stretch(Self.gradeShares(grades, from: from, to: to))])
        }

        var sections: [Section] = []
        if terrain.climbs.isEmpty {
            // Nothing to split at, so thirds, which still say where the route climbs or falls.
            sections = [stretch(0, 1.0 / 3), stretch(1.0 / 3, 2.0 / 3), stretch(2.0 / 3, 1)]
        } else {
            var cursor = 0.0
            for climb in terrain.climbs {
                let start = climb.startMeters / distance
                let top = min(1, (climb.startMeters + climb.lengthMeters) / distance)
                if start - cursor >= Self.minimumStretchShare { sections.append(stretch(cursor, start)) }
                sections.append(Section(from: start, to: top, parts: [.climb(ClimbPlacement(
                    category: climb.category,
                    averageGradePercent: climb.averageGradePercent,
                    isHardest: climb == hardest
                ))]))
                cursor = top
            }
            if 1 - cursor >= Self.minimumStretchShare { sections.append(stretch(cursor, 1)) }
        }

        // Neighbouring stretches that read the same are one stretch, or the model narrates a
        // change that never happens ("then it stays the same").
        var index = 1
        while index < sections.count {
            if let previous = sections[index - 1].onlyStretch, let current = sections[index].onlyStretch,
               Self.describe(previous) == Self.describe(current) {
                sections[index - 1] = stretch(sections[index - 1].from, sections[index].to)
                sections.remove(at: index)
            } else {
                index += 1
            }
        }

        // A route with more climbs than sentences: join the neighbouring pair that covers the
        // least distance until it fits, keeping both pairs' parts in riding order. Folded into a
        // recomputed gradient spread instead ("mostly flat, including a Cat 4 climb"), a climb
        // went unmentioned by the model every time.
        while sections.count > Self.maximumSections {
            let first = sections.indices.dropLast().min {
                sections[$0 + 1].to - sections[$0].from < sections[$1 + 1].to - sections[$1].from
            }!
            sections[first] = Section(from: sections[first].from, to: sections[first + 1].to,
                                      parts: sections[first].parts + sections[first + 1].parts)
            sections.remove(at: first + 1)
        }

        character = terrain.character
        self.sections = sections
    }

    init(character: RouteCharacter, sections: [Section]) {
        self.character = character
        self.sections = sections
    }

    /// The facts as the model reads them. The few figures left — a climb's category and average
    /// grade — are there for scale only, and never reach the answer (`RouteNarrative.validated`),
    /// so the rider's unit picker has no bearing here.
    var prompt: String {
        (["Route character: \(character.promptText).",
          "The route in sections, in riding order. Write one sentence per section."]
         + sections.map { "- \($0.label): \(Self.describe($0))" })
            .joined(separator: "\n")
    }

    // MARK: - Words

    /// A band at or above this share of a section is worth a word.
    static let notableShare = 0.15
    /// Short very steep rises are worth a word even when they add up to little distance: they are
    /// what a punchy route is.
    static let notableVerySteepShare = 0.02

    /// The section's parts in riding order: "A Cat 4 climb averaging 6%, then mostly flat."
    static func describe(_ section: Section) -> String {
        let text = section.parts.map { part in
            switch part {
            case .stretch(let shares): describe(shares)
            case .climb(let climb): climbText(climb)
            }
        }.joined(separator: ", then ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// "flat throughout", "mostly flat, with some steep climbing", "mixed: flat, descending and
    /// gentle climbing", in words only.
    static func describe(_ shares: [GradeBand: Double]) -> String {
        let notable = GradeBand.allCases
            .filter { (shares[$0] ?? 0) >= notableShare }
            .sorted { (shares[$0] ?? 0) > (shares[$1] ?? 0) }
        guard let top = notable.first else { return "mixed" }
        var text: String
        if (shares[top] ?? 0) >= 0.9 {
            text = "\(top.label) throughout"
        } else if (shares[top] ?? 0) >= 0.5 {
            text = "mostly \(top.label)"
            if notable.count > 1 {
                text += ", with some " + list(notable.dropFirst().map(\.label))
            }
        } else {
            text = "mixed: " + list(notable.map(\.label))
        }
        if !notable.contains(.verySteep), (shares[.verySteep] ?? 0) >= notableVerySteepShare {
            text += ", with short very steep rises"
        }
        return text
    }

    private static func climbText(_ climb: ClimbPlacement) -> String {
        let grade = climb.averageGradePercent.formatted(.number.precision(.fractionLength(0)))
        return climb.isHardest
            ? "the hardest climb, a \(climb.category.label) averaging \(grade)%"
            : "a \(climb.category.label) climb averaging \(grade)%"
    }

    private static func list(_ words: [String]) -> String {
        words.count < 2 ? words.joined() : words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    // MARK: - Arithmetic

    /// Samples are evenly spaced by distance, so a share of samples is a share of distance.
    static func gradeShares(_ grades: [Double], from: Double, to: Double) -> [GradeBand: Double] {
        let lower = min(grades.count - 1, max(0, Int((from * Double(grades.count)).rounded(.down))))
        let upper = min(grades.count, max(lower + 1, Int((to * Double(grades.count)).rounded(.up))))
        let span = grades[lower..<upper]
        return Dictionary(uniqueKeysWithValues: GradeBand.allCases.map { band in
            (band, Double(span.filter { GradeBand($0) == band }.count) / Double(span.count))
        })
    }
}

extension RouteNarrativeInput.Section {
    /// The gradient spread, for a section that is one stretch and nothing else.
    var onlyStretch: [GradeBand: Double]? {
        guard parts.count == 1, case .stretch(let shares) = parts[0] else { return nil }
        return shares
    }

    /// "From the start until early on", "Midway", "The whole route".
    var label: String {
        let start = RoutePosition(fraction: from)
        // Just short of `to`, so a section ending exactly on a boundary ends in the position
        // before it: the first third ends "early on", not "midway".
        let end = RoutePosition(fraction: max(from, to - 1e-9))
        switch (start, end) {
        case (.start, .finish): return "The whole route"
        case _ where start == end: return start.alone
        default: return "From \(start.label) until \(end.label)"
        }
    }
}

private extension RouteCharacter {
    /// A punchy route has no categorized climb by definition, so it is the one character that
    /// needs saying what it means; "punchy" alone reads to the model as a mood.
    var promptText: String {
        self == .punchy ? "punchy: no long climbs, but frequent short steep rises" : rawValue
    }
}

/// Bands for the gradient spread, on the smoothed grade `RouteTerrain.grades` computes. Edges
/// belong to the steeper band.
enum GradeBand: CaseIterable, Sendable, Hashable {
    case descending, flat, gentle, steep, verySteep

    init(_ gradePercent: Double) {
        switch gradePercent {
        case ..<(-2): self = .descending
        case ..<2: self = .flat
        case ..<5: self = .gentle
        case ..<8: self = .steep
        default: self = .verySteep
        }
    }

    var label: String {
        switch self {
        case .descending: "descending"
        case .flat: "flat"
        case .gentle: "gentle climbing"
        case .steep: "steep climbing"
        case .verySteep: "very steep climbing"
        }
    }
}

/// Where along the route something happens, coarse enough to stay true in words.
enum RoutePosition: Sendable, Equatable {
    case start, early, midway, late, finish

    /// `fraction` is a share of the route's distance. Within `minimumStretchShare` of either end
    /// is that end; the rest is thirds, each edge belonging to the later one.
    init(fraction: Double) {
        let edge = RouteNarrativeInput.minimumStretchShare
        switch fraction {
        case ..<edge: self = .start
        case ..<(1.0 / 3): self = .early
        case ..<(2.0 / 3): self = .midway
        case ..<(1 - edge): self = .late
        default: self = .finish
        }
    }

    var label: String {
        switch self {
        case .start: "the start"
        case .early: "early on"
        case .midway: "midway"
        case .late: "late on"
        case .finish: "the finish"
        }
    }

    /// A section that begins and ends in the same place.
    var alone: String {
        switch self {
        case .start: "At the start"
        case .early: "Early on"
        case .midway: "Midway"
        case .late: "Late on"
        case .finish: "At the finish"
        }
    }
}

enum RouteNarrative {

    /// Roughly three sentences, plus or minus two: one per section, and a route has one to
    /// `RouteNarrativeInput.maximumSections`. The output is sentences the app joins
    /// (`paragraph(_:)`), not prose shown as it comes: asked for a paragraph, the model answered
    /// in lower case, one clause a line.
    static let sentenceCount = 1...5

    /// Past this, the paragraph is rejected rather than stored. Routes with one climb in each
    /// section came to 130–410 characters. A route with more climbs than sections carries two or
    /// three parts a sentence and ran to 460–600, with one run in five past this.
    static let maximumLength = 600

    static let instructions = """
        You tell a cyclist what riding a route will feel like, from facts about its elevation. \
        Write one short, natural sentence for each section, the way a friend who knows the \
        road would describe it. Every claim must come from the facts, section by section; never \
        invent climbs, places, roads, surfaces or scenery, and don't repeat the facts word for \
        word. The app shows every figure beside your text, so never write a number, a digit, a \
        count, a distance, a grade, a percentage or a unit of measure, and don't name climb \
        categories. Call it the route or the road. Write in English.
        """

    /// The model's sentences as S20 shows them, or nil when they break the rules above. Each is
    /// tidied — the model leaves a space before its full stops, and sometimes no full stop — and
    /// the whole is then held to `validated`.
    static func paragraph(_ sentences: [String]) -> String? {
        guard sentenceCount.contains(sentences.count) else { return nil }
        let tidied = sentences.map { sentence -> String in
            var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            while let last = text.last, last == " " || last == "." { text.removeLast() }
            guard let first = text.first else { return "" }
            let ending = text.last == "!" || text.last == "?" ? "" : "."
            return first.uppercased() + text.dropFirst() + ending
        }
        guard !tidied.contains("") else { return nil }
        return validated(tidied.joined(separator: " "))
    }

    /// What makes "never contradicts the figures shown beside it" hold: text with no figures in it
    /// cannot quote a wrong one, and stored text with no units cannot go stale when the rider
    /// changes the S12 unit picker. Nil for anything else.
    static func validated(_ text: String) -> String? {
        guard !text.isEmpty,
              text.count <= maximumLength,
              text.rangeOfCharacter(from: .decimalDigits) == nil,
              !text.contains("%"),
              // A unit as a whole word. Not after an apostrophe, so "I'm" is not read as metres.
              text.firstMatch(of: #/(?i)(?:^|[^'’\w])(km|kms|kilomet(er|re)s?|mi|miles?|m|met(er|re)s?|ft|foot|feet)\b/#) == nil
        else { return nil }
        return text
    }
}
