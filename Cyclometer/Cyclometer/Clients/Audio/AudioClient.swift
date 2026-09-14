import ComposableArchitecture
import AVFoundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "com.xavier.cyclometer".
private let logger = Logger(subsystem: "com.xavier.cyclometer", category: "audio")

/// TCA dependency for the app's synthesized tones (per Audio.md spec): the three radar safety
/// alerts, and the turn tones navigation announces (#198).
///
///   L0 All Clear : 880→587 Hz sine, descending, ~680 ms — jersey-pocket audible
///   L2 Warning   : 1,400 Hz triangle, double staccato pulse, ~480 ms
///   L3 Danger    : 2,100 Hz square, triple burst, ~580 ms — overrides Silent Mode (user opt-in, unwired in MVP)
///   Turns        : C6–E6–G♯6 triangle — rising for right, falling for left, up and back for a U-turn
struct AudioClient {
    var playAllClear:           @Sendable () async -> Void
    var playWarning:            @Sendable () async -> Void
    var playDanger:              @Sendable () async -> Void
    /// Its own closure, not a case of the safety tones': a setting that silences radar warnings
    /// must not silence turns with them (#198).
    var playTurn:               @Sendable (Maneuver.Direction) async -> Void
    var setOverridesSilentMode: @Sendable (Bool) async -> Void
}

extension AudioClient: DependencyKey {
    static let liveValue: AudioClient = {
        let state = AudioEngineState()
        return AudioClient(
            playAllClear:           { await state.play(.allClear) },
            playWarning:            { await state.play(.warning) },
            playDanger:              { await state.play(.danger) },
            playTurn:               { direction in await state.play(ToneKind(turn: direction)) },
            setOverridesSilentMode: { enabled in state.setOverridesSilentMode(enabled) }
        )
    }()

    static let testValue = AudioClient(
        playAllClear:           { },
        playWarning:            { },
        playDanger:              { },
        playTurn:               { _ in },
        setOverridesSilentMode: { _ in }
    )
}

extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}

// MARK: - Tone Synthesis (pure — no engine/session state, unit-testable)

/// One tone's identity. The radar alerts are the escalation levels `AlertOrchestratorFeature`
/// drives — no case for L1 advisory: Audio.md specifies haptic-only for L1, no tone. The turn
/// tones are navigation's (#198), and stand for no alert level.
enum ToneKind: CaseIterable, Sendable {
    case allClear, warning, danger
    case turnLeft, turnRight, uTurn

    /// The tone for a turn. A slight turn is still a turn to its side: the rider needs the side,
    /// and the turn instruction's arrow says how sharp. A U-turn has no side to give — at 180° the
    /// sign of the heading change is noise — so it has a tone of its own.
    init(turn direction: Maneuver.Direction) {
        switch direction {
        case .slightLeft, .left: self = .turnLeft
        case .slightRight, .right: self = .turnRight
        case .uTurn: self = .uTurn
        }
    }

    /// Fraction of system volume (Audio.md's per-tone volume spec). A scalar multiplier
    /// on top of whatever the system output level already is — never boosts past it.
    var volume: Float {
        switch self {
        case .allClear: 0.6
        case .warning:  0.8
        case .danger:   1.0
        // Warning's, not All Clear's: a turn tone missed at speed is a missed turn. All Clear
        // alone is quieter, because it asks nothing of the rider.
        case .turnLeft, .turnRight, .uTurn: 0.8
        }
    }

    /// How long the tone sounds, start to finish.
    var duration: TimeInterval {
        segments.reduce(0) { $0 + $1.durationMs } / 1_000
    }

    /// Whether this tone, started while `sounding` is still sounding, gives way rather than cut it
    /// off. Only a turn tone does, and only to a Warning or a Danger: radar keeps the speaker
    /// (#198). Every other tone cuts off whatever is sounding — Audio.md: tones are interruptible.
    func yields(to sounding: ToneKind) -> Bool {
        switch self {
        case .allClear, .warning, .danger: false
        case .turnLeft, .turnRight, .uTurn: sounding == .warning || sounding == .danger
        }
    }

