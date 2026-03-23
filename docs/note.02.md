# Tech Note: Extract DualSTT as a Production SPM Library

## Objective

Restructure the 2STT-macos repository so the audio capture + transcription engine
is a reusable Swift Package library (`DualSTT`) that can be consumed by other apps
(specifically: Flank, a native macOS interview copilot built with Swift 6.2/SwiftUI).

The standalone 2STT demo app continues to work, now importing the library.

---

## Context About the Consumer (Flank)

Flank is a native macOS 15+ app (Swift 6.2, SwiftUI, no sandbox, no CocoaPods).
It already has its own audio engine for mic capture (extracted from OpenGranola).
It uses GRDB for persistence, SPM for all dependencies. It streams transcripts
to an Anthropic-powered AI overlay.

Flank needs:
- System audio capture (CATapDescription) - it does NOT have this today
- SpeechAnalyzer transcription pipeline with format conversion
- TranscriptEntry model with .me/.them tagging
- TranscriptStore with volatile/final handling
- Optionally mic capture (may use its own OpenGranola engine instead)

Flank does NOT need: the SwiftUI views, the demo app, the exporters (it has GRDB).

---

## Target Structure

```
2STT-macos/
├── Package.swift                    # Defines DualSTT library + DualAudioTranscriber executable
├── Sources/
│   ├── DualSTT/                     # THE LIBRARY - what consumers import
│   │   ├── Audio/
│   │   │   ├── AudioCapturing.swift
│   │   │   ├── AudioCaptureError.swift
│   │   │   ├── MicCaptureManager.swift
│   │   │   └── SystemAudioCaptureManager.swift
│   │   ├── Transcription/
│   │   │   ├── BufferConverter.swift       # Extract from SpeechPipeline into own file
│   │   │   ├── SpeechPipeline.swift
│   │   │   ├── TranscriptStore.swift
│   │   │   ├── TranscriptionEngine.swift
│   │   │   └── TranscriptionError.swift
│   │   └── Models/
│   │       ├── AudioSource.swift
│   │       ├── TranscriptEntry.swift
│   │       └── PermissionState.swift
│   │
│   └── DualAudioTranscriber/        # THE DEMO APP - imports DualSTT
│       ├── App.swift
│       ├── Export/
│       │   ├── PlainTextExporter.swift
│       │   └── SRTExporter.swift
│       └── Views/
│           ├── ContentView.swift
│           ├── ControlBarView.swift
│           ├── TranscriptListView.swift
│           ├── TranscriptRowView.swift
│           ├── RecordingIndicator.swift
│           └── PermissionStatusView.swift
│
├── Tests/
│   └── DualSTTTests/                # Renamed from DualAudioTranscriberTests
│       ├── TranscriptEntryTests.swift
│       ├── TranscriptStoreTests.swift
│       ├── SRTExporterTests.swift      # Keep here or move to app tests
│       └── PlainTextExporterTests.swift # Keep here or move to app tests
│
├── DualAudioTranscriber/            # Keep existing Xcode support files here
│   ├── DualAudioTranscriber.entitlements
│   └── Info.plist
│
└── tech.specs.md
```

---

## Package.swift

Replace the existing Package.swift with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DualSTT",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "DualSTT",
            targets: ["DualSTT"]
        ),
    ],
    targets: [
        // The reusable library
        .target(
            name: "DualSTT",
            path: "Sources/DualSTT",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Speech"),
            ]
        ),

        // The standalone demo app
        .executableTarget(
            name: "DualAudioTranscriber",
            dependencies: ["DualSTT"],
            path: "Sources/DualAudioTranscriber",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),

        // Tests for the library
        .testTarget(
            name: "DualSTTTests",
            dependencies: ["DualSTT"],
            path: "Tests/DualSTTTests"
        ),
    ]
)
```

---

## Access Control Rules

This is the critical part. Every type in DualSTT must have explicit access control.
The rule: public interface for consumers, internal implementation details.

### PUBLIC (consumers see these)

These types and their members must be marked `public`:

**Models:**

```swift
// AudioSource.swift
public enum AudioSource: String, Codable, Sendable, Equatable {
    case me = "ME"
    case them = "THEM"
}

