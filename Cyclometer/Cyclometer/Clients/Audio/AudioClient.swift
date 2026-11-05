import ComposableArchitecture
import AVFoundation
import os

// Stream live: Console.app / Xcode console, filter subsystem "xyz.acmeapps.ride".
private let logger = Logger.cyclometer(.audio)

/// TCA dependency for the app's synthesized tones (per Audio.md spec): the three radar safety
/// alerts, the turn tones navigation announces (#198), and the rider's bell (#492).
///
///   L0 All Clear : 880→587 Hz sine, descending, ~680 ms — jersey-pocket audible
///   L2 Warning   : 1,400 Hz triangle, double staccato pulse, ~480 ms
///   L3 Danger    : 2,100 Hz square, triple burst, ~580 ms — ducks music to the speaker (user opt-in, unwired in MVP)
///   Turns        : C6–E6–G♯6 triangle — rising for right, falling for left, up and back for a U-turn
///   Bell         : a rotary bicycle bell, brrring-brrring, ~1 s
///
/// Every tone rings through the Ring/Silent switch and with the screen locked (`configureSession`).
struct AudioClient {
    var playAllClear:           @Sendable () async -> Void
    var playWarning:            @Sendable () async -> Void
    var playDanger:              @Sendable () async -> Void
    /// Its own closure, not a case of the safety tones': a setting that silences radar warnings
    /// must not silence turns with them (#198).
    var playTurn:               @Sendable (Maneuver.Direction) async -> Void
    /// The toolbar's Bell button (#492). For the people ahead of the rider, not the rider.
    var playBell:               @Sendable () async -> Void
    var setOverridesSilentMode: @Sendable (Bool) async -> Void
    /// The ride is over: stop the engine and give up the session. With the `audio` background mode
    /// a running engine keeps iOS from suspending the app, so leaving it up after the ride would
    /// hold the app awake in the background until it is killed. The next tone starts it again.
    var stop:                   @Sendable () async -> Void
}

extension AudioClient: DependencyKey {
    static let liveValue: AudioClient = {
        let state = AudioEngineState()
        return AudioClient(
            playAllClear:           { await state.play(.allClear) },
            playWarning:            { await state.play(.warning) },
            playDanger:              { await state.play(.danger) },
            playTurn:               { direction in await state.play(ToneKind(turn: direction)) },
            playBell:               { await state.play(.bell) },
            setOverridesSilentMode: { enabled in state.setOverridesSilentMode(enabled) },
            stop:                   { state.stop() }
        )
    }()

    static let testValue = AudioClient(
        playAllClear:           { },
        playWarning:            { },
        playDanger:              { },
        playTurn:               { _ in },
        playBell:               { },
        setOverridesSilentMode: { _ in },
        stop:                   { }
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
/// tones are navigation's (#198), and stand for no alert level. The bell is the rider's (#492).
enum ToneKind: CaseIterable, Sendable {
    case allClear, warning, danger
    case turnLeft, turnRight, uTurn
    case bell

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
        // Full: it is for the people ahead, who aren't listening for it.
        case .bell: 1.0
        }
    }

    /// How long the tone sounds, start to finish.
    var duration: TimeInterval {
        segments.reduce(0) { $0 + $1.durationMs } / 1_000
    }

    /// Whether this tone, started while `sounding` is still sounding, gives way rather than cut it
    /// off. Only a turn tone or the bell does, and only to a Warning or a Danger: radar keeps the
    /// speaker (#198, #492). Every other tone cuts off whatever is sounding — Audio.md: tones are
    /// interruptible — and so does a bell rung over a turn tone, or over another bell.
    func yields(to sounding: ToneKind) -> Bool {
        switch self {
        case .allClear, .warning, .danger: false
        case .turnLeft, .turnRight, .uTurn, .bell: sounding == .warning || sounding == .danger
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
        case .bell:
            [Self.rotaryBell]
        }
    }

