# DualSTT

Native macOS speech transcription engine that simultaneously captures and transcribes **microphone** and **system audio** in real time. Built entirely on Apple frameworks - zero third-party dependencies, fully on-device.

DualSTT runs two independent speech pipelines: one for your microphone ("ME") and one for system audio ("THEM") from any source - Zoom, Teams, YouTube, or any other app producing audio. Transcripts are speaker-tagged and exportable as plain text or SRT subtitles.

## Requirements

- macOS 26+ (Tahoe)
- Apple Silicon (M-series, arm64)
- Apple Intelligence speech model (downloaded automatically on first use)
- Xcode 26+ / Swift 6.2+

## Installation

Add DualSTT as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/DualSTT.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["DualSTT"],
        linkerSettings: [
            .linkedFramework("AVFoundation"),
            .linkedFramework("CoreAudio"),
            .linkedFramework("AudioToolbox"),
            .linkedFramework("Speech"),
        ]
    ),
]
```

## Usage

```swift
import DualSTT

let engine = TranscriptionEngine()

// Start capturing both pipelines
await engine.startRecording()

// Observe live transcript entries
for entry in engine.store.entries {
    print("[\(entry.source.rawValue)] \(entry.text)")
}

// Stop and export
await engine.stopRecording()
let transcript = PlainTextExporter.export(engine.store.entries)
let subtitles = SRTExporter.export(engine.store.entries)
```

### Permissions

Your app must declare these keys in its `Info.plist`:

| Key | Purpose |
|-----|---------|
| `NSMicrophoneUsageDescription` | Microphone access |
| `NSAudioCaptureUsageDescription` | System audio capture (triggers permission prompt) |
| `NSSpeechRecognitionUsageDescription` | On-device speech recognition |

Your entitlements must disable App Sandbox (`com.apple.security.app-sandbox = false`) because the CoreAudio Process Tap API requires it, and enable audio input (`com.apple.security.device.audio-input = true`).

### Permission State

Track permission readiness before recording:

```swift
let engine = TranscriptionEngine()

// Check individual permissions
engine.permissions.microphone       // .unknown, .granted, .denied
engine.permissions.systemAudio      // .unknown, .granted, .denied
engine.permissions.speechRecognition
engine.permissions.speechModel

// All four must be .granted before recording works
engine.permissions.allReady         // Bool
```

System audio has no pre-check API. The engine attempts capture and detects denial via OSStatus `0x6E6F7065` (`'nope'`).

## Architecture

```
TranscriptionEngine
    |
    +-- MicCaptureManager ---- SpeechPipeline (ME) ---+
    |   (AVAudioEngine)        (SpeechAnalyzer)       |
    |                                                  |
    +-- SystemAudioCaptureManager -- SpeechPipeline ---+--> TranscriptStore
        (CoreAudio Process Tap)      (THEM)                 (entries[])
```

**Dual independent pipelines** - each audio source has its own capture manager and speech pipeline. Transcripts merge into a single ordered store with speaker tags.

**Volatile/final model** - partial (in-progress) results update a volatile entry in-place. When the recognizer finalizes a segment, the entry is locked and a new volatile slot opens. This prevents duplicate lines in the transcript.

**Buffer conversion** - `BufferConverter` handles sample rate, channel count, and bit depth conversion to the target format (16 kHz, Int16, mono) required by SpeechAnalyzer. Passthrough when formats already match.

## Project Structure

```
Sources/
  DualSTT/                  # Reusable library
    Audio/                  # Capture managers + protocol
    Models/                 # TranscriptEntry, AudioSource, PermissionState
    Transcription/          # SpeechPipeline, TranscriptStore, BufferConverter
    Export/                 # PlainTextExporter, SRTExporter
  DualSTTApp/               # Demo SwiftUI application
    Views/                  # ContentView, controls, transcript list
Tests/
  DualSTTTests/             # Unit tests (Swift Testing)
```

## Public API

| Type | Description |
|------|-------------|
| `TranscriptionEngine` | Main entry point - orchestrates capture, transcription, and export |
| `TranscriptStore` | `@Observable` store holding ordered `TranscriptEntry` items |
| `TranscriptEntry` | Immutable transcript segment with source, text, timestamp, and final flag |
| `AudioSource` | `.me` (microphone) or `.them` (system audio) |
| `PermissionState` | `@Observable` tracker for all four required permissions |
| `AudioCapturing` | Protocol for audio capture implementations |
| `MicCaptureManager` | AVAudioEngine-based microphone capture |
| `SystemAudioCaptureManager` | CoreAudio Process Tap-based system audio capture |
| `SpeechPipeline` | Audio-to-text pipeline wrapping SpeechAnalyzer |
| `BufferConverter` | Audio format converter (sample rate, channels, bit depth) |
| `PlainTextExporter` | Export as `[HH:MM:SS] [ME/THEM] text` |
| `SRTExporter` | Export as SubRip subtitles with timecodes |

## Export Formats

**Plain text:**
```
[00:00:03] [ME] Hey, can you hear me?
[00:00:05] [THEM] Yeah, loud and clear.
```

**SRT:**
```
1
00:00:03,000 --> 00:00:04,500
[ME] Hey, can you hear me?

2
00:00:05,000 --> 00:00:06,200
[THEM] Yeah, loud and clear.
```

## Development

### Build and Run the Demo App

```bash
./run.sh
```

This builds the project, creates a macOS `.app` bundle, code-signs with entitlements, and launches.

### Run Tests

```bash
swift test
```

Tests use the Swift Testing framework (`@Suite`, `@Test`, `#expect`) and do not require audio hardware.

### Code Quality

The project uses SwiftFormat and SwiftLint with a pre-commit hook that auto-formats staged files and blocks on lint errors.

```bash
# Configure the git hooks path (one-time setup)
git config core.hooksPath .githooks

# Manual formatting
swiftformat .

# Manual linting
swiftlint
```

## License

See [LICENSE](LICENSE) for details.
