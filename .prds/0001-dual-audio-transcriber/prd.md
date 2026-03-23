# PRD-0001: DualAudioTranscriber

**Status:** draft
**Created:** 2026-03-23
**Author:** Eugene Rata

---

## Problem Statement

During meetings (Zoom, Teams, or any audio/video call), there is no native macOS tool that captures both sides of a conversation - what I say and what others say - as separate, correctly tagged transcript streams in real time. Existing solutions either require third-party virtual audio devices (fragile), screen recording permissions (invasive), or cloud-based transcription (latency, privacy). I need a tool that works instantly, runs entirely on-device, and produces a clean, speaker-tagged transcript that I can later send to an LLM for analysis.

## Solution

A native macOS 26 SwiftUI app that runs two independent audio capture and transcription pipelines simultaneously:

- **Microphone pipeline ("ME"):** Captures mic input via AVAudioEngine, feeds it to a dedicated SpeechAnalyzer/SpeechTranscriber instance.
- **System audio pipeline ("THEM"):** Captures all system audio output (excluding own process) via CoreAudio's CATapDescription/Process Tap API, feeds it to a second dedicated SpeechAnalyzer/SpeechTranscriber instance.

Both pipelines emit results into a single, chronologically ordered transcript list with accurate ME/THEM tagging. Volatile (partial) results appear immediately and update in-place until finalized. Zero third-party dependencies - everything uses Apple's shipping frameworks.

## User Stories

1. As a meeting participant, I want to click a single button to start recording both my voice and the other party's audio, so that I don't have to configure multiple tools.
2. As a meeting participant, I want to see what I'm saying tagged as [ME] and what others are saying tagged as [THEM], so that I can distinguish speakers at a glance.
3. As a meeting participant, I want to see partial transcription results appear immediately as words are spoken, so that I can follow along in real time without delay.
4. As a meeting participant, I want partial results to refine and update in-place as the speech model gains more context, so that the final text is accurate without cluttering the list with duplicates.
5. As a meeting participant, I want the transcript to be chronologically interleaved (ME and THEM entries mixed by time), so that I can read the conversation as a natural dialogue.
6. As a meeting participant, I want zero cross-contamination between streams - my voice must never appear as [THEM] and vice versa, so that the transcript is trustworthy.
7. As a meeting participant, I want to stop recording and have all pending partial results finalized, so that nothing is lost when I end the session.
8. As a meeting participant, I want to clear the transcript to start fresh for a new meeting, so that old entries don't pollute a new session.
9. As a meeting participant, I want to export the transcript as an SRT file with speaker tags and local timestamps, so that I can review it later or share it.
10. As a meeting participant, I want to export the transcript as a plain text file, so that I have a simple, portable record.
11. As a meeting participant, I want to copy the entire transcript (including the latest volatile text) to the clipboard with a single button click, so that I can paste it into an LLM chat for analysis.
12. As a meeting participant, I want the app to request microphone and system audio permissions on first launch with clear explanations, so that I understand why each permission is needed.
13. As a meeting participant, I want a visual recording indicator (pulsing red dot), so that I always know when capture is active.
14. As a meeting participant, I want the transcript list to auto-scroll to the latest entry, so that I don't have to manually scroll during a meeting.
15. As a meeting participant, I want volatile (partial) results to be visually distinct from finalized results (dimmed/italic vs solid), so that I can tell what's still being refined.
16. As a meeting participant, I want the app to handle edge cases gracefully - no system audio playing means no [THEM] entries appear (not errors), Bluetooth device changes don't crash the app, so that I can trust it during important calls.
17. As a meeting participant, I want the speech model to download automatically on first use if not already cached, so that setup is frictionless.
18. As a user, I want keyboard shortcuts (Cmd+Return to start/stop), so that I can control recording without reaching for the mouse.

## Implementation Decisions

### Architecture: Dual Independent Pipelines

Two completely independent SpeechAnalyzer + SpeechTranscriber pipelines, one per audio source. Mixing audio before transcription would destroy speaker tagging. Diarization after mixing is inferior in every way. Each SpeechAnalyzer instance manages its own audio timeline independently; both can run concurrently on ANE without conflict.

### Audio Capture

- **Microphone:** AVAudioEngine with a tap on inputNode. Must use the hardware's native format - never request a different format in installTap or macOS throws kAudioUnitErr_FormatNotSupported. SpeechAnalyzer handles resampling internally.
- **System audio:** CoreAudio Process Tap API (CATapDescription + AudioHardwareCreateProcessTap), introduced in macOS 14.4. This is the only correct approach on modern macOS. NOT ScreenCaptureKit (requires screen recording permission), NOT virtual audio devices (fragile third-party hacks). The pipeline: create CATapDescription (global stereo, excluding own PID) -> create process tap -> read tap format -> create private aggregate device with tap as sub-tap -> set up IO proc -> start device -> convert AudioBufferList to AVAudioPCMBuffer in callback -> forward to SpeechAnalyzer.
- **Own process exclusion:** Always exclude own PID from the system audio tap to prevent feedback loops.
- **Cleanup:** Aggregate device and process tap must be destroyed on stop/deinit or they leak.