    /// Audio.md's exact segment breakdown for this tone. `playDanger()` renders one
    /// 580ms triple-burst cycle only — the 800ms inter-burst pause and "repeat
    /// continuously until level drops" behavior belong to `AlertOrchestratorFeature`,
    /// via a cancellable repeating Effect, not this client. Same reasoning for
    /// Warning's "minimum 3s before re-trigger" — that's the orchestrator's guard.
    var segments: [ToneSegment] {
        switch self {
        case .allClear:
            // Two descending notes, A5 → D5 (minor third down) — "going down" reads as
            // de-escalation. Gentle exponential decay per Audio.md, distinct from the
            // linear decay used for Warning/Danger's plain "fast decay" spec.
            [
                .tone(freq: 880, ms: 300, waveform: .sine, attackMs: 20, decayMs: 60, decayShape: .exponential),
                .silence(ms: 80),
                .tone(freq: 587, ms: 300, waveform: .sine, attackMs: 20, decayMs: 60, decayShape: .exponential)
            ]
        case .warning:
            [
                .tone(freq: 1_400, ms: 180, waveform: .triangle, attackMs: 5, decayMs: 20),
                .silence(ms: 120),
                .tone(freq: 1_400, ms: 180, waveform: .triangle, attackMs: 5, decayMs: 20)
            ]
        case .danger:
            [
                .tone(freq: 2_100, ms: 140, waveform: .square, attackMs: 1, decayMs: 10),
                .silence(ms: 80),
                .tone(freq: 2_100, ms: 140, waveform: .square, attackMs: 1, decayMs: 10),
                .silence(ms: 80),
                .tone(freq: 2_100, ms: 140, waveform: .square, attackMs: 1, decayMs: 10)
            ]
        // One pitch set, the C6 augmented triad, so that the contour alone says which way (#198):
        // rising for right — listeners hear higher as further right — and falling for left.
        case .turnRight:
            Self.turnFigure(1_047, 1_319, 1_661)
        case .turnLeft:
            Self.turnFigure(1_661, 1_319, 1_047)
        case .uTurn:
            // Up, and back down: out, and round.
            Self.turnFigure(1_047, 1_319, 1_661, 1_319, 1_047)
        }
    }

    /// A turn tone: quick notes stepping through `frequencies`, the last one held — where the figure
    /// lands, and so the note that says which way it went. Triangle for presence in wind, as Warning,
    /// on pitches neither Warning nor Danger uses, so that no part of a turn tone can pass for a
    /// radar pulse.
    private static func turnFigure(_ frequencies: Double...) -> [ToneSegment] {
        var segments: [ToneSegment] = []
        for (index, frequency) in frequencies.enumerated() {
            if index > 0 { segments.append(.silence(ms: 40)) }
            segments.append(
                index == frequencies.count - 1
                    ? .tone(freq: frequency, ms: 240, waveform: .triangle, attackMs: 5, decayMs: 60, decayShape: .exponential)
                    : .tone(freq: frequency, ms: 90, waveform: .triangle, attackMs: 5, decayMs: 20)
            )
        }
        return segments
    }
}

enum Waveform: Sendable {
    case sine, triangle, square

    /// -1...1 at time `t` (seconds) for a tone at `frequency` Hz.
    func sample(frequency: Double, t: Double) -> Double {
        let phase = frequency * t
        switch self {
        case .sine:
            return sin(2 * .pi * phase)
        case .triangle:
            // Phase-aligned with sine (same zero crossings) via 2/π·asin(sin(x)).
            return (2 / Double.pi) * asin(sin(2 * .pi * phase))
        case .square:
            return sin(2 * .pi * phase) >= 0 ? 1 : -1
        }
    }
}

enum DecayShape: Sendable { case linear, exponential }

struct ToneSegment: Sendable {
    enum Kind: Sendable {
        case tone(frequency: Double, waveform: Waveform, attackMs: Double, decayMs: Double, decayShape: DecayShape)
        case silence
    }
    let kind: Kind
    let durationMs: Double

    static func tone(
        freq: Double, ms: Double, waveform: Waveform,
        attackMs: Double, decayMs: Double, decayShape: DecayShape = .linear
    ) -> ToneSegment {
        ToneSegment(kind: .tone(frequency: freq, waveform: waveform, attackMs: attackMs, decayMs: decayMs, decayShape: decayShape), durationMs: ms)
    }

    static func silence(ms: Double) -> ToneSegment {
        ToneSegment(kind: .silence, durationMs: ms)
    }

    func frameCount(sampleRate: Double) -> Int {
        Int((durationMs / 1_000) * sampleRate)
    }
}

/// Renders a tone's segments to a mono PCM buffer. Pure function — no I/O, no shared
/// state — so it's testable without an audio session or hardware (see
/// `AudioToneRendererTests`).
enum ToneRenderer {
    static let sampleRate: Double = 44_100

