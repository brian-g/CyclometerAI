# Cyclometer — Audio Alert Specification
**Version:** 0.1 Draft  
**Date:** 2026-04-05  
**Status:** In Review  
**Author:** Brian (UX Design) + Claude (Specification)  
**Companion Documents:** `PRD.md §8.3` (Haptic Alert System), `PRD.md §8.2` (Radar Visualization)

---

## Overview

Cyclometer uses three distinct audio tones to communicate radar threat state. Unlike haptics, audio works through jersey pockets and provides awareness when the rider's attention is directed away from the phone. The three tones map to the three alert levels defined in `PRD.md §8.3`:

| Tone | Alert Level | Trigger | Silent Mode |
|---|---|---|---|
| **All Clear** | L0 | Threat has resolved (radar returns to clear after L2 or L3) | Never overrides |
| **Warning** | L2 — Caution | Moderate threat: 3+ vehicles, or moderate closing speed | Never overrides |
| **Danger** | L3 — Danger | Any vehicle ≥ 30 km/h closing speed | Overrides if user opt-in |

> **L1 Advisory**: No audio tone. Haptic only. Audio would be too disruptive for minor advisory-level events that may occur frequently on busy roads.

---

## Design Criteria

### 1. Audibility Requirements

| Condition | Target |
|---|---|
| Ambient noise floor at 30 km/h (wind) | ≈ 65 dB |
| Ambient noise floor at 40 km/h (wind) | ≈ 75 dB |
| Phone in jersey pocket (fabric attenuation) | −15 to −20 dB |
| Target tone perceived loudness | ≥ 10 dB above noise floor at pocket |

- Effective frequency range for outdoor cycling audibility: **1,000–4,000 Hz** (peak human hearing sensitivity; cuts through wind and road noise better than low frequencies)
- Tones below 800 Hz may be masked by road and wind noise; avoid for safety-critical sounds
- All tones must be perceptible without earphones; must also work through earphones without being jarring at typical listening volumes

### 2. Distinctiveness Requirements

Each tone must be instantly distinguishable from the others and from iOS system sounds (iMessage, phone call, Calendar alert, low battery warning) by **pattern and pitch alone**. The rider must be able to identify the alert level without conscious analysis after 2–3 rides.

- Different patterns (number of pulses, rhythm)
- Different pitch registers (low/mid/high)
- Different emotional registers (pleasant/alerting/urgent)
- Must not resemble any common iOS notification sound

### 3. Emotional Register

| Tone | Register | Design Intention |
|---|---|---|
| All Clear | Relief / resolution | Signals the threat has passed. Non-startling. Must not be confused with a new alert. |
| Warning | Attention / caution | "Pay attention." Not panic-inducing, but clearly not ambient. |
| Danger | Urgency / emergency | Instinctive response. Must cut through even moderate distraction. |

### 4. User Control

- All Clear and Warning tones: on/off toggle in Settings (S12), default **on**
- Danger tone: separate on/off toggle, default **on**; Silent Mode override is a third independent setting, default **off**
- Volume: follows system volume at the time of alert (no separate in-app volume control in MVP)

---

## Tone Specifications

### All Clear

**Purpose:** Signals that a radar threat that triggered a Warning or Danger has now resolved. The rider can relax.

| Parameter | Specification |
|---|---|
| Pattern | Two descending notes (interval: minor third) |
| Frequencies | 880 Hz → 587 Hz (A5 → D5) |
| Duration | 300 ms + 80 ms silence + 300 ms |
| Total duration | ~680 ms |
| Amplitude envelope | Soft attack (20 ms), sustain, gentle exponential decay |
| Waveform | Sine wave — smooth, non-harsh |
| Volume | 60% of system volume (this is a relieving signal, not an alert) |
| Repeat | No — plays once on level return to clear |

**Design note:** The descending interval subconsciously signals "going down" / de-escalation. The sine wave is pleasant and non-startling. This tone must not be confused with an incoming notification — the two-note descending pattern is sufficiently distinct from iOS single-note alerts.

---

### Warning (L2 — Caution)

**Purpose:** Communicates moderate threat — multiple vehicles approaching, or approaching at moderate speed. The rider should be aware but does not need to take immediate evasive action.

| Parameter | Specification |
|---|---|
| Pattern | Two short staccato pulses |
| Frequency | 1,400 Hz (F6) |
| Duration | 180 ms on, 120 ms off, 180 ms on |
| Total duration | ~480 ms |
| Amplitude envelope | Fast attack (5 ms), flat sustain, fast decay (20 ms) |
| Waveform | Triangle wave — more presence and edge than sine, less harsh than square |
| Volume | 80% of system volume |
| Repeat | Once per L2 trigger; minimum 3 seconds before re-trigger |

**Design note:** The double-pulse pattern is distinctive and carries a "caution" connotation already familiar from everyday life (two-beep vehicle reverse alerts, two-tone doorbells). 1,400 Hz sits in the peak sensitivity range of human hearing and cuts through wind noise effectively.

---

### Danger (L3)

**Purpose:** Maximum urgency. A vehicle is approaching at dangerous speed. The rider must take immediate evasive action. This tone must trigger an instinctive response, not a considered one.

| Parameter | Specification |
|---|---|
| Pattern | Triple burst, repeating with pause |
| Frequency | 2,100 Hz (C7) |
| Duration | 140 ms on, 80 ms off, 140 ms on, 80 ms off, 140 ms on → 580 ms total burst |
| Pause between bursts | 800 ms |
| Full cycle | ~1,380 ms |
| Amplitude envelope | Instantaneous attack (1 ms), flat sustain, fast decay (10 ms) |
| Waveform | Square wave — maximum harmonic content, most penetrating through noise |
| Volume | 100% of system volume; overrides AVAudioSession if user opt-in enabled |
| Repeat | Continuous until alert level drops below L3 threshold |
| Silent Mode | Uses `AVAudioSession` category `.playback` with speaker route override. Activates only when `UserProfile.overrideSilentModeForL3 == true`. |

