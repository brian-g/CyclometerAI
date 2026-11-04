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

    @Test("Bell renders 1,050ms: two flicks and the ring-out")
    func bellDuration() {
        #expect(approxMilliseconds(ToneRenderer.render(ToneKind.bell.segments)) == 1_050)
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

    @Test("Only a turn tone or the bell gives way, and only to a sounding Warning or Danger — radar keeps the speaker")
    func onlyATurnToneOrTheBellGivesWay() {
        let yielding: [ToneKind] = [.turnLeft, .turnRight, .uTurn, .bell]
        for kind in ToneKind.allCases {
            let givesWayTo = ToneKind.allCases.filter { kind.yields(to: $0) }
            #expect(givesWayTo == (yielding.contains(kind) ? [.warning, .danger] : []), "\(kind)")
        }
    }

    /// What a listener hears, segment by segment: pitch, waveform and length, or a rest.
    private func signature(_ kind: ToneKind) -> [String] {
        kind.segments.map { segment in
            switch segment.kind {
            case .tone(let frequency, let waveform, _, _, _): "\(frequency) Hz \(waveform) \(segment.durationMs) ms"
            case .silence: "rest \(segment.durationMs) ms"
            case .ring(let fundamental, _, let strikes): "ring \(fundamental) Hz \(strikes.count) strikes \(segment.durationMs) ms"
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

// MARK: - Bell (#492)

@Suite("ToneKind — bell (#492)")
struct ToneKindBellTests {

    private let buffer = ToneRenderer.render(ToneKind.bell.segments)

    @Test("Strikes piling up never clip: the ring is scaled to its peak")
    func peakIsScaledNotClipped() {
        let channel = buffer.floatChannelData![0]
        let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(channel[$1])) }
        #expect(abs(peak - ToneRenderer.ringPeak) < 0.001)
    }

    @Test("It starts and ends at silence — no click on either side")
    func startsAndEndsSilent() {
        let channel = buffer.floatChannelData![0]
        #expect(abs(channel[0]) < 0.01)
        #expect(abs(channel[Int(buffer.frameLength) - 1]) < 0.01)
    }

    @Test("Two rings, not one: the bell dips between the flicks")
    func dipsBetweenTheFlicks() {
        let firstFlick = rms(220..<280), gap = rms(390..<450), secondFlick = rms(670..<730)
        #expect(gap < 0.75 * firstFlick)
        #expect(gap < 0.75 * secondFlick)
    }

    @Test("Its fundamental sits in Audio.md's 1–4 kHz band")
    func fundamentalIsAudibleOutdoors() throws {
        let segment = try #require(ToneKind.bell.segments.first)
        guard case .ring(let fundamental, _, _) = segment.kind else {
            Issue.record("the bell is not a ring")
            return
        }
        #expect((1_000...4_000).contains(fundamental))
    }

    /// Root mean square of the samples between `ms`, in milliseconds from the start.
    private func rms(_ ms: Range<Int>) -> Float {
        let channel = buffer.floatChannelData![0]
        let frames = Int(Double(ms.lowerBound) * ToneRenderer.sampleRate / 1_000)..<Int(Double(ms.upperBound) * ToneRenderer.sampleRate / 1_000)
        let sum = frames.reduce(Float(0)) { $0 + channel[$1] * channel[$1] }
        return (sum / Float(frames.count)).squareRoot()
    }
}

// MARK: - Background audio

@Suite("Tones while backgrounded")
struct ToneBackgroundModeTests {
    /// Without the `audio` background mode a locked phone can't start a tone at all. It was dropped from
    /// Info.plist once without anyone noticing (#329), and the 2026-11-03 ride lost every radar tone while
    /// backgrounded (BLE.md §13.2 Q4). The test host is the app, so `Bundle.main` is its Info.plist.
    @Test("The app declares the audio background mode")
    func declaresAudioBackgroundMode() throws {
        let modes = try #require(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        #expect(modes.contains("audio"))
    }
}