    static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    static func render(_ segments: [ToneSegment]) -> AVAudioPCMBuffer {
        let totalFrames = segments.reduce(0) { $0 + $1.frameCount(sampleRate: sampleRate) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let channel = buffer.floatChannelData![0]

        var offset = 0
        for segment in segments {
            let frameCount = segment.frameCount(sampleRate: sampleRate)
            switch segment.kind {
            case .silence:
                for i in 0..<frameCount { channel[offset + i] = 0 }
            case .tone(let frequency, let waveform, let attackMs, let decayMs, let decayShape):
                let attackFrames = Int((attackMs / 1_000) * sampleRate)
                let decayFrames = Int((decayMs / 1_000) * sampleRate)
                for i in 0..<frameCount {
                    let t = Double(i) / sampleRate
                    let raw = waveform.sample(frequency: frequency, t: t)
                    let envelope = envelope(
                        at: i, frameCount: frameCount,
                        attackFrames: attackFrames, decayFrames: decayFrames, shape: decayShape
                    )
                    channel[offset + i] = Float(raw * envelope)
                }
            }
            offset += frameCount
        }
        return buffer
    }

    private static func envelope(at i: Int, frameCount: Int, attackFrames: Int, decayFrames: Int, shape: DecayShape) -> Double {
        if i < attackFrames {
            return Double(i) / Double(max(attackFrames, 1))
        }
        let decayStart = frameCount - decayFrames
        if i >= decayStart {
            let progress = Double(i - decayStart) / Double(max(decayFrames, 1))
            return shape == .exponential ? exp(-5.0 * progress) : (1.0 - progress)
        }
        return 1.0
    }
}

// MARK: - Live Engine/Session State

/// Owns the one `AVAudioEngine`/`AVAudioPlayerNode` pair for the app's lifetime and the
/// `AVAudioSession` routing decision. Follows the same `@unchecked Sendable` + `NSLock`
/// pattern as `BLECentral` / `RadarClientState` — engine attach/connect happens lazily
/// on first play, not at construction.
private final class AudioEngineState: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var cachedBuffers: [ToneKind: AVAudioPCMBuffer] = [:]
    /// Never set to `true` in MVP — UX.md §S12 resolved "Silent Mode override toggle:
    /// not a setting at this time," so nothing calls `setOverridesSilentMode`. The
    /// plumbing stays in case a later milestone reintroduces the row.
    private var silentModeOverrideEnabled = false
    /// The last tone started, and when it stops sounding. A deadline, not a flag the completion
    /// callback clears: `stop()` runs under `lock` and may fire that callback before returning,
    /// and `NSLock` isn't recursive.
    private var sounding: (kind: ToneKind, until: ContinuousClock.Instant)?
    private let lock = NSLock()

    func setOverridesSilentMode(_ enabled: Bool) {
        lock.withLock { silentModeOverrideEnabled = enabled }
    }

    func play(_ kind: ToneKind) async {
        let buffer = lock.withLock { () -> AVAudioPCMBuffer in
            if let cached = cachedBuffers[kind] { return cached }
            let rendered = ToneRenderer.render(kind.segments)
            cachedBuffers[kind] = rendered
            return rendered
        }
        let overrideSilentMode = lock.withLock { silentModeOverrideEnabled }

        do {
            try configureSession(for: kind, overrideSilentMode: overrideSilentMode)
            try ensureEngineRunning()
        } catch {
            logger.error("audio session/engine setup failed for \(String(describing: kind)): \(error)")
            return
        }

        // Tones are interruptible (Audio.md acceptance criteria) — a new tone takes
        // priority over whatever is currently scheduled/sounding, except that a turn tone
        // never cuts off a sounding Warning or Danger (`ToneKind.yields(to:)`, #198). Two
        // overlapping `play()` calls (e.g. a fast caution→danger escalation, or a turn
        // announced as radar escalates) can each reach this point concurrently, in either
        // order, so that check, the volume and the stop/scheduleBuffer/play triple run
        // under `lock` — otherwise two tasks' calls can interleave on the shared node with
        // no ordering guarantee. Only the completion await sits outside the lock: an
        // interrupted call's `stop()` fires the *previous* call's completion callback,
        // so that call's wait resolves promptly rather than blocking the tone that just
        // preempted it.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let heldBy = lock.withLock { () -> ToneKind? in
                let now = ContinuousClock.now
                if let sounding, now < sounding.until, kind.yields(to: sounding.kind) {
                    return sounding.kind
                }
                player.volume = kind.volume
                player.stop()
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                    continuation.resume()
                }
                player.play()
                sounding = (kind: kind, until: now + .seconds(kind.duration))
                return nil
            }
            if let heldBy {
                logger.notice("\(String(describing: kind), privacy: .public) held — \(String(describing: heldBy), privacy: .public) sounding")
                continuation.resume()
            }
        }
    }

    private func configureSession(for kind: ToneKind, overrideSilentMode: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if kind == .danger, overrideSilentMode {
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
        } else {
            // .ambient respects the Ring/Silent switch — the default for every tone,
            // and for Danger too unless the (currently unreachable) override is on.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        }
    }

    private func ensureEngineRunning() throws {
        if engine.attachedNodes.isEmpty {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: ToneRenderer.format)
        }
        if !engine.isRunning {
            try engine.start()
        }
    }
}
