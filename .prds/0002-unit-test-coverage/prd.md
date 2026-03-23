# PRD-0002: Extract DualSTT Library and Unit Test Coverage

**Status:** draft
**Created:** 2026-03-23
**Author:** Eugene Rata

---

## Problem Statement

The 2STT-macos repository is a monolithic executable. All audio capture, transcription, and model code lives inside a single `DualAudioTranscriber` executable target. This makes it impossible for other apps (specifically Flank, a native macOS interview copilot) to consume the transcription engine as a dependency. Additionally, the audio format conversion code that caused a production SIGTRAP crash has zero test coverage, and error types and the permission state machine are untested.

## Solution

Restructure the repository into two SPM targets: a reusable `DualSTT` library containing audio capture, transcription, models, and exports, and a `DualAudioTranscriber` executable that imports the library and provides the demo app UI. Extract the buffer conversion logic from SpeechPipeline into a standalone `BufferConverter` type. Add public access control for all consumer-facing types. Write comprehensive unit tests for all testable components, targeting ~49 tests across 9 files.

## User Stories

1. As a Flank developer, I want to add `DualSTT` as an SPM dependency, so that I can use system audio capture and transcription without copying source files.
2. As a Flank developer, I want to use `TranscriptionEngine` as a self-contained entry point, so that I get mic + system audio + transcription with a single `startRecording()` call.
3. As a Flank developer, I want to use `SystemAudioCaptureManager` standalone, so that I can capture system audio while using my own mic engine (OpenGranola).
4. As a Flank developer, I want to use `SpeechPipeline` directly, so that I can feed audio from any source into the transcription pipeline with full control.
5. As a Flank developer, I want `TranscriptStore` to be observable, so that my SwiftUI views reactively display transcript entries.
6. As a Flank developer, I want `TranscriptEntry` with `.me`/`.them` tagging, so that I can distinguish speakers in the transcript.
7. As a developer, I want the demo app to keep working after the restructure, so that I can verify the library works end-to-end.
8. As a developer, I want the buffer conversion code extracted into a testable unit, so that the crash-causing code path can be verified without live audio hardware.
9. As a developer, I want tests that cover sample rate conversion (48kHz to 16kHz, 44.1kHz to 16kHz), so that downsampling produces correct frame counts.
10. As a developer, I want tests that cover format conversion (Float32 to Int16), so that the exact crash scenario is regression-tested.
11. As a developer, I want tests that cover channel conversion (stereo to mono), so that multi-channel capture devices work correctly.
12. As a developer, I want tests that verify mid-stream format changes (device switch), so that switching audio devices during recording doesn't crash.
13. As a developer, I want tests that verify converter passthrough when formats match (identity - same buffer instance returned), so that no unnecessary conversion overhead occurs.
14. As a developer, I want the full pipeline scenario tested (Float32 48kHz stereo to Int16 16kHz mono), so that the real-world capture-to-analyzer path is verified.
15. As a developer, I want edge case tests (single-frame buffers, large 10-second buffers, 1000 rapid conversions), so that the converter is robust.
16. As a developer, I want tests that verify converted output contains non-zero audio data, so that silent/corrupt output is caught.
17. As a developer, I want all AudioCaptureError cases tested for non-empty descriptive messages, including the 'nope' (0x6E6F7065) status mentioning System Settings.
18. As a developer, I want all TranscriptionError cases tested, including appleIntelligenceRequired mentioning System Settings and locale identifiers appearing in locale-specific errors.
19. As a developer, I want PermissionState tested for initial state (all unknown), allReady logic (excludes systemAudio), and markSystemAudio transitions.
20. As a developer, I want AudioSource tested for raw values and Codable round-trip, so that serialization is verified.
21. As a developer, I want all library logs separated from app logs via a distinct logger subsystem, so that Console.app filtering works correctly.
22. As a developer, I want a v1.0.0 tag after the restructure passes all verification, so that Flank can pin to a stable version.

## Implementation Decisions

### Package Structure

- The SPM package is renamed from `DualAudioTranscriber` to `DualSTT`.
- Package.swift defines three targets: `DualSTT` (library), `DualAudioTranscriber` (executable, depends on DualSTT), and `DualSTTTests` (test target, depends on DualSTT).
- A `products` declaration exports `DualSTT` as a library product so external consumers can depend on it.
- Source files are physically reorganized into `Sources/DualSTT/` (library) and `Sources/DualAudioTranscriber/` (demo app).
- Tests move from `Tests/DualAudioTranscriberTests/` to `Tests/DualSTTTests/`.

### What Goes in the Library vs the App

