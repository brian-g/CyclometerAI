import Testing
import AVFoundation
@testable import Cyclometer

// MARK: - Duration fidelity

@Suite("ToneRenderer — duration fidelity")
struct ToneRendererDurationTests {

    @Test("All Clear renders ~680ms of samples (300 + 80 + 300)")
    func allClearDuration() {
        let buffer = ToneRenderer.render(ToneKind.allClear.segments)
        #expect(approxMilliseconds(buffer) == 680)
    }

    @Test("Warning renders ~480ms of samples (180 + 120 + 180)")
    func warningDuration() {
        let buffer = ToneRenderer.render(ToneKind.warning.segments)
        #expect(approxMilliseconds(buffer) == 480)
    }

    @Test("Danger renders one 580ms triple-burst cycle (140 + 80 + 140 + 80 + 140) — no inter-burst pause or repeat baked in")
    func dangerDuration() {
        let buffer = ToneRenderer.render(ToneKind.danger.segments)
        #expect(approxMilliseconds(buffer) == 580)
    }

    @Test("Turn Left and Turn Right each render 500ms (90 + 40 + 90 + 40 + 240)")
    func turnDurations() {
        #expect(approxMilliseconds(ToneRenderer.render(ToneKind.turnLeft.segments)) == 500)
        #expect(approxMilliseconds(ToneRenderer.render(ToneKind.turnRight.segments)) == 500)
    }

    @Test("U-turn renders 760ms (four 90ms notes, four 40ms gaps, a 240ms last note)")
    func uTurnDuration() {
        #expect(approxMilliseconds(ToneRenderer.render(ToneKind.uTurn.segments)) == 760)
    }

    private func approxMilliseconds(_ buffer: AVAudioPCMBuffer) -> Int {
        Int((Double(buffer.frameLength) / ToneRenderer.sampleRate) * 1_000)
    }
}

// MARK: - Frequency fidelity

@Suite("ToneRenderer — frequency fidelity (via zero-crossing count)")
struct ToneRendererFrequencyTests {

    @Test("Sine at 880 Hz over 100ms crosses zero the expected number of times")
    func sineZeroCrossings() {
        let segment = ToneSegment.tone(freq: 880, ms: 100, waveform: .sine, attackMs: 0, decayMs: 0)
        let buffer = ToneRenderer.render([segment])
        // 880 Hz over 0.1s = 88 cycles = 176 zero crossings.
        #expect(abs(zeroCrossings(buffer) - 176) <= 2)
    }

    @Test("Square at 2,100 Hz over 100ms crosses zero the expected number of times")
    func squareZeroCrossings() {
        let segment = ToneSegment.tone(freq: 2_100, ms: 100, waveform: .square, attackMs: 0, decayMs: 0)
        let buffer = ToneRenderer.render([segment])
        // 2,100 Hz over 0.1s = 210 cycles = 420 zero crossings.
        #expect(abs(zeroCrossings(buffer) - 420) <= 2)
    }

    private func zeroCrossings(_ buffer: AVAudioPCMBuffer) -> Int {
        let channel = buffer.floatChannelData![0]
        var count = 0
        for i in 1..<Int(buffer.frameLength) {
            if (channel[i - 1] < 0) != (channel[i] < 0) { count += 1 }
        }
        return count
    }
}

// MARK: - Silence segments

@Suite("ToneRenderer — silence segments")
struct ToneRendererSilenceTests {

    @Test("Silence segment renders all-zero samples")
    func silenceIsZero() {
        let buffer = ToneRenderer.render([.silence(ms: 50)])
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) {
            #expect(channel[i] == 0)
        }
    }
}

// MARK: - Turn tones (#198)

@Suite("ToneKind — turn tones")
struct ToneKindTurnTests {

    @Test("A tone's duration is its segments' — the Warning's 480ms is what holds a turn tone back")
    func durationSumsTheSegments() {
        #expect(ToneKind.warning.duration == 0.48)
        #expect(ToneKind.uTurn.duration == 0.76)
    }

    @Test("No two tones are the same sequence of notes")
    func everyToneIsDistinct() {
        let kinds = ToneKind.allCases
        for (index, kind) in kinds.enumerated() {
            for other in kinds[(index + 1)...] {
                #expect(signature(kind) != signature(other), "\(kind) and \(other)")
            }
        }
    }

    @Test("Right rises, left falls, and left is right reversed — the contour alone carries the side")
    func contourCarriesTheSide() {
        let right = pitches(.turnRight)
        #expect(zip(right, right.dropFirst()).allSatisfy { $0 < $1 })
        #expect(pitches(.turnLeft) == Array(right.reversed()))
        #expect(rhythm(.turnLeft) == rhythm(.turnRight))
    }

    @Test("A U-turn goes up and comes back down to where it started")
    func uTurnGoesUpAndBack() throws {
        let notes = pitches(.uTurn)
        let top = try #require(notes.max())
        let peak = try #require(notes.firstIndex(of: top))
        try #require(peak > 0 && peak < notes.count - 1, "the top note is neither the first nor the last")
        #expect(zip(notes[..<peak], notes[1...peak]).allSatisfy { $0 < $1 })
        #expect(zip(notes[peak...], notes[(peak + 1)...]).allSatisfy { $0 > $1 })
        #expect(notes.first == notes.last)
    }

    @Test("Turn tones sit in the 1–4 kHz band, and share no pitch with Warning or Danger")
    func turnPitchesStayClearOfTheRadarTones() {
        let radar = Set(pitches(.warning) + pitches(.danger))
        for kind in [ToneKind.turnLeft, .turnRight, .uTurn] {
            for pitch in pitches(kind) {
                #expect((1_000...4_000).contains(pitch), "\(kind) at \(pitch) Hz")
                #expect(!radar.contains(pitch), "\(kind) at \(pitch) Hz")
            }
        }
    }

    @Test("Every maneuver has a tone: a slight turn is its side's, a U-turn its own")
    func everyManeuverHasATone() {
        for direction in Maneuver.Direction.allCases {
            let expected: ToneKind = direction == .uTurn ? .uTurn : direction.isLeft ? .turnLeft : .turnRight
            #expect(ToneKind(turn: direction) == expected, "\(direction)")
        }
    }

    /// What a listener hears, segment by segment: pitch, waveform and length, or a rest.
    private func signature(_ kind: ToneKind) -> [String] {
        kind.segments.map { segment in
            switch segment.kind {
            case .tone(let frequency, let waveform, _, _, _): "\(frequency) Hz \(waveform) \(segment.durationMs) ms"
            case .silence: "rest \(segment.durationMs) ms"
            }
        }
    }

    private func pitches(_ kind: ToneKind) -> [Double] {
        kind.segments.compactMap { segment -> Double? in
            guard case .tone(let frequency, _, _, _, _) = segment.kind else { return nil }
            return frequency
        }
    }

    private func rhythm(_ kind: ToneKind) -> [Double] {
        kind.segments.map(\.durationMs)
    }
}