// TranscriptEntry.swift
public struct TranscriptEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: AudioSource
    public let timestamp: Date
    public let text: String
    public let isFinal: Bool

    public init(
        id: UUID = UUID(),
        source: AudioSource,
        timestamp: Date = Date(),
        text: String,
        isFinal: Bool = false
    ) { ... }

    public func with(text: String? = nil, isFinal: Bool? = nil) -> TranscriptEntry { ... }
}
```

**TranscriptStore:**

```swift
@Observable
@MainActor
public final class TranscriptStore {
    public private(set) var entries: [TranscriptEntry] = []

    public init() {}

    public func handleResult(source: AudioSource, text: String, isFinal: Bool) { ... }
    public func clear() { ... }
    public func allText(includingVolatile: Bool = true) -> String { ... }
}
```

**TranscriptionEngine:**

```swift
@Observable
@MainActor
public final class TranscriptionEngine {
    public let store: TranscriptStore
    public let permissions: PermissionState
    public private(set) var isRecording: Bool
    public var error: String?
    public private(set) var micDeviceName: String
    public private(set) var systemAudioInfo: String

    public init() { ... }

    public func startRecording() async { ... }
    public func stopRecording() async { ... }
    public func clearTranscript() { ... }

    // Keep these public so consumers can export however they want
    // Or remove and let consumers read store.entries directly
    public static func currentOutputDeviceName() -> String { ... }
}
```

**PermissionState:**

```swift
public enum PermissionStatus: Sendable { ... }

@Observable
@MainActor
public final class PermissionState {
    public private(set) var microphone: PermissionStatus
    public private(set) var systemAudio: PermissionStatus
    public private(set) var speechRecognition: PermissionStatus
    public private(set) var speechModel: PermissionStatus
    public var allReady: Bool { ... }

    public init() { ... }

    public func checkAll() { ... }
    public func checkMicrophone() { ... }
    public func requestMicrophone() async { ... }
    public func checkSpeechRecognition() { ... }
    public func requestSpeechRecognition() { ... }
    public func checkSpeechModel() { ... }
    public func markSystemAudio(_ status: PermissionStatus) { ... }
}
```

**Errors:**

```swift
public enum AudioCaptureError: Error, LocalizedError { ... }
public enum TranscriptionError: Error, LocalizedError { ... }
```

**Audio Capture Managers (public so Flank can use them standalone):**

```swift
public protocol AudioCapturing: AnyObject, Sendable {
    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)? { get set }
    func start() throws
    func stop()
}

@Observable
public final class MicCaptureManager: AudioCapturing, @unchecked Sendable {
    public var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    public init() {}
    public func start() throws { ... }
    public func stop() { ... }
}

@Observable
public final class SystemAudioCaptureManager: AudioCapturing, @unchecked Sendable {
    public var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?
    public init() {}
    public func start() throws { ... }
    public func stop() { ... }
}
```

### INTERNAL (implementation details, NOT public)

These stay `internal` (default access) - consumers don't need them:

- `SpeechPipeline` - internal orchestration of SpeechAnalyzer
- `BufferConverter` - internal audio format conversion
- Logger instances
- All private helper methods
- `deviceName(for:)` helper in TranscriptionEngine

---

## Extract BufferConverter Into Its Own File

Currently the AVAudioConverter logic is inline in SpeechPipeline.appendAudio().
Extract it into `Sources/DualSTT/Transcription/BufferConverter.swift`:

```swift
import AVFoundation
import os.log

private let log = Logger(subsystem: "com.zintegral.DualSTT", category: "BufferConverter")