Library (`Sources/DualSTT/`):
- Models: AudioSource, TranscriptEntry, PermissionState (+ PermissionStatus enum)
- Audio: AudioCapturing protocol, AudioCaptureError, MicCaptureManager, SystemAudioCaptureManager
- Transcription: BufferConverter (new), SpeechPipeline, TranscriptStore, TranscriptionEngine, TranscriptionError
- Export: PlainTextExporter, SRTExporter (moved from app - Option A, since they're small generic utilities any consumer would want)

App (`Sources/DualAudioTranscriber/`):
- App.swift
- All Views: ContentView, ControlBarView, TranscriptListView, TranscriptRowView, RecordingIndicator, PermissionStatusView
- Each view file adds `import DualSTT`

### Access Control

Public (consumer-facing API):
- All model types and their members: AudioSource, TranscriptEntry, PermissionStatus, PermissionState
- TranscriptStore (with `public private(set) var entries`)
- TranscriptionEngine (with `public private(set)` for state properties)
- AudioCapturing protocol, MicCaptureManager, SystemAudioCaptureManager
- AudioCaptureError, TranscriptionError
- SpeechPipeline (public so Flank can wire system audio to pipeline without using full TranscriptionEngine)
- PlainTextExporter, SRTExporter

Internal (implementation details):
- BufferConverter - implementation detail of SpeechPipeline
- Logger instances
- Private helper methods (e.g., deviceName(for:) in TranscriptionEngine)

### BufferConverter Extraction

- Extract from `SpeechPipeline.appendAudio()` inline code into `Sources/DualSTT/Transcription/BufferConverter.swift`.
- Interface: `init(targetFormat: AVAudioFormat)` and `func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer?`
- Owns the `AVAudioConverter` lifecycle. Sets `primeMethod = .none`.
- Passthrough: returns the original buffer instance (identity) when formats already match.
- Format change detection: if `converter.inputFormat != srcFormat`, recreates the converter.
- Returns `nil` on failure (buffer allocation failure, converter creation failure, conversion error).
- `SpeechPipeline.appendAudio()` simplifies to: lazily create `BufferConverter` on first call, then `guard let converted = bufferConverter?.convert(buffer)`.

### Logger Subsystem

- All library files change logger subsystem from `"com.eugenerat.DualAudioTranscriber"` to `"com.eugenerat.DualSTT"` so library logs are distinguishable from app logs in Console.app.

### Consumer Integration

- Flank adds the dependency via SPM: `.package(url: "https://github.com/integral-llc/2STT-macos.git", from: "1.0.0")`.
- Usage Pattern A (full engine): create `TranscriptionEngine()`, call `startRecording()`/`stopRecording()`, observe `engine.store.entries`.
- Usage Pattern B (system audio only): use `SystemAudioCaptureManager` + `SpeechPipeline` directly, feed audio with `appendAudio()`.

## Testing Decisions

- Tests verify external behavior only: given an input buffer with known properties, assert the output buffer has the correct format, frame count, and non-zero data. No internal state inspection.
- Prior art: existing tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). New tests follow the same pattern.
- Tests create synthetic `AVAudioPCMBuffer` instances filled with 440Hz sine wave data using shared helper functions (`makeSineBuffer`, `makeTargetFormat`). No hardware or microphone required.
- `PermissionStateTests` uses `@MainActor` on test methods since `PermissionState` is `@MainActor`-isolated.
- Frame count assertions allow +/- 1 frame tolerance for sample rate conversion rounding.
- Passthrough test uses identity check (`===`) to verify no copy is made.

### Testability Map

| Component | Unit Testable? | Why |
|-----------|---------------|-----|
| BufferConverter | YES - critical | Synthetic AVAudioPCMBuffers, verify conversion |
| AudioCaptureError | YES - trivial | Verify error descriptions |
| TranscriptionError | YES - trivial | Verify error descriptions |
| PermissionState | PARTIAL | Can test initial state + markSystemAudio. Can't test actual permission APIs without mocking |
| TranscriptEntry | DONE | Already covered |
| TranscriptStore | DONE | Already covered |
| PlainTextExporter | DONE | Already covered |
| SRTExporter | DONE | Already covered |
| SpeechPipeline | NO | Requires live SpeechAnalyzer + downloaded model |
| MicCaptureManager | NO | Requires hardware microphone |
| SystemAudioCaptureManager | NO | Requires CoreAudio process tap |
| TranscriptionEngine | NO | Integration test - requires all of the above |

### Test Suites

BufferConverter (13 tests):
- Passthrough when formats match (identity check)
- 48kHz to 16kHz downsampling
- 44.1kHz to 16kHz downsampling
- Stereo to mono
- Float32 to Int16 (the crash case)
- Full conversion: Float32 48kHz stereo to Int16 16kHz mono
- Converter reuse for consecutive same-format buffers
- Format change mid-stream recreates converter
- Single-frame buffer (no crash)
- Large buffer (10 seconds / 480k frames)
- Output contains non-zero audio data
- 1000 rapid conversions (no leak/crash)

AudioCaptureError (8 tests):
- noMicrophoneAvailable has descriptive message
- tapCreationFailed with 'nope' (0x6E6F7065) mentions System Settings
- tapCreationFailed with other status shows OSStatus
- formatReadFailed shows OSStatus
- aggregateDeviceFailed has description
- ioProcFailed has description
- deviceStartFailed has description
- All errors conform to LocalizedError with non-empty descriptions

TranscriptionError (4 tests):
- appleIntelligenceRequired mentions Apple Intelligence and System Settings
- localeNotSupported includes locale identifier
- modelNotInstalled includes locale and Apple Intelligence instructions
- modelDownloadFailed includes reason string

PermissionState (5 tests):
- Initial state is all unknown
- allReady is false when any required permission is not granted
- markSystemAudio updates systemAudio status
- allReady excludes systemAudio from requirements
- PermissionStatus enum has all 4 expected cases

AudioSource (3 tests):
- Raw values are correct (ME, THEM)
- Codable round-trip preserves value
- Decodes from JSON string

## Out of Scope

- SpeechPipeline integration tests (requires live SpeechAnalyzer + downloaded model)
- MicCaptureManager tests (requires physical microphone)
- SystemAudioCaptureManager tests (requires CoreAudio process tap entitlements)
- TranscriptionEngine tests (requires all of the above)
- UI/View tests
- CI pipeline setup
- Code coverage tooling integration
- Flank integration work (that's Flank's repo)

## Further Notes

- All tests run on any Apple Silicon Mac with macOS 26, no audio hardware needed.
- The BufferConverter extraction is a refactor with no behavioral change to SpeechPipeline.
- The exporter tests (SRTExporterTests, PlainTextExporterTests) reference TranscriptEntry and AudioSource which move to the library. Since exporters also move to the library (Option A), all existing tests stay in DualSTTTests with just an import change.
- After all verification passes, the commit is tagged v1.0.0 for consumer pinning.
