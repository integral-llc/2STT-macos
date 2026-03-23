# PRD-0002: Extract DualSTT Library and Unit Test Coverage - Tasks

Derived from [prd.md](./prd.md). Update as implementation progresses.

## Tasks

### 1. Directory Restructure

- [ ] Create `Sources/DualSTT/` directory structure (Audio/, Transcription/, Models/, Export/)
- [ ] Move model files to `Sources/DualSTT/Models/`: AudioSource.swift, TranscriptEntry.swift, PermissionState.swift
- [ ] Move audio files to `Sources/DualSTT/Audio/`: AudioCapturing.swift, AudioCaptureError.swift, MicCaptureManager.swift, SystemAudioCaptureManager.swift
- [ ] Move transcription files to `Sources/DualSTT/Transcription/`: SpeechPipeline.swift, TranscriptStore.swift, TranscriptionEngine.swift, TranscriptionError.swift
- [ ] Move export files to `Sources/DualSTT/Export/`: PlainTextExporter.swift, SRTExporter.swift
- [ ] Remove moved files from `Sources/DualAudioTranscriber/`
- [ ] Create `Sources/DualAudioTranscriber/` with remaining app files: App.swift + Views/
- [ ] Add `import DualSTT` to all remaining app files (App.swift + each View)

### 2. Package.swift Rewrite

- [ ] Replace Package.swift with multi-target version: DualSTT library target, DualAudioTranscriber executable target (depends on DualSTT), DualSTTTests test target
- [ ] Add `.library(name: "DualSTT", targets: ["DualSTT"])` product declaration

### 3. Access Control

- [ ] Add `public` to all consumer-facing types and members per access control rules (Models, TranscriptStore, TranscriptionEngine, AudioCapturing, capture managers, errors, SpeechPipeline, exporters)
- [ ] Verify internal types stay internal: BufferConverter, Logger instances, private helpers

### 4. BufferConverter Extraction

- [ ] Create `Sources/DualSTT/Transcription/BufferConverter.swift` with `init(targetFormat:)` and `convert(_:) -> AVAudioPCMBuffer?`
- [ ] Move conversion logic from `SpeechPipeline.appendAudio()` into BufferConverter, including format change detection and `primeMethod = .none`
- [ ] Simplify `SpeechPipeline.appendAudio()` to: lazy `BufferConverter` init, then `guard let converted = bufferConverter?.convert(buffer)`

### 5. Logger Subsystem Update

- [ ] Change all Logger subsystem strings from `"com.eugenerat.DualAudioTranscriber"` to `"com.eugenerat.DualSTT"` in library files

### 6. Test Restructure

- [ ] Rename `Tests/DualAudioTranscriberTests/` to `Tests/DualSTTTests/`
- [ ] Update all `@testable import DualAudioTranscriber` to `@testable import DualSTT` in existing test files

### 7. Build Verification (pre-tests)

- [ ] `swift build` succeeds with no access control errors
- [ ] `swift test` passes all existing tests under new package structure
- [ ] Demo app builds, launches, and transcribes correctly

### 8. New Test Files

- [ ] Create `BufferConverterTests.swift` with shared helpers (`makeSineBuffer`, `makeTargetFormat`) and 13 tests: passthrough identity, 48kHz to 16kHz, 44.1kHz to 16kHz, stereo to mono, Float32 to Int16, full pipeline conversion, converter reuse, format change mid-stream, single-frame buffer, large buffer (10s), non-zero audio data, rapid conversions (1000x)
- [ ] Create `AudioCaptureErrorTests.swift` (8 tests): noMic, tapCreationFailed 'nope' mentions System Settings, tapCreationFailed other shows OSStatus, formatReadFailed, aggregateDeviceFailed, ioProcFailed, deviceStartFailed, all-conform-to-LocalizedError
- [ ] Create `TranscriptionErrorTests.swift` (4 tests): appleIntelligenceRequired, localeNotSupported with locale ID, modelNotInstalled with locale + instructions, modelDownloadFailed with reason
- [ ] Create `PermissionStateTests.swift` (5 tests @MainActor): initial all-unknown, allReady false by default, markSystemAudio updates, allReady excludes systemAudio, PermissionStatus cases
- [ ] Create `AudioSourceTests.swift` (3 tests): raw values, Codable round-trip, JSON string decode

### 9. Final Verification

- [ ] `swift test` - all ~49 tests pass
- [ ] No regressions in existing 4 test files
- [ ] Commit: "refactor: extract DualSTT library for SPM consumption"
- [ ] Tag v1.0.0

## Discovered During Implementation

Add tasks here that surface during the build but weren't in the original plan.

- [ ] ...