**Design note:** The triple burst is a universally recognized urgency pattern (SOS-adjacent, rapid alarm cycles). 2,100 Hz is the frequency range where the square wave's harmonic content creates maximum auditory penetration. The square waveform is intentionally harsh — this is appropriate for a life-safety alert. The 800 ms pause between bursts prevents continuous tone fatigue and allows the rider to process the alert.

---

## Tone Relationships and Progression

```
Threat increasing:        Threat decreasing:
                          
L0 (clear)                L3 (danger) → [triple burst, repeating]
  ↓ vehicle detected           ↓ threat recedes
L1 (advisory) → haptic only   L2 (caution) → [double pulse]
  ↓ more vehicles / speed up       ↓ all clear
L2 (caution) → [double pulse] L0 (clear) → [two-note descending]
  ↓ high closing speed
L3 (danger) → [triple burst]
```

**Transitions:**
- L0 → L1: Haptic only; no audio
- L1 → L2: Warning tone plays once
- L2 → L3: Danger tone begins immediately (Warning does not also play)
- L3 → L2: Danger tone stops; Warning tone does NOT play (downgrade is not re-alerted)
- L2 → L0: All Clear tone plays once
- L3 → L0: Danger tone stops; All Clear tone plays once
- L1 → L0: No audio (no audio was played on L1 entry)

---

## Implementation Notes

### Synthesis Approach (Recommended)

Generate tones programmatically using `AVAudioEngine` with `AVAudioSourceNode`. This approach:
- Avoids bundled audio files and licensing questions
- Allows precise frequency, duration, and envelope control
- Permits runtime parameter adjustment (e.g., frequency tuning based on user feedback)
- Integrates cleanly with TCA via `AudioAlertClient` dependency

```swift
// Conceptual synthesis pattern — implementation detail for Claude Code phase
// Generate a tone burst with specified frequency, duration, and waveform
func generateTone(
    frequency: Double,      // Hz
    duration: TimeInterval, // seconds
    waveform: Waveform,     // .sine | .triangle | .square
    attackMs: Double,       // ms
    decayMs: Double         // ms
) -> AVAudioPCMBuffer
```

### Bundled Audio File Approach (Alternative)

If synthesis proves difficult to tune in context, short `.caf` (Core Audio Format) or `.wav` files can be bundled:
- Files should be 44.1 kHz, 16-bit mono
- Maximum file size: ~50 KB each (tones are short)
- License: must be CC0 (public domain) or original work

**Open source sound sources for reference/inspiration (not for direct use without license verification):**
- [freesound.org](https://freesound.org) — filter by CC0 license; search "beep alert", "warning tone", "chime"
- [Sonniss GDC Audio Bundle](https://sonniss.com/gameaudiogdc) — royalty-free game audio
- Custom synthesis using free tools: Audacity (open source), Sox (command-line)

### AVAudioSession Configuration

```swift
// For Warning and All Clear tones (respect Silent Mode):
try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)

// For Danger tone when overrideSilentModeForL3 is enabled:
try AVAudioSession.sharedInstance().setCategory(
    .playback,
    mode: .default,
    options: [.defaultToSpeaker, .duckOthers]
)
try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
```

---

## Acceptance Criteria

- [ ] All Clear tone: two descending notes, perceptible from jersey pocket at 30 km/h riding speed
- [ ] Warning tone: double pulse, perceptible from jersey pocket at 40 km/h riding speed
- [ ] Danger tone: triple burst, repeating, perceptible from jersey pocket at 40 km/h; must score ≥ 4/5 in blind recognition test after two playbacks
- [ ] All three tones are immediately distinguishable from each other in a blind listening test
- [ ] No tone resembles any stock iOS system sound (test on current iOS release)
- [ ] Danger tone plays through speaker when phone is face-down in jersey pocket (validate with `overrideOutputAudioPort(.speaker)`)
- [ ] Warning and All Clear tones respect Silent Mode (do not play when phone is on silent)
- [ ] Danger tone respects Silent Mode when override setting is OFF (default)
- [ ] Danger tone overrides Silent Mode when override setting is ON
- [ ] All tones fully testable via mock radar data in `AudioAlertClient` without hardware
- [ ] Tone volume does not exceed system volume setting
- [ ] Tones are interruptible — if threat level changes mid-tone, the new tone takes priority

---

## Open Questions

- [ ] **OQA1** — Should the Warning tone also play for L2 → L3 escalation, or only for L1/L0 → L2? (Current spec: no, to avoid double-alerting on rapid escalation)
- [ ] **OQA2** — Should there be a distinct advisory-level audio tone for L1, even though it's currently haptic-only? Cadence has no audio at this level; preserving that omission is intentional to reduce alert fatigue.
- [ ] **OQA3** — Earphone behavior: should the app detect if earphones are connected and adjust the Warning/Danger tone volume/character accordingly? (Earphones at full volume could be startling at 2,100 Hz)
- [ ] **OQA4** — Should the All Clear tone be a user-toggleable setting? Some riders may find any audio at "clear" distracting. Current spec: on by default, configurable in S12.
- [ ] **OQA5** — Tone fine-tuning: exact frequencies and patterns above are a starting point. User testing on a real ride (phone in pocket, at speed) is required to validate audibility and distinctiveness before finalizing.
- [ ] **OQA6** — Turn right and Turn left sounds must also be incorporated when turn by turn directions are added.

---

*Cyclometer Audio Alert Specification v0.1 · Draft · 2026-04-05*
