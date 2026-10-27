import Foundation
import Testing
@testable import Cyclometer

/// The arithmetic and the rules around S20's on-device paragraph (#203): which sections the route
/// is split into, what the model is told about each, and what of its answer may be shown. The
/// model itself is never called here; it is not deterministic, and not on every machine.
@Suite("RouteNarrative")
struct RouteNarrativeTests {

    // MARK: Harness

    /// A straight route north, a point every 20 m, its elevation given pitch by pitch as
    /// `(metres, grade)`, starting at 100 m. Through the import's own derivation, so each input is
    /// built from the same terrain analysis a saved route carries.
    private func route(_ pitches: [(meters: Double, gradePercent: Double)])
        -> (summary: RouteSummary, coordinates: [RouteCoordinate]) {
        let total = pitches.reduce(0) { $0 + $1.meters }
        let path = RouteFixtures.path(legs: [(0, total)], spacingMeters: 20)
        let cumulative = RouteGeometry.cumulativeDistances(path)
        let coordinates = zip(path, cumulative).map { point, distance in
            var point = point
            var elevation = 100.0
            var start = 0.0
            for pitch in pitches {
                elevation += min(max(distance - start, 0), pitch.meters) * pitch.gradePercent / 100
                start += pitch.meters
            }
            point.elevationMeters = elevation
            return point
        }
        let imported = ImportedRoute(name: nil, terrainDescription: nil, coordinates: coordinates, cuePoints: [])
        return (RouteSummary(imported: imported), coordinates)
    }

    private func input(_ pitches: [(meters: Double, gradePercent: Double)]) throws -> RouteNarrativeInput {
        let (summary, coordinates) = route(pitches)
        return try #require(RouteNarrativeInput(summary: summary, coordinates: coordinates))
    }

    private func climbs(_ section: RouteNarrativeInput.Section) -> [RouteNarrativeInput.ClimbPlacement] {
        section.parts.compactMap { if case .climb(let climb) = $0 { climb } else { nil } }
    }

    // MARK: Sections

    @Test("a route with no elevation has no input, so it is never narrated")
    func noElevationIsNil() {
        let path = RouteFixtures.path(legs: [(0, 5_000)], spacingMeters: 20)
        let summary = RouteSummary(imported: ImportedRoute(name: nil, terrainDescription: nil,
                                                           coordinates: path, cuePoints: []))
        #expect(RouteNarrativeInput(summary: summary, coordinates: path) == nil)
    }