final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let srcFormat = buffer.format

        // No conversion needed
        if srcFormat.sampleRate == targetFormat.sampleRate
            && srcFormat.channelCount == targetFormat.channelCount
            && srcFormat.commonFormat == targetFormat.commonFormat {
            return buffer
        }

        // Create or recreate converter if input format changed
        if converter == nil || converter?.inputFormat != srcFormat {
            guard let c = AVAudioConverter(from: srcFormat, to: targetFormat) else {
                log.error("Failed to create converter from \(srcFormat) to \(self.targetFormat)")
                return nil
            }
            c.primeMethod = .none
            self.converter = c
            log.info("Converter created: \(srcFormat.sampleRate)Hz \(srcFormat.channelCount)ch -> \(self.targetFormat.sampleRate)Hz \(self.targetFormat.channelCount)ch")
        }

        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status == .haveData || status == .endOfStream else {
            if let error { log.error("Conversion failed: \(error)") }
            return nil
        }

        return output
    }
}
```

Then SpeechPipeline.appendAudio() simplifies to:

```swift
func appendAudio(_ buffer: AVAudioPCMBuffer) {
    guard isActive else { return }

    if bufferConverter == nil, let targetFormat {
        bufferConverter = BufferConverter(targetFormat: targetFormat)
    }

    guard let converted = bufferConverter?.convert(buffer) else { return }
    inputContinuation?.yield(AnalyzerInput(buffer: converted))
}
```

---

## Update Logger Subsystem

Change all Logger subsystem strings from:
```swift
Logger(subsystem: "com.zintegral.DualAudioTranscriber", category: "...")
```
To:
```swift
Logger(subsystem: "com.zintegral.DualSTT", category: "...")
```

This separates library logs from app logs in Console.app.

---

## Update Test Imports

All test files currently have:
```swift
@testable import DualAudioTranscriber
```

Change to:
```swift
@testable import DualSTT
```

The exporter tests (SRTExporterTests, PlainTextExporterTests) reference types that
are moving to the library (TranscriptEntry, AudioSource) but the exporters themselves
stay in the app. Two options:

**Option A (recommended):** Move the exporters into DualSTT as public utilities.
They're small (19 and 33 lines), generic, and any consumer would want export.
Keep all tests in DualSTTTests.

**Option B:** Keep exporters in the app target. Move exporter tests into a
separate DualAudioTranscriberTests target that depends on both DualSTT and the
app. More complex, not worth it for 52 lines of export code.

Go with Option A.

---

## Move Exporters to Library

Move `PlainTextExporter.swift` and `SRTExporter.swift` into `Sources/DualSTT/Export/`.
Mark them public:

```swift
public enum PlainTextExporter {
    public static func export(_ entries: [TranscriptEntry]) -> String { ... }
}

public enum SRTExporter {
    public static func export(_ entries: [TranscriptEntry]) -> String { ... }
}
```

---

## Demo App Changes

The demo app at `Sources/DualAudioTranscriber/` needs:

1. `import DualSTT` at the top of every file
2. Remove local copies of all model/audio/transcription files (they're now in DualSTT)
3. Keep only: App.swift and all Views/

Files remaining in the app target:
```
Sources/DualAudioTranscriber/
├── App.swift
└── Views/
    ├── ContentView.swift
    ├── ControlBarView.swift
    ├── TranscriptListView.swift
    ├── TranscriptRowView.swift
    ├── RecordingIndicator.swift
    └── PermissionStatusView.swift
```

Every view file adds `import DualSTT` at the top. No other changes needed since
all the types they reference (TranscriptionEngine, TranscriptEntry, etc.) keep
the same names.

---

## Semantic Versioning

After restructuring:

1. Verify `swift build` succeeds
2. Verify `swift test` passes (all existing tests)
3. Verify the demo app launches and transcribes
4. Tag the commit:

```bash
git tag -a v1.0.0 -m "DualSTT: production SPM library for dual audio capture + transcription"
git push origin v1.0.0
```

---

## Consumer Integration (How Flank Will Use It)

### SPM Dependency

```swift
// In Flank's Package.swift:
dependencies: [
    .package(url: "https://github.com/integral-llc/2STT-macos.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "Flank",
        dependencies: [
            .product(name: "DualSTT", package: "2STT-macos"),
        ]
    ),
]
```

Or via Xcode: File > Add Package Dependencies > paste the GitHub URL.

### Usage Pattern A: Full engine (mic + system audio + transcription)

```swift
import DualSTT

