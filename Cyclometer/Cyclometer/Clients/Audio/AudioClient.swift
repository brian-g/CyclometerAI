import ComposableArchitecture
import AVFoundation

/// TCA dependency for three-tone audio safety alerts (per Audio.md spec).
///
///   L0 All Clear : 880 Hz sine,             200 ms — jersey-pocket audible
///   L2 Warning   : 1046 Hz triangle,        300 ms — double-pulsed
///   L3 Danger    : 1318 Hz + 1046 Hz chord, 600 ms — overrides Silent Mode (user opt-in)
struct AudioClient {
    var playAllClear:           @Sendable () async -> Void
    var playWarning:            @Sendable () async -> Void
    var playDanger:             @Sendable () async -> Void
    var setOverridesSilentMode: @Sendable (Bool) async -> Void
}

extension AudioClient: DependencyKey {
    static let liveValue = AudioClient(
        playAllClear:           { /* AVFoundation impl */ },
        playWarning:            { /* AVFoundation impl */ },
        playDanger:             { /* AVFoundation impl */ },
        setOverridesSilentMode: { enabled in
            // Use AVAudioSession.sharedInstance().setCategory(.playback, ...) when enabled
        }
    )
    static let testValue = AudioClient(
        playAllClear:           { },
        playWarning:            { },
        playDanger:             { },
        setOverridesSilentMode: { _ in }
    )
}

extension DependencyValues {
    var audioClient: AudioClient {
        get { self[AudioClient.self] }
        set { self[AudioClient.self] = newValue }
    }
}