    /// A rotary bicycle bell (#492): a thumb flick spins two hammers against a thin steel dome,
    /// which clatter on it about 25 times a second. Two flicks are the brrring-brrring. The dome
    /// keeps ringing through the clatter and between the flicks, so this is one `.ring` — the
    /// strikes overlap — rather than notes and rests.
    ///
    /// The dome's modes are inharmonic, as a struck plate's are, around a 1.7 kHz fundamental
    /// inside Audio.md's 1–4 kHz band; the higher modes are quieter and die sooner, so the clatter
    /// is bright and the ring-out mellow. A second fundamental 4 Hz above the first beats against
    /// it — the shimmer of a real bell, whose dome is never perfectly round.
    private static let rotaryBell: ToneSegment = {
        // A flick's hammer hits: unevenly spaced around 40 ms, and softening as the spin slows.
        // Fixed, not random, so the bell sounds the same every time and tests can pin it.
        let flick: [(ms: Double, strength: Double)] = [
            (0, 1.0), (37, 0.85), (81, 0.95), (118, 0.8), (160, 0.85), (197, 0.7), (241, 0.75), (279, 0.6)
        ]
        let flickStarts: [Double] = [0, 450]
        return .ring(
            fundamental: 1_700,
            partials: [
                BellPartial(ratio: 1.0, amplitude: 1.0, decayMs: 150),
                BellPartial(ratio: 1.0024, amplitude: 0.6, decayMs: 150),
                BellPartial(ratio: 2.32, amplitude: 0.5, decayMs: 100),
                BellPartial(ratio: 4.25, amplitude: 0.25, decayMs: 60),
                BellPartial(ratio: 6.63, amplitude: 0.12, decayMs: 35)
            ],
            strikes: flickStarts.flatMap { start in
                flick.map { BellStrike(atMs: start + $0.ms, strength: $0.strength) }
            },
            ms: 1_050
        )
    }()

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

/// One mode of a struck bell: its pitch as a multiple of the fundamental, how loud a strike makes
/// it, and its decay time constant — the time it takes to fall to 1/e (about −9 dB).
struct BellPartial: Sendable {
    let ratio: Double
    let amplitude: Double
    let decayMs: Double
}

/// One hammer hit on a bell, `atMs` from the start of its `.ring` segment.
struct BellStrike: Sendable {
    let atMs: Double
    let strength: Double
}

struct ToneSegment: Sendable {
    enum Kind: Sendable {
        case tone(frequency: Double, waveform: Waveform, attackMs: Double, decayMs: Double, decayShape: DecayShape)
        case silence
        /// A struck bell (#492): every partial rings from each strike and decays on its own,
        /// and a strike adds to whatever is still ringing.
        case ring(fundamental: Double, partials: [BellPartial], strikes: [BellStrike])
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

    static func ring(fundamental: Double, partials: [BellPartial], strikes: [BellStrike], ms: Double) -> ToneSegment {
        ToneSegment(kind: .ring(fundamental: fundamental, partials: partials, strikes: strikes), durationMs: ms)
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
            case .ring(let fundamental, let partials, let strikes):
                let samples = ring(fundamental: fundamental, partials: partials, strikes: strikes, frameCount: frameCount)
                for i in 0..<frameCount { channel[offset + i] = samples[i] }
            }
            offset += frameCount
        }
        return buffer
    }

    /// How long a bell strike takes to reach full strength: long enough not to click, short
    /// enough to stay a hit.
    static let ringAttackMs: Double = 1
    /// The fade over a `.ring`'s last stretch, so the ring-out ends at silence rather than a cut.
    static let ringFadeMs: Double = 120
    /// A `.ring`'s loudest sample. Strikes pile up while the bell still rings, so the sum is
    /// scaled to this rather than left to clip.
    static let ringPeak: Float = 0.9

    /// Each partial's envelope runs as a one-pole decay, `e = e·d + drive`, so a strike adds to
    /// what is still ringing and the cost is one multiply per partial per frame — the bell renders
    /// on the first tap, which must not wait. A strike's drive is spread over `ringAttackMs`.
    private static func ring(fundamental: Double, partials: [BellPartial], strikes: [BellStrike], frameCount: Int) -> [Float] {
        let attackFrames = max(Int((ringAttackMs / 1_000) * sampleRate), 1)
        var drive = [Double](repeating: 0, count: frameCount)
        for strike in strikes {
            let start = Int((strike.atMs / 1_000) * sampleRate)
            for i in start..<min(start + attackFrames, frameCount) {
                drive[i] += strike.strength / Double(attackFrames)
            }
        }

        var mixed = [Double](repeating: 0, count: frameCount)
        for partial in partials {
            let frequency = fundamental * partial.ratio
            let decayPerFrame = exp(-1 / ((partial.decayMs / 1_000) * sampleRate))
            var envelope = 0.0
            for i in 0..<frameCount {
                envelope = envelope * decayPerFrame + drive[i]
                mixed[i] += partial.amplitude * envelope * sin(2 * .pi * frequency * Double(i) / sampleRate)
            }
        }

        let fadeFrames = min(Int((ringFadeMs / 1_000) * sampleRate), frameCount)
        for i in (frameCount - fadeFrames)..<frameCount {
            mixed[i] *= Double(frameCount - 1 - i) / Double(max(fadeFrames - 1, 1))
        }
        let peak = mixed.reduce(0) { max($0, abs($1)) }
        let scale = peak > 0 ? Double(ringPeak) / peak : 0
        return mixed.map { Float($0 * scale) }
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

    /// Under `lock`, so a tone starting concurrently either finishes its setup first and is cut
    /// off here, or starts after and brings the engine and session back up. `player.stop()` fires a
    /// sounding tone's completion, which only resumes its `play` call. The engine goes before the
    /// session: deactivating a session with running I/O fails.
    func stop() {
        lock.withLock {
            player.stop()
            sounding = nil
            engine.stop()
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                logger.error("deactivating the audio session failed: \(error)")
            }
        }
    }