let engine = TranscriptionEngine()
await engine.startRecording()

// Read entries reactively (engine.store is @Observable)
for entry in engine.store.entries {
    print("[\(entry.source.rawValue)] \(entry.text)")
}

await engine.stopRecording()
```

### Usage Pattern B: System audio only (Flank has its own mic via OpenGranola)

```swift
import DualSTT

let systemCapture = SystemAudioCaptureManager()
let pipeline = SpeechPipeline(source: .them)  // Only if SpeechPipeline is public

// OR use TranscriptStore directly with a custom setup
let store = TranscriptStore()
// ... wire systemCapture -> pipeline -> store
```

NOTE: If Flank only needs the full TranscriptionEngine, SpeechPipeline can stay
internal. If Flank needs granular control (e.g., system audio capture without mic,
or feeding audio from OpenGranola into a SpeechPipeline), then SpeechPipeline
and BufferConverter should also be public. Decision: **make SpeechPipeline public
too** so Flank has flexibility. Mark BufferConverter internal since it's an
implementation detail of SpeechPipeline.

Update SpeechPipeline access:

```swift
public final class SpeechPipeline: @unchecked Sendable {
    public let source: AudioSource
    public var onTranscript: (@Sendable (String, Bool) -> Void)?
    public var onError: (@Sendable (String) -> Void)?

    public init(source: AudioSource) { ... }
    public func prepare(locale: Locale = ...) async throws { ... }
    public func appendAudio(_ buffer: AVAudioPCMBuffer) { ... }
    public func finalize() async { ... }
}
```

---

## Checklist

Execute in order:

- [ ] Create `Sources/DualSTT/` directory structure
- [ ] Move model files: AudioSource.swift, TranscriptEntry.swift, PermissionState.swift
- [ ] Move audio files: AudioCapturing.swift, AudioCaptureError.swift, MicCaptureManager.swift, SystemAudioCaptureManager.swift
- [ ] Move transcription files: SpeechPipeline.swift, TranscriptStore.swift, TranscriptionEngine.swift, TranscriptionError.swift
- [ ] Move export files: PlainTextExporter.swift, SRTExporter.swift
- [ ] Extract BufferConverter.swift from SpeechPipeline inline code
- [ ] Add `public` access modifiers per the rules above
- [ ] Update all Logger subsystems to "com.zintegral.DualSTT"
- [ ] Remove moved files from Sources/DualAudioTranscriber/
- [ ] Add `import DualSTT` to all remaining app files (App.swift + Views)
- [ ] Replace Package.swift with the new multi-target version
- [ ] Rename Tests/DualAudioTranscriberTests/ to Tests/DualSTTTests/
- [ ] Update test imports from `@testable import DualAudioTranscriber` to `@testable import DualSTT`
- [ ] Run `swift build` - fix any access control errors
- [ ] Run `swift test` - all tests must pass
- [ ] Build and run the demo app - verify it launches and transcribes
- [ ] Commit with message: "refactor: extract DualSTT library for SPM consumption"
- [ ] Tag v1.0.0

# Tech Note: Unit Tests for DualSTT Library

## Current Coverage

4 test files exist covering TranscriptEntry, TranscriptStore, PlainTextExporter, SRTExporter.
These are good - don't touch them (except updating imports to `@testable import DualSTT`).

## What's Missing

The code that caused the SIGTRAP crash - audio format conversion - has zero tests.
The error types have zero tests. PermissionState state machine has zero tests.

## Testability Map

| Component | Unit Testable? | Why |
|-----------|---------------|-----|
| BufferConverter | YES - critical | Create synthetic AVAudioPCMBuffers, verify conversion |
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

## New Test Files to Create

Create these files in `Tests/DualSTTTests/`:

---

### 1. BufferConverterTests.swift

This is the most important test file. The BufferConverter was the root cause of the 
production crash. Every edge case must be covered.

NOTE: BufferConverter is `internal` to DualSTT. Tests use `@testable import DualSTT`
to access it. If BufferConverter is not yet extracted into its own file, extract it
first per the SPM library tech note.

```swift
import Testing
import AVFoundation
@testable import DualSTT