### Transcription

- Use SpeechTranscriber with `.progressiveLiveTranscription` preset for streaming partial results.
- Model runs out-of-process (system speech service), not in app memory.
- Auto-download model on first use via AssetInventory if not already installed.
- Volatile results update in-place in the transcript list; finalized results are locked.

### Zero Buffering Policy

Audio buffers must be forwarded to SpeechAnalyzer immediately upon receipt. No batching, no queuing, no artificial delay. The user must see words appear as they are spoken. The "copy all" action must capture everything including the latest volatile text.

### Volatile-to-Final Result Handling

Each audio source tracks at most one "current volatile" entry. When a volatile result arrives:
- If a volatile entry already exists for that source, update its text in-place.
- If the result is final, mark the entry as final and clear the volatile tracker.
- If no volatile entry exists, create a new one.

This prevents the list from filling with duplicate partial results.

### Transcript Data Model

Each entry stores: unique ID, source (ME/THEM), timestamp (wall clock), text, and isFinal flag. Entries are ordered by insertion time. The model is immutable from the outside (new entries are appended, volatile entries are replaced with new instances).

### Export Formats

- **Plain text:** `[HH:MM:SS] [ME/THEM] text` per line.
- **SRT:** Single file with sequential numbering. Each entry becomes one SRT block. Timestamps are local wall-clock time formatted as SRT timecodes. Speaker tag (ME/THEM) is embedded in the text line.

### Project Setup

Xcode project (not SwiftPM CLI). macOS 26+ deployment target, Swift 6, arm64 only, sandbox disabled, hardened runtime enabled with audio input entitlement. Frameworks: AVFoundation, CoreAudio, AudioToolbox, Speech.

### Entitlements and Info.plist

- Sandbox disabled (CATapDescription requires unsandboxed access to CoreAudio).
- NSMicrophoneUsageDescription, NSAudioCaptureUsageDescription, and NSSpeechRecognitionUsageDescription must be set or the app will crash or silently fail.
- NSAudioCaptureUsageDescription triggers the macOS system audio capture permission prompt.

### Thread Safety

The IO proc callback for system audio runs on a real-time audio thread. No memory allocation, no locks, no blocking work in the callback. Copy buffer data and dispatch to another queue/Task.

### Error Handling

- System audio permission denial (OSStatus 1852797029 / 'nope'): surface a clear error message explaining the user must enable permission in System Settings.
- No public API to pre-check system audio capture permission; must attempt and handle failure.
- Bluetooth device changes mid-recording: monitor kAudioDevicePropertyDeviceHasChanged and handle gracefully.

## Testing Decisions

Tests should verify external behavior, not implementation details. Mock the audio/speech layers behind protocol interfaces so the data management layer can be tested in isolation.

### Modules with automated tests

- **TranscriptStore / entry management:** Test volatile-to-final replacement, correct ordering, no duplicate entries, clearing, empty-text filtering. These are pure logic tests with no hardware dependency.
- **SRTExporter:** Test SRT format output - sequential numbering, timecode formatting, speaker tag embedding, empty transcript edge case. Pure string transformation, fully testable.
- **PlainTextExporter:** Test text format output. Same approach as SRT.
- **TranscriptEntry model:** Test initialization, immutability guarantees, Identifiable conformance.

### Manual testing

Hardware integration (mic capture, system audio capture, SpeechAnalyzer) will be tested manually using YouTube video over speakers + mic input. Test scenarios from the tech spec (mic only, system audio only, dual stream, volatile/final results) serve as the manual test plan.

## Out of Scope

- LLM API integration (planned for a future version; v1 provides the "copy all" action as the handoff point)
- Per-app audio capture (capturing only Zoom, only Teams, etc.)
- Speaker diarization within the system audio stream (splitting multiple remote speakers)
- Acoustic echo cancellation (users should wear headphones for clean separation)
- Language auto-detection or multi-language support
- Live summarization
- App Store distribution or sandboxed builds
- iOS/iPadOS/visionOS support
- Recording to audio file (WAV/M4A)
- Settings/preferences UI

## Further Notes

- The "zero third-party dependencies" constraint is a hard requirement, not a preference. Everything must use Apple's shipping frameworks.
- macOS 26 (Tahoe) is required for SpeechAnalyzer/SpeechTranscriber. The app cannot support earlier macOS versions.
- Performance expectations (M-series): ~130ms speech-to-first-partial-result latency, <5% CPU (ANE handles inference), ~50-80MB app memory footprint. Speech model process adds ~200-400MB but is not charged to the app.
- First-launch model download (~150-300MB) should show progress to the user.
- When the user is not wearing headphones, speaker audio will bleed into the mic causing cross-contamination. This is a physics problem. V1 recommendation: wear headphones. AEC is out of scope.
- The tech spec (`tech.specs.md`) serves as implementation guidance. Implementation may diverge from the code samples as long as the architectural decisions and constraints described in this PRD are respected.