    func play(_ kind: ToneKind) async {
        let buffer = lock.withLock { () -> AVAudioPCMBuffer in
            if let cached = cachedBuffers[kind] { return cached }
            let rendered = ToneRenderer.render(kind.segments)
            cachedBuffers[kind] = rendered
            return rendered
        }

        // Tones are interruptible (Audio.md acceptance criteria) — a new tone takes
        // priority over whatever is currently scheduled/sounding, except that a turn tone
        // never cuts off a sounding Warning or Danger (`ToneKind.yields(to:)`, #198). Two
        // overlapping `play()` calls (e.g. a fast caution→danger escalation, or a turn
        // announced as radar escalates) can each reach this point concurrently, in either
        // order, so that check, the volume and the stop/play/scheduleBuffer triple run
        // under `lock` — otherwise two tasks' calls can interleave on the shared node with
        // no ordering guarantee. Only the completion await sits outside the lock: an
        // interrupted call's `stop()` fires the *previous* call's completion callback,
        // so that call's wait resolves promptly rather than blocking the tone that just
        // preempted it.
        //
        // `playAudio()` comes before `scheduleBuffer`, because since iOS 27 starting the node
        // can throw. Had the buffer already been scheduled, its completion (this call's resume)
        // would fire at some later `stop()`, so the catch couldn't resume without resuming
        // twice. Started first, a failure leaves nothing scheduled, and the catch resumes
        // exactly once. `sounding` is cleared after `stop()`, which has silenced it, so a
        // failed start doesn't leave a turn tone yielding to a Warning that isn't sounding.
        //
        // The session and engine are set up under `lock` too, after the hold check. The session's
        // options are per tone — an overriding Danger ducks the music and takes the speaker — so
        // they are shared state like the node. Set before the check, a held tone would change a
        // sounding one's options; set outside the lock, a concurrent tone's options could land
        // between another tone's setup and its start.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let heldBy: ToneKind?
            do {
                heldBy = try lock.withLock { () throws -> ToneKind? in
                    if let sounding, ContinuousClock.now < sounding.until, kind.yields(to: sounding.kind) {
                        return sounding.kind
                    }
                    try configureSession(for: kind, overrideSilentMode: silentModeOverrideEnabled)
                    try ensureEngineRunning()
                    player.volume = kind.volume
                    player.stop()
                    sounding = nil
                    try player.playAudio()
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                        continuation.resume()
                    }
                    sounding = (kind: kind, until: ContinuousClock.now + .seconds(kind.duration))
                    return nil
                }
            } catch {
                logger.error("\(String(describing: kind)) failed to start: \(error)")
                continuation.resume()
                return
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
            // .playback for every tone, because it is the only category that sounds with the
            // screen locked: `.ambient` is silenced by the lock as well as the Ring/Silent switch,
            // and a ride's phone is locked in a pocket or asleep on the bars. The 2026-11-03 ride
            // lost every radar tone while backgrounded (BLE.md §13.2 Q4). iOS can't read the
            // switch, so obeying it and playing while locked can't both be had; the alerts win.
            // .mixWithOthers keeps the rider's music playing under the tone, and is what lets a
            // backgrounded app start the session at all — with the `audio` background mode.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        }
    }

    private func ensureEngineRunning() throws {
        // Attach and connect are checked separately. Since iOS 27 `connectNode` can throw, and a
        // failed connect must leave the next call something to retry. A single "anything
        // attached?" check would step over an attached but unconnected player.
        if player.engine == nil {
            engine.attach(player)
        }
        if engine.outputConnectionPoints(for: player, outputBus: 0).isEmpty {
            try engine.connectNode(player, to: engine.mainMixerNode, format: ToneRenderer.format)
        }
        if !engine.isRunning {
            try engine.start()
        }
    }
}