@Suite("BufferConverter")
struct BufferConverterTests {

    // MARK: - Helpers

    /// Create a synthetic AVAudioPCMBuffer filled with a sine wave
    private func makeSineBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frameCount: AVAudioFrameCount,
        format: AVAudioCommonFormat = .pcmFormatFloat32,
        interleaved: Bool = false
    ) -> AVAudioPCMBuffer {
        let audioFormat = AVAudioFormat(
            commonFormat: format,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: interleaved
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        // Fill with 440Hz sine wave
        if format == .pcmFormatFloat32, let channelData = buffer.floatChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    let phase = Float(frame) / Float(sampleRate) * 440.0 * 2.0 * .pi
                    channelData[ch][frame] = sinf(phase) * 0.5
                }
            }
        } else if format == .pcmFormatInt16, let channelData = buffer.int16ChannelData {
            for ch in 0..<Int(channels) {
                for frame in 0..<Int(frameCount) {
                    let phase = Float(frame) / Float(sampleRate) * 440.0 * 2.0 * .pi
                    channelData[ch][frame] = Int16(sinf(phase) * 16000.0)
                }
            }
        }

        return buffer
    }

    private func makeTargetFormat(
        sampleRate: Double = 16000,
        channels: AVAudioChannelCount = 1,
        format: AVAudioCommonFormat = .pcmFormatInt16
    ) -> AVAudioFormat {
        AVAudioFormat(
            commonFormat: format,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!
    }

    // MARK: - Passthrough Tests

    @Test("returns original buffer when formats match exactly")
    func passthroughWhenFormatsMatch() {
        let targetFormat = makeTargetFormat(
            sampleRate: 16000,
            channels: 1,
            format: .pcmFormatInt16
        )
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 16000,
            channels: 1,
            frameCount: 1600,
            format: .pcmFormatInt16,
            interleaved: true
        )

        let result = converter.convert(input)

        // Should be the exact same buffer instance (no copy)
        #expect(result === input)
    }

    // MARK: - Sample Rate Conversion

    @Test("converts 48kHz to 16kHz")
    func downsamples48kTo16k() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 48000,
            channels: 1,
            frameCount: 4800  // 100ms at 48kHz
        )

        let result = converter.convert(input)

        #expect(result != nil)
        // 4800 frames at 48kHz -> ~1600 frames at 16kHz
        let expectedFrames = AVAudioFrameCount(
            (Double(input.frameLength) * 16000.0 / 48000.0).rounded(.up)
        )
        // Allow +/- 1 frame for rounding
        #expect(result!.frameLength >= expectedFrames - 1)
        #expect(result!.frameLength <= expectedFrames + 1)
        #expect(result!.format.sampleRate == 16000)
    }

    @Test("converts 44.1kHz to 16kHz")
    func downsamples44_1kTo16k() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 44100,
            channels: 1,
            frameCount: 4410  // 100ms at 44.1kHz
        )

        let result = converter.convert(input)

        #expect(result != nil)
        #expect(result!.format.sampleRate == 16000)
        // 4410 * (16000/44100) ~ 1600
        #expect(result!.frameLength > 0)
        #expect(result!.frameLength <= 1602)  // allow rounding
    }

    // MARK: - Channel Conversion

    @Test("converts stereo to mono")
    func stereoToMono() {
        let targetFormat = makeTargetFormat(sampleRate: 16000, channels: 1)
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 16000,
            channels: 2,
            frameCount: 1600
        )

        let result = converter.convert(input)

        #expect(result != nil)
        #expect(result!.format.channelCount == 1)
    }

    // MARK: - Format Conversion (the crash scenario)

    @Test("converts Float32 to Int16 - the original crash case")
    func float32ToInt16() {
        let targetFormat = makeTargetFormat(
            sampleRate: 16000,
            channels: 1,
            format: .pcmFormatInt16
        )
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 16000,
            channels: 1,
            frameCount: 1600,
            format: .pcmFormatFloat32
        )

        let result = converter.convert(input)

        #expect(result != nil)
        #expect(result!.format.commonFormat == .pcmFormatInt16)
        #expect(result!.frameLength == 1600)
    }

    @Test("converts Float32 48kHz stereo to Int16 16kHz mono - full pipeline scenario")
    func fullConversion_float32_48k_stereo_to_int16_16k_mono() {
        let targetFormat = makeTargetFormat(
            sampleRate: 16000,
            channels: 1,
            format: .pcmFormatInt16
        )
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 48000,
            channels: 2,
            frameCount: 4800,  // 100ms at 48kHz stereo
            format: .pcmFormatFloat32
        )

        let result = converter.convert(input)

        #expect(result != nil)
        #expect(result!.format.sampleRate == 16000)
        #expect(result!.format.channelCount == 1)
        #expect(result!.format.commonFormat == .pcmFormatInt16)
        #expect(result!.frameLength > 0)
    }

    // MARK: - Converter Reuse and Invalidation

    @Test("reuses converter for consecutive buffers with same format")
    func reusesConverterForSameFormat() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)

        let buf1 = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)
        let buf2 = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)

        let r1 = converter.convert(buf1)
        let r2 = converter.convert(buf2)

        #expect(r1 != nil)
        #expect(r2 != nil)
        // Both should succeed - converter was reused internally
    }

    @Test("handles format change mid-stream by recreating converter")
    func handlesFormatChange() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)

        // First: 48kHz input
        let buf48 = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 4800)
        let r1 = converter.convert(buf48)
        #expect(r1 != nil)

        // Then: 44.1kHz input (device changed)
        let buf44 = makeSineBuffer(sampleRate: 44100, channels: 1, frameCount: 4410)
        let r2 = converter.convert(buf44)
        #expect(r2 != nil)
        // Should still produce 16kHz output
        #expect(r2!.format.sampleRate == 16000)
    }

    // MARK: - Edge Cases

    @Test("handles single-frame buffer")
    func singleFrameBuffer() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(sampleRate: 48000, channels: 1, frameCount: 1)

        // Should not crash - may return nil or a valid buffer
        let _ = converter.convert(input)
        // No crash = pass
    }

    @Test("handles large buffer (10 seconds)")
    func largeBuffer() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 48000,
            channels: 2,
            frameCount: 480000  // 10 seconds at 48kHz
        )

        let result = converter.convert(input)

        #expect(result != nil)
        // 480000 * (16000/48000) = 160000
        #expect(result!.frameLength >= 159999)
        #expect(result!.frameLength <= 160001)
    }

    @Test("output buffer contains non-zero audio data")
    func outputContainsAudioData() {
        let targetFormat = makeTargetFormat(
            sampleRate: 16000,
            channels: 1,
            format: .pcmFormatInt16
        )
        let converter = BufferConverter(targetFormat: targetFormat)
        let input = makeSineBuffer(
            sampleRate: 48000,
            channels: 1,
            frameCount: 4800,
            format: .pcmFormatFloat32
        )

        let result = converter.convert(input)

        #expect(result != nil)
        guard let int16Data = result!.int16ChannelData else {
            Issue.record("int16ChannelData is nil")
            return
        }
        // At least some samples should be non-zero (sine wave)
        var hasNonZero = false
        for i in 0..<Int(result!.frameLength) {
            if int16Data[0][i] != 0 {
                hasNonZero = true
                break
            }
        }
        #expect(hasNonZero, "Output buffer is all zeros - conversion lost audio data")
    }

    @Test("multiple rapid conversions don't leak or crash")
    func rapidConversions() {
        let targetFormat = makeTargetFormat()
        let converter = BufferConverter(targetFormat: targetFormat)

        for _ in 0..<1000 {
            let input = makeSineBuffer(
                sampleRate: 48000,
                channels: 2,
                frameCount: 1024
            )
            let _ = converter.convert(input)
        }
        // No crash, no leak = pass
    }
}
```

---

### 2. AudioCaptureErrorTests.swift

```swift
import Testing
import Foundation
@testable import DualSTT