    @Test("a route the same end to end is one section, said once")
    func uniformRouteIsOneSection() throws {
        let input = try input([(20_000, 0)])
        #expect(input.sections.count == 1)
        #expect(input.prompt == """
            Route character: flat.
            The route in sections, in riding order. Write one sentence per section.
            - The whole route: Flat throughout.
            """)
    }

    @Test("a route with no climbs falls back to thirds, merging the ones that read the same")
    func noClimbsIsThirds() throws {
        // Flat for two thirds, then a steady descent: under any categorized climb.
        let input = try input([(20_000, 0), (10_000, -3)])
        #expect(input.sections.map(\.label) == ["From the start until midway", "From late on until the finish"])
        #expect(input.sections.map(RouteNarrativeInput.describe) == ["Flat throughout.", "Descending throughout."])
    }

    @Test("a climb is a section of its own, between the stretches either side of it")
    func climbSplitsTheRoute() throws {
        // Flat 6 km, a 3 km Cat 3 at 6%, flat 21 km: the climb sits at 20–30% of the way.
        let input = try input([(6_000, 0), (3_000, 6), (21_000, 0)])
        #expect(input.sections.count == 3)
        #expect(input.sections.map(\.label) == ["From the start until early on", "Early on", "From early on until the finish"])
        let climb = try #require(climbs(input.sections[1]).first)
        #expect(input.sections[1].parts.count == 1)
        #expect(climb.category == .cat3)
        #expect(!climb.isHardest, "one climb is not the hardest of anything")
        #expect(RouteNarrativeInput.describe(input.sections[1]) == "A Cat 3 climb averaging 6%.")
    }

    @Test("of two climbs, the one with the higher FIETS score is called the hardest")
    func hardestOfSeveral() throws {
        // Descending between them: on a level run `RouteTerrain` would read both as one rise, since
        // a climb only ends at a dip past `climbDipToleranceMeters`.
        let input = try input([(6_000, 0), (3_000, 6), (12_000, -1), (6_000, 7), (13_000, -3)])
        let placed = input.sections.flatMap(climbs)
        #expect(placed.map(\.category) == [.cat3, .cat2])
        #expect(placed.map(\.isHardest) == [false, true])
        #expect(input.prompt.contains("The hardest climb, a Cat 2 averaging 7%."))
    }

    @Test("a stretch under 5% of the route is left out, and the climb runs to the finish")
    func shortStretchIsDropped() throws {
        // A Cat 4 from 7 km, ending 300 m from the finish of a 10 km route: 3% of it.
        let input = try input([(7_000, 0), (2_700, 4), (300, 0)])
        #expect(input.sections.count == 2)
        #expect(input.sections.last?.label == "From late on until the finish")
        #expect(climbs(input.sections[1]).count == 1)
    }

    @Test("more climbs than sentences join into five sections, every climb still there in riding order")
    func manyClimbsFitFiveSections() throws {
        // Six Cat 4s, 2 km at 6% each, 11 km apart.
        let pitches = (0..<6).flatMap { _ in [(meters: 2_000.0, gradePercent: 6.0), (meters: 11_000.0, gradePercent: -1.0)] }
        let input = try input(pitches)
        #expect(input.sections.count == RouteNarrativeInput.maximumSections)
        #expect(input.sections.flatMap(climbs).count == 6)
        // Joined sections keep their parts, so a climb is never folded into a gradient spread.
        #expect(input.sections.allSatisfy { !climbs($0).isEmpty })
        #expect(zip(input.sections, input.sections.dropFirst()).allSatisfy { $0.to == $1.from })
    }

    // MARK: Words

    @Test("a section's position reads as where it starts and where it ends")
    func sectionLabels() {
        func label(_ from: Double, _ to: Double) -> String {
            RouteNarrativeInput.Section(from: from, to: to, parts: []).label
        }
        #expect(label(0, 1) == "The whole route")
        #expect(label(0, 1.0 / 3) == "From the start until early on", "a third ends early on, not midway")
        #expect(label(0.4, 0.5) == "Midway")
        #expect(label(0.5, 0.8) == "From midway until late on")
        #expect(label(0.7, 1) == "From late on until the finish")
        #expect(label(0, 0.03) == "At the start")
    }

    @Test("a gradient spread is put into words without a figure")
    func gradientWords() {
        #expect(RouteNarrativeInput.describe([.flat: 0.95, .gentle: 0.05]) == "flat throughout")
        #expect(RouteNarrativeInput.describe([.flat: 0.6, .steep: 0.3, .descending: 0.1])
                == "mostly flat, with some steep climbing")
        #expect(RouteNarrativeInput.describe([.flat: 0.4, .descending: 0.35, .gentle: 0.25])
                == "mixed: flat, descending and gentle climbing")
        #expect(RouteNarrativeInput.describe([.flat: 0.96, .verySteep: 0.04])
                == "flat throughout, with short very steep rises")
    }

    @Test("a joined section keeps its parts in riding order")
    func joinedSectionReadsInOrder() {
        let climb = RouteNarrativeInput.ClimbPlacement(category: .cat4, averageGradePercent: 6, isHardest: false)
        let section = RouteNarrativeInput.Section(from: 0.2, to: 0.5, parts: [.climb(climb), .stretch([.flat: 1])])
        #expect(RouteNarrativeInput.describe(section) == "A Cat 4 climb averaging 6%, then flat throughout.")
    }

    @Test("grade bands and route positions put each edge in the later band")
    func bandEdges() {
        #expect(GradeBand(-2.01) == .descending)
        #expect(GradeBand(-2) == .flat)
        #expect(GradeBand(2) == .gentle)
        #expect(GradeBand(5) == .steep)
        #expect(GradeBand(8) == .verySteep)
        #expect(RoutePosition(fraction: 0.049) == .start)
        #expect(RoutePosition(fraction: 1.0 / 3) == .midway)
        #expect(RoutePosition(fraction: 0.95) == .finish)
    }

    // MARK: Answer

    @Test("the model's sentences are tidied into one paragraph")
    func sentencesAreTidied() {
        #expect(RouteNarrative.paragraph(["the road starts level .", "  Then it climbs hard", "What a finish!"])
                == "The road starts level. Then it climbs hard. What a finish!")
    }

    @Test("an empty sentence, or a count outside one to five, is rejected")
    func sentenceCountIsHeld() {
        #expect(RouteNarrative.paragraph([]) == nil)
        #expect(RouteNarrative.paragraph(["The road is level.", " "]) == nil)
        #expect(RouteNarrative.paragraph(Array(repeating: "The road is level.", count: 6)) == nil)
    }

    @Test("text quoting a figure or a unit is rejected, so it can't contradict the rows beside it",
          arguments: [
            "The road climbs for 3 miles.",
            "A steady eight percent, or 8%.",
            "It rises a few hundred metres.",
            "It rises a few hundred meters.",
            "A km of climbing.",
            "The last mile is steep.",
            "Gains a hundred ft.",
            "It gains a hundred feet.",
            "Up a hundred m before the top.",
          ])
    func figuresAreRejected(_ text: String) {
        #expect(RouteNarrative.validated(text) == nil)
    }

    @Test("ordinary words that contain a unit's letters are kept",
          arguments: ["I'm sure the climb will hurt.", "A smooth, demanding road to the summit.", "Midway it climbs."])
    func wordsAreKept(_ text: String) {
        #expect(RouteNarrative.validated(text) == text)
    }

    @Test("a paragraph past the length cap is rejected")
    func overlongIsRejected() {
        let sentence = String(repeating: "a", count: RouteNarrative.maximumLength / 5)
        #expect(RouteNarrative.paragraph(Array(repeating: sentence, count: 5)) == nil)
        #expect(RouteNarrative.validated(String(repeating: "a", count: RouteNarrative.maximumLength)) != nil)
    }
}
