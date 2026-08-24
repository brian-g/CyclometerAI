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