@Suite("AudioCaptureError")
struct AudioCaptureErrorTests {

    @Test("noMicrophoneAvailable has descriptive message")
    func noMic() {
        let error = AudioCaptureError.noMicrophoneAvailable
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("microphone"))
    }

    @Test("tapCreationFailed with 'nope' status mentions System Settings")
    func tapNope() {
        let error = AudioCaptureError.tapCreationFailed(0x6E6F7065) // 'nope'
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("System Settings"))
    }

    @Test("tapCreationFailed with other status shows OSStatus")
    func tapOtherError() {
        let error = AudioCaptureError.tapCreationFailed(-50)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("-50"))
    }

    @Test("formatReadFailed shows OSStatus")
    func formatRead() {
        let error = AudioCaptureError.formatReadFailed(-10868)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("-10868"))
    }

    @Test("aggregateDeviceFailed shows OSStatus")
    func aggregateDevice() {
        let error = AudioCaptureError.aggregateDeviceFailed(-1)
        #expect(error.errorDescription != nil)
    }

    @Test("ioProcFailed shows OSStatus")
    func ioProc() {
        let error = AudioCaptureError.ioProcFailed(-1)
        #expect(error.errorDescription != nil)
    }

    @Test("deviceStartFailed shows OSStatus")
    func deviceStart() {
        let error = AudioCaptureError.deviceStartFailed(-1)
        #expect(error.errorDescription != nil)
    }

    @Test("all errors conform to LocalizedError")
    func allConformToLocalizedError() {
        let errors: [AudioCaptureError] = [
            .noMicrophoneAvailable,
            .microphonePermissionDenied,
            .tapCreationFailed(0),
            .formatReadFailed(0),
            .aggregateDeviceFailed(0),
            .ioProcFailed(0),
            .deviceStartFailed(0),
        ]
        for error in errors {
            #expect(error.errorDescription != nil, "Missing description for \(error)")
            #expect(!error.errorDescription!.isEmpty, "Empty description for \(error)")
        }
    }
}
```

---

### 3. TranscriptionErrorTests.swift

```swift
import Testing
import Foundation
@testable import DualSTT

@Suite("TranscriptionError")
struct TranscriptionErrorTests {

    @Test("appleIntelligenceRequired mentions System Settings")
    func appleIntelligence() {
        let error = TranscriptionError.appleIntelligenceRequired
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("Apple Intelligence"))
        #expect(error.errorDescription!.contains("System Settings"))
    }

    @Test("localeNotSupported includes locale identifier")
    func localeNotSupported() {
        let locale = Locale(identifier: "ja-JP")
        let error = TranscriptionError.localeNotSupported(locale)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("ja-JP"))
    }

    @Test("modelNotInstalled includes locale and instructions")
    func modelNotInstalled() {
        let locale = Locale(identifier: "en-US")
        let error = TranscriptionError.modelNotInstalled(locale)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("en-US"))
        #expect(error.errorDescription!.contains("Apple Intelligence"))
    }

    @Test("modelDownloadFailed includes reason")
    func modelDownloadFailed() {
        let error = TranscriptionError.modelDownloadFailed("network timeout")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("network timeout"))
    }
}
```

---

### 4. PermissionStateTests.swift

```swift
import Testing
import Foundation
@testable import DualSTT

@Suite("PermissionState")
struct PermissionStateTests {

    @Test("initial state is all unknown")
    @MainActor
    func initialState() {
        let state = PermissionState()
        #expect(state.microphone == .unknown)
        #expect(state.systemAudio == .unknown)
        #expect(state.speechRecognition == .unknown)
        #expect(state.speechModel == .unknown)
    }

    @Test("allReady is false when any required permission is not granted")
    @MainActor
    func allReadyFalseByDefault() {
        let state = PermissionState()
        #expect(state.allReady == false)
    }

    @Test("markSystemAudio updates systemAudio status")
    @MainActor
    func markSystemAudio() {
        let state = PermissionState()

        state.markSystemAudio(.granted)
        #expect(state.systemAudio == .granted)

        state.markSystemAudio(.denied)
        #expect(state.systemAudio == .denied)
    }

    @Test("allReady excludes systemAudio from requirements")
    @MainActor
    func allReadyExcludesSystemAudio() {
        // allReady only checks microphone, speechRecognition, speechModel
        // systemAudio is excluded because there's no pre-check API
        let state = PermissionState()
        // Even with systemAudio granted, allReady should be false
        // because mic/speech/model are still .unknown
        state.markSystemAudio(.granted)
        #expect(state.allReady == false)
    }

    @Test("PermissionStatus enum has all expected cases")
    func permissionStatusCases() {
        let cases: [PermissionStatus] = [.unknown, .granted, .denied, .unavailable]
        #expect(cases.count == 4)
    }
}
```

---

### 5. AudioSourceTests.swift (extend existing)

Already covered in TranscriptEntryTests, but add Codable round-trip:

```swift
import Testing
import Foundation
@testable import DualSTT

@Suite("AudioSource")
struct AudioSourceTests {

    @Test("raw values are correct")
    func rawValues() {
        #expect(AudioSource.me.rawValue == "ME")
        #expect(AudioSource.them.rawValue == "THEM")
    }

    @Test("Codable round-trip preserves value")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let original = AudioSource.me
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AudioSource.self, from: data)
        #expect(decoded == original)

        let original2 = AudioSource.them
        let data2 = try encoder.encode(original2)
        let decoded2 = try decoder.decode(AudioSource.self, from: data2)
        #expect(decoded2 == original2)
    }

    @Test("decodes from JSON string")
    func decodesFromJSON() throws {
        let json = "\"ME\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AudioSource.self, from: json)
        #expect(decoded == .me)
    }
}
```

---

## Test File Summary

After changes:

```
Tests/DualSTTTests/
├── TranscriptEntryTests.swift       # EXISTING - update import only
├── TranscriptStoreTests.swift       # EXISTING - update import only
├── PlainTextExporterTests.swift     # EXISTING - update import only
├── SRTExporterTests.swift           # EXISTING - update import only
├── BufferConverterTests.swift       # NEW - 13 tests
├── AudioCaptureErrorTests.swift     # NEW - 8 tests
├── TranscriptionErrorTests.swift    # NEW - 4 tests
├── PermissionStateTests.swift       # NEW - 5 tests
└── AudioSourceTests.swift           # NEW - 3 tests
```

Existing: ~16 tests
New: ~33 tests
Total: ~49 tests

## What NOT to Test (and Why)

Do NOT attempt to write tests for:

- **SpeechPipeline** - Requires a live SpeechAnalyzer instance with downloaded
  model. This is integration test territory. If you want coverage, write one
  manual test that runs locally but is `#if DEBUG` gated and excluded from CI.

- **MicCaptureManager** - Requires a physical microphone. Will fail on headless
  CI. If tested, must be behind a hardware check.

- **SystemAudioCaptureManager** - Requires CoreAudio process tap entitlements
  and active system audio. Cannot run in CI or test runners.

- **TranscriptionEngine** - Full integration test needing all of the above.
  Test this manually with the demo app.

The BufferConverter tests are the most valuable because that's exactly where the
crash was. If those 13 tests pass, the critical conversion path is verified.

## Running Tests

```bash
cd DualAudioTranscriber   # or repo root after SPM restructure
swift test
```

All tests should run on any Apple Silicon Mac with macOS 26, no microphone or
audio output required. The BufferConverter tests create synthetic audio buffers
in memory - no hardware needed.