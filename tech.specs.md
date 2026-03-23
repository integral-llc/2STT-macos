# DualAudioTranscriber - Technical Specification for Claude Code

## Project Overview

Build a native macOS app (SwiftUI) that simultaneously captures **microphone audio** ("Me") and **system audio** ("Them") from any app (YouTube in Safari/Chrome, Zoom, Teams, etc.), transcribes each stream independently using Apple's built-in SpeechAnalyzer/SpeechTranscriber, and displays the results in a real-time scrolling list tagged with speaker source.

**Zero third-party dependencies.** Everything uses Apple's shipping frameworks on macOS 26 (Tahoe).

---

## Target Platform & Requirements

- **macOS 26.0+ (Tahoe)** - required for SpeechAnalyzer/SpeechTranscriber
- **Xcode 16.0+** with macOS 26 SDK
- **Swift 6.x** with strict concurrency
- **Apple Silicon** (M-series) - SpeechTranscriber runs on ANE (Apple Neural Engine)
- **Minimum deployment target:** macOS 26.0
- **Architecture:** arm64 only (SpeechTranscriber's on-device model targets ANE)
- **Sandbox:** Disabled (CATapDescription requires unsandboxed access to CoreAudio)
- **Hardened Runtime:** YES, with the following entitlements enabled

---

## Entitlements (CRITICAL)

Create `DualAudioTranscriber.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

## Info.plist Keys (CRITICAL)

These MUST be set or the app will crash/be denied permissions:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>DualAudioTranscriber needs microphone access to transcribe your speech.</string>
<key>NSAudioCaptureUsageDescription</key>
<string>DualAudioTranscriber needs to capture system audio to transcribe what others are saying.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>DualAudioTranscriber uses on-device speech recognition to convert audio to text.</string>
```

**IMPORTANT:** `NSAudioCaptureUsageDescription` is the key that triggers the macOS system audio capture permission prompt. It was introduced with macOS 14.4's CoreAudio Process Tap API. Without it, `AudioHardwareCreateProcessTap` will fail silently.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Layer                     │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │           TranscriptListView                  │   │
│  │  ┌────────────────────────────────────────┐  │   │
│  │  │ [ME]   "So I was thinking about..."    │  │   │
│  │  │ [THEM] "Yeah that's a great point..."  │  │   │
│  │  │ [ME]   "And then we could..."          │  │   │
│  │  │ [THEM] "Exactly, let me show you..."   │  │   │
│  │  └────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────┐  │
│  │  Record   │  │   Stop    │  │  Clear / Export  │  │
│  └──────────┘  └───────────┘  └─────────────────┘  │
└─────────────────────┬───────────────────────────────┘
                      │
         ┌────────────┴────────────┐
         │   TranscriptionEngine   │
         │   (@Observable class)   │
         └────────────┬────────────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
┌───────┴────────┐         ┌───────┴────────┐
│  MicCapture    │         │  SystemCapture  │
│  (AVAudioEngine│         │  (CATap +       │
│   inputNode)   │         │   Aggregate     │
│                │         │   Device)       │
└───────┬────────┘         └───────┬────────┘
        │                          │
        ▼                          ▼
┌────────────────┐         ┌────────────────┐
│ SpeechAnalyzer │         │ SpeechAnalyzer │
│ + Transcriber  │         │ + Transcriber  │
│ (instance #1)  │         │ (instance #2)  │
│ Tag: .me       │         │ Tag: .them     │
└────────────────┘         └────────────────┘
```

### Key Architectural Decision: Dual SpeechAnalyzer Instances

You MUST run two completely independent `SpeechAnalyzer` + `SpeechTranscriber` pipelines. One for mic, one for system audio. This is correct because:

1. Each SpeechAnalyzer instance manages its own audio timeline independently
2. Mixing audio before transcription would destroy the me/them tagging
3. Two separate instances can run concurrently on ANE without conflict
4. Apple's SpeechAnalyzer is designed to handle multiple concurrent sessions

**Do NOT attempt to:** mix both streams into one, use diarization to split them back out, or alternate feeding chunks from different sources to a single analyzer. All of these are worse in every way.

---

## File Structure

```
DualAudioTranscriber/
├── DualAudioTranscriber.entitlements
├── Info.plist
├── Package.swift                          # SwiftPM project (NOT Xcode project)
└── Sources/
    └── DualAudioTranscriber/
        ├── App.swift                      # @main entry, WindowGroup
        ├── Models/
        │   ├── TranscriptEntry.swift      # Data model for each transcript line
        │   └── AudioSource.swift          # Enum: .me, .them
        ├── Audio/
        │   ├── MicCaptureManager.swift    # AVAudioEngine mic capture
        │   ├── SystemAudioCaptureManager.swift  # CATapDescription system capture
        │   └── AudioConverter.swift       # PCM format conversion utilities
        ├── Transcription/
        │   ├── TranscriptionEngine.swift  # Orchestrator: manages both pipelines
        │   └── SpeechPipeline.swift       # Single SpeechAnalyzer+Transcriber pipeline
        └── Views/
            ├── ContentView.swift          # Main window layout
            ├── TranscriptListView.swift   # ScrollView with transcript entries
            ├── TranscriptRowView.swift    # Individual row (tag + text)
            └── ControlBarView.swift       # Start/Stop/Clear buttons
```

---

## Data Models

### TranscriptEntry.swift

```swift
import Foundation

enum AudioSource: String, Codable, Sendable {
    case me = "ME"
    case them = "THEM"
}

struct TranscriptEntry: Identifiable, Sendable {
    let id: UUID
    let source: AudioSource
    let timestamp: Date
    var text: String
    var isFinal: Bool  // false = volatile/partial result, true = finalized

    init(source: AudioSource, text: String, isFinal: Bool = false) {
        self.id = UUID()
        self.source = source
        self.timestamp = Date()
        self.text = text
        self.isFinal = isFinal
    }
}
```

---

## Audio Capture Layer

### MicCaptureManager.swift - Microphone Capture

Uses `AVAudioEngine` with a tap on `inputNode`. This is the standard, well-documented approach.

**Key implementation details:**

```swift
import AVFoundation
import Speech

@Observable
final class MicCaptureManager: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var isRunning = false

    // Callback delivers PCM buffers to the transcription pipeline
    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start() throws {
        let inputNode = audioEngine.inputNode
        // CRITICAL: Get the HARDWARE format first, then request conversion
        let hwFormat = inputNode.inputFormat(forBus: 0)

        // Validate the hardware format is usable
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioCaptureError.noMicrophoneAvailable
        }

        // Install tap at the hardware's native format
        // SpeechAnalyzer accepts any standard PCM format - it handles
        // resampling internally. Do NOT manually resample to 16kHz.
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) {
            [weak self] buffer, time in
            self?.onAudioBuffer?(buffer, time)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }
}
```

**Gotchas:**
- NEVER request a format different from the hardware format in `installTap`. macOS will throw `kAudioUnitErr_FormatNotSupported (-10868)` if you ask for 16kHz when the mic runs at 48kHz. SpeechAnalyzer handles resampling itself.
- Buffer size of 1024 is fine for real-time. Larger buffers (4096, 8192) add latency but reduce overhead.
- The `format` parameter in `installTap` must match `inputNode.inputFormat(forBus: 0)` exactly, or be `nil` to auto-detect.

### SystemAudioCaptureManager.swift - System Audio via CoreAudio Process Tap

This is the complex part. macOS 14.4+ introduced `CATapDescription` and `AudioHardwareCreateProcessTap` for capturing audio from other processes. This is the ONLY correct way to capture system audio on modern macOS - NOT ScreenCaptureKit (which requires screen recording permission and captures video), NOT BlackHole/Soundflower (virtual audio devices that are fragile hacks).

**The Process Tap pipeline has these steps:**

1. Create a `CATapDescription` configured for stereo global tap (captures all system audio output)
2. Call `AudioHardwareCreateProcessTap()` to create the tap
3. Create an aggregate audio device that includes the tap as a sub-tap
4. Read the tap's audio format (`kAudioTapPropertyFormat`)
5. Set up an IO proc on the aggregate device to receive audio callbacks
6. Start the aggregate device
7. In the callback, convert received audio to `AVAudioPCMBuffer` and forward to SpeechAnalyzer

```swift
import CoreAudio
import AVFoundation
import AudioToolbox

@Observable
final class SystemAudioCaptureManager: @unchecked Sendable {
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapStreamFormat: AudioStreamBasicDescription?
    private var isRunning = false

    var onAudioBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func start() throws {
        // Step 1: Create CATapDescription for global stereo tap
        // This captures ALL system audio output excluding our own process
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [ownPID]
        )

        // Get the UUID string - needed for aggregate device config
        let tapUUID = tapDescription.uuid.uuidString

        // Step 2: Create the process tap
        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapStatus == noErr else {
            throw AudioCaptureError.tapCreationFailed(tapStatus)
        }
        self.tapObjectID = tapID

        // Step 3: Read the tap's native audio format
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var format = AudioStreamBasicDescription()
        let formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let formatStatus = AudioObjectGetPropertyData(
            tapID, &formatAddress, 0, nil, &formatSize, &format
        )
        guard formatStatus == noErr else {
            throw AudioCaptureError.formatReadFailed(formatStatus)
        }
        self.tapStreamFormat = format

        // Step 4: Create aggregate device with the tap
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "DualAudioTranscriber_Tap",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey as String: true,  // Don't show in system
            kAudioAggregateDeviceTapListKey as String: [
                [kAudioSubTapUIDKey as String: tapUUID]
            ],
            kAudioAggregateDeviceTapAutoStartKey as String: true
        ]

        var aggID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(
            aggregateDesc as CFDictionary, &aggID
        )
        guard aggStatus == noErr else {
            throw AudioCaptureError.aggregateDeviceFailed(aggStatus)
        }
        self.aggregateDeviceID = aggID

        // Step 5: Create IO proc to receive audio
        let avFormat = AVAudioFormat(streamDescription: &format)!

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
            &procID, aggID, nil
        ) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self = self,
                  let bufferList = inInputData?.pointee else { return }

            // Convert AudioBufferList to AVAudioPCMBuffer
            let frameCount = AVAudioFrameCount(
                bufferList.mBuffers.mDataByteSize /
                UInt32(MemoryLayout<Float>.size * Int(format.mChannelsPerFrame))
            )

            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: avFormat,
                                                    frameCapacity: frameCount) else {
                return
            }
            pcmBuffer.frameLength = frameCount

            // Copy audio data
            let srcBuf = bufferList.mBuffers
            if let srcData = srcBuf.mData, let dstData = pcmBuffer.floatChannelData {
                let channelCount = Int(format.mChannelsPerFrame)
                if channelCount == 1 || format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
                    memcpy(dstData[0], srcData, Int(srcBuf.mDataByteSize))
                } else {
                    // Interleaved stereo - deinterleave to planar
                    let src = srcData.assumingMemoryBound(to: Float.self)
                    for frame in 0..<Int(frameCount) {
                        for ch in 0..<channelCount {
                            dstData[ch][frame] = src[frame * channelCount + ch]
                        }
                    }
                }
            }

            let audioTime = AVAudioTime(hostTime: inInputTime.pointee.mHostTime)
            self.onAudioBuffer?(pcmBuffer, audioTime)
        }

        guard ioStatus == noErr, let procID else {
            throw AudioCaptureError.ioProcFailed(ioStatus)
        }
        self.ioProcID = procID

        // Step 6: Start the device
        let startStatus = AudioDeviceStart(aggID, procID)
        guard startStatus == noErr else {
            throw AudioCaptureError.deviceStartFailed(startStatus)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        if tapObjectID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapObjectID)
        }

        tapObjectID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        isRunning = false
    }

    deinit {
        stop()
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case noMicrophoneAvailable
    case tapCreationFailed(OSStatus)
    case formatReadFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable: return "No microphone detected"
        case .tapCreationFailed(let s): return "Process tap creation failed: \(s)"
        case .formatReadFailed(let s): return "Could not read tap format: \(s)"
        case .aggregateDeviceFailed(let s): return "Aggregate device creation failed: \(s)"
        case .ioProcFailed(let s): return "IO proc setup failed: \(s)"
        case .deviceStartFailed(let s): return "Device start failed: \(s)"
        }
    }
}
```

**CRITICAL GOTCHAS for System Audio Capture:**

1. **OSStatus 1852797029 (`'nope'`)** - This means the user denied audio capture permission, OR the `NSAudioCaptureUsageDescription` key is missing from Info.plist. There is NO programmatic way to check this permission status via public API before attempting to create the tap. You must attempt it and handle the error.

2. **Exclude own process** - ALWAYS pass your own PID to `stereoGlobalTapButExcludeProcesses:` or you'll get a feedback loop (your app's audio output gets captured and re-transcribed).

3. **Private aggregate device** - Set `kAudioAggregateDeviceIsPrivateKey` to `true` so the aggregate device doesn't appear in System Settings > Sound.

4. **Format matching** - The tap's format is determined by the system output device. On most Macs this will be Float32, 48000Hz, 2-channel interleaved. Do NOT assume 16kHz mono. SpeechAnalyzer handles conversion.

5. **Cleanup is mandatory** - If you don't destroy the aggregate device and process tap on stop/deinit, they leak and persist until the app terminates. This can cause subsequent launches to fail.

6. **Thread safety** - The IO proc callback runs on a real-time audio thread. Do NOT allocate memory, acquire locks, or do anything blocking in the callback. Copy the buffer and dispatch to another queue.

---

## Transcription Layer

### SpeechPipeline.swift - Single SpeechAnalyzer Pipeline

This wraps one SpeechAnalyzer + SpeechTranscriber instance. You create two of these - one tagged `.me`, one tagged `.them`.

```swift
import Speech
import AVFoundation

actor SpeechPipeline {
    let source: AudioSource
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var resultsTask: Task<Void, Never>?

    // Callback for new transcript results
    var onTranscript: (@Sendable (String, Bool) -> Void)?  // (text, isFinal)

    init(source: AudioSource) {
        self.source = source
    }

    func prepare(locale: Locale = Locale(identifier: "en-US")) async throws {
        // Create transcriber with progressive live preset
        // This preset is optimized for streaming audio - it emits volatile
        // (partial) results that update as more audio arrives, then finalizes
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveLiveTranscription
        )
        self.transcriber = transcriber

        // Ensure the on-device model is downloaded
        // SpeechTranscriber model is shared system-wide - if Notes or Voice
        // Memos already downloaded it, this returns immediately. Otherwise
        // it downloads ~150-300MB on first use.
        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard supportedLocales.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
            throw TranscriptionError.localeNotSupported(locale)
        }

        let installedLocales = await SpeechTranscriber.installedLocales
        if !installedLocales.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) {
            // Download the model asset
            if let request = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                // This triggers the actual download
                try await request.startInstallation()
                // Wait for completion
                for try await progress in request.progress {
                    // Optionally report download progress
                    if progress.isFinished { break }
                }
            }
        }

        // Create analyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Start consuming results
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = result.text
                    let isFinal = !result.isVolatile
                    await MainActor.run {
                        self.onTranscript?(text, isFinal)
                    }
                }
            } catch {
                print("[\(self.source)] Results stream error: \(error)")
            }
        }
    }

    /// Feed an audio buffer into this pipeline
    func appendAudio(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        // SpeechAnalyzer.append() accepts AVAudioPCMBuffer directly
        // It handles format conversion internally (resampling, channel mixing)
        do {
            try analyzer?.append(buffer, at: time)
        } catch {
            print("[\(source)] Failed to append audio: \(error)")
        }
    }

    /// Call when recording stops to finalize any pending results
    func finalize() async {
        do {
            try await analyzer?.finalizeAndFinish()
        } catch {
            print("[\(source)] Finalization error: \(error)")
        }
        resultsTask?.cancel()
    }
}

enum TranscriptionError: Error, LocalizedError {
    case localeNotSupported(Locale)

    var errorDescription: String? {
        switch self {
        case .localeNotSupported(let l): return "Locale \(l.identifier) not supported"
        }
    }
}
```

**SpeechAnalyzer Key Concepts:**

1. **Volatile vs Final results** - The `.progressiveLiveTranscription` preset emits volatile results that evolve as more audio context arrives. A volatile result for "I think we should" might update to "I think we should probably" before finalizing as "I think we should probably reconsider." Your UI should show the latest volatile result for the current utterance, then lock it in when `isVolatile == false`.

2. **Audio timeline** - SpeechAnalyzer maintains an internal audio timeline. Each `append()` call advances it. You don't need to manage timestamps manually - just pass the `AVAudioTime` from the capture callback.

3. **Model runs out-of-process** - The SpeechTranscriber model runs in a separate system process, NOT in your app's memory space. This means it won't crash your app, won't count against your memory limit, and Apple can update it independently.

4. **Concurrency** - SpeechAnalyzer uses Swift concurrency natively. The `results` property is an `AsyncSequence`. It's designed to be consumed in a `Task`.

### TranscriptionEngine.swift - Orchestrator

```swift
import Foundation
import AVFoundation

@Observable
@MainActor
final class TranscriptionEngine {
    var entries: [TranscriptEntry] = []
    var isRecording = false
    var error: String?

    private let micCapture = MicCaptureManager()
    private let systemCapture = SystemAudioCaptureManager()
    private var micPipeline: SpeechPipeline?
    private var systemPipeline: SpeechPipeline?

    // Track current volatile entries so we can update them in-place
    private var currentVolatileID: [AudioSource: UUID] = [:]

    func startRecording() async {
        guard !isRecording else { return }
        entries.removeAll()
        error = nil

        do {
            // Create and prepare both speech pipelines
            let micPipeline = SpeechPipeline(source: .me)
            let systemPipeline = SpeechPipeline(source: .them)

            // Set up result callbacks BEFORE starting capture
            await micPipeline.setOnTranscript { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.handleTranscript(source: .me, text: text, isFinal: isFinal)
                }
            }
            await systemPipeline.setOnTranscript { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.handleTranscript(source: .them, text: text, isFinal: isFinal)
                }
            }

            // Download models if needed (show loading state in UI)
            try await micPipeline.prepare()
            try await systemPipeline.prepare()

            self.micPipeline = micPipeline
            self.systemPipeline = systemPipeline

            // Wire audio capture -> speech pipeline
            micCapture.onAudioBuffer = { [weak micPipeline] buffer, time in
                Task {
                    await micPipeline?.appendAudio(buffer, at: time)
                }
            }
            systemCapture.onAudioBuffer = { [weak systemPipeline] buffer, time in
                Task {
                    await systemPipeline?.appendAudio(buffer, at: time)
                }
            }

            // Start both captures
            try micCapture.start()
            try systemCapture.start()

            isRecording = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording else { return }

        // Stop capture first
        micCapture.stop()
        systemCapture.stop()

        // Finalize transcription (flushes any pending results)
        await micPipeline?.finalize()
        await systemPipeline?.finalize()

        micPipeline = nil
        systemPipeline = nil
        currentVolatileID = [:]
        isRecording = false
    }

    /// Handle incoming transcript results, updating volatile entries in-place
    private func handleTranscript(source: AudioSource, text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingID = currentVolatileID[source],
           let index = entries.firstIndex(where: { $0.id == existingID }) {
            // Update existing volatile entry
            entries[index].text = trimmed
            if isFinal {
                entries[index].isFinal = true
                currentVolatileID[source] = nil
            }
        } else {
            // Create new entry
            let entry = TranscriptEntry(source: source, text: trimmed, isFinal: isFinal)
            entries.append(entry)
            if !isFinal {
                currentVolatileID[source] = entry.id
            }
        }
    }

    func clearTranscript() {
        entries.removeAll()
    }

    func exportTranscript() -> String {
        entries.map { entry in
            let time = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "[\(time)] [\(entry.source.rawValue)] \(entry.text)"
        }.joined(separator: "\n")
    }
}
```

**Volatile Result Handling Strategy:**

The `handleTranscript` method implements a critical UX pattern:
- When a volatile (partial) result arrives for a source, we either update the existing volatile entry or create a new one
- When the result becomes final (`isFinal == true`), we lock it and clear the volatile tracker
- This prevents the list from filling up with duplicate partial results

---

## SwiftUI Views

### App.swift

```swift
import SwiftUI

@main
struct DualAudioTranscriberApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 600, height: 700)
    }
}
```

### ContentView.swift

```swift
import SwiftUI

struct ContentView: View {
    @State private var engine = TranscriptionEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dual Audio Transcriber")
                    .font(.headline)
                Spacer()
                if engine.isRecording {
                    RecordingIndicator()
                }
            }
            .padding()

            Divider()

            // Transcript list
            TranscriptListView(entries: engine.entries)

            Divider()

            // Controls
            ControlBarView(engine: engine)
        }
        .frame(minWidth: 500, minHeight: 400)
        .alert("Error", isPresented: .constant(engine.error != nil)) {
            Button("OK") { engine.error = nil }
        } message: {
            Text(engine.error ?? "")
        }
    }
}

struct RecordingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(isAnimating ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}
```

### TranscriptListView.swift

```swift
import SwiftUI

struct TranscriptListView: View {
    let entries: [TranscriptEntry]

    var body: some View {
        ScrollViewReader { proxy in
            List(entries) { entry in
                TranscriptRowView(entry: entry)
                    .id(entry.id)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .onChange(of: entries.count) { _, _ in
                // Auto-scroll to latest entry
                if let lastID = entries.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}
```

### TranscriptRowView.swift

```swift
import SwiftUI

struct TranscriptRowView: View {
    let entry: TranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Source tag
            Text(entry.source.rawValue)
                .font(.caption.monospaced().bold())
                .foregroundStyle(entry.source == .me ? .blue : .green)
                .frame(width: 45, alignment: .center)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(entry.source == .me
                              ? Color.blue.opacity(0.12)
                              : Color.green.opacity(0.12))
                )

            // Timestamp
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

            // Transcript text
            Text(entry.text)
                .font(.body)
                .opacity(entry.isFinal ? 1.0 : 0.6)  // Dim volatile results
                .italic(!entry.isFinal)                 // Italicize volatile results

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

### ControlBarView.swift

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ControlBarView: View {
    @Bindable var engine: TranscriptionEngine

    var body: some View {
        HStack(spacing: 16) {
            if engine.isRecording {
                Button(action: {
                    Task { await engine.stopRecording() }
                }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .tint(.red)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button(action: {
                    Task { await engine.startRecording() }
                }) {
                    Label("Record", systemImage: "record.circle")
                }
                .tint(.red)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Button(action: { engine.clearTranscript() }) {
                Label("Clear", systemImage: "trash")
            }
            .disabled(engine.isRecording || engine.entries.isEmpty)

            Spacer()

            // Export as text file
            Button(action: exportToFile) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(engine.entries.isEmpty)

            Text("\(engine.entries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .buttonStyle(.bordered)
    }

    private func exportToFile() {
        let text = engine.exportTranscript()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript_\(Date().ISO8601Format()).txt"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
```

---

## Build Configuration

### Package.swift (SwiftPM)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DualAudioTranscriber",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DualAudioTranscriber",
            path: "Sources/DualAudioTranscriber",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("Speech"),
            ]
        )
    ]
)
```

### Alternatively: Xcode Project Setup

If using Xcode instead of SwiftPM CLI:

1. File > New > Project > macOS > App
2. Interface: SwiftUI, Language: Swift
3. **Signing & Capabilities:**
   - Disable App Sandbox
   - Enable Hardened Runtime
   - Add "Audio Input" under Hardened Runtime exceptions
4. **Build Settings:**
   - MACOSX_DEPLOYMENT_TARGET = 26.0
   - SWIFT_VERSION = 6.0
   - ARCHS = arm64
5. Link frameworks: AVFoundation, CoreAudio, AudioToolbox, Speech

---

## Testing Instructions

### Test 1: Mic Only (Simplest)
1. Launch the app
2. Click Record
3. Grant microphone permission when prompted
4. Speak into your mic
5. Verify [ME] entries appear in the list with your speech transcribed
6. Click Stop

### Test 2: System Audio Only (YouTube)
1. Open Safari or Chrome, navigate to a YouTube video
2. Start playing the video
3. Launch the app, click Record
4. Grant system audio capture permission when prompted
5. Verify [THEM] entries appear with the video's speech transcribed
6. Click Stop

### Test 3: Dual Stream (The Real Test)
1. Open a YouTube video and start playing it
2. Launch the app, click Record
3. While the video plays, speak into your microphone
4. Verify BOTH [ME] and [THEM] entries appear interleaved
5. Verify [ME] entries contain YOUR words, [THEM] entries contain VIDEO words
6. There should be NO cross-contamination (your voice shouldn't appear in [THEM])
7. Click Stop, verify export works

### Test 4: Volatile/Final Results
1. During recording, watch how partial results appear (dimmed, italic)
2. As you finish a sentence, the entry should become solid (finalized)
3. The text should update in-place as the model refines its prediction

---

## Known Issues & Edge Cases

### 1. First Launch Model Download
SpeechTranscriber needs to download its on-device model (~150-300MB) on first use. If Notes or Voice Memos have already been used on the system, the model may already be cached. Add a loading/progress indicator during `prepare()`.

### 2. System Audio Permission
There is NO public API to check system audio capture permission status before attempting it. You must try to create the tap and handle the error. If the user denies permission, macOS does not re-prompt - they must go to System Settings > Privacy & Security > Screen & System Audio Recording and manually enable your app.

### 3. Headphones
When the user wears headphones, system audio still routes through the output device. CATapDescription captures from the output pipeline BEFORE it hits the hardware, so headphones vs speakers makes no difference to capture. The tap sees the same audio regardless.

### 4. AirPods / Bluetooth Audio
Bluetooth audio devices may change the system's output sample rate (e.g., to 24kHz for AAC codec). The tap format changes accordingly. Since we read `kAudioTapPropertyFormat` dynamically and SpeechAnalyzer handles resampling, this should work transparently. However, if the output device changes mid-recording (e.g., AirPods disconnect), the tap may break. Handle this by monitoring `kAudioDevicePropertyDeviceHasChanged`.

### 5. No System Audio Playing
If nothing is producing audio when you start recording, the system capture pipeline will simply receive silence. SpeechAnalyzer won't emit any results for silence. This is correct behavior - [THEM] entries only appear when there's actually speech in the system audio.

### 6. Echo / Feedback
If the user is NOT wearing headphones and their speakers are loud, the mic will pick up the system audio playing through speakers. This means the same speech could appear in both [ME] and [THEM]. This is a physics problem, not a software problem. The architectural answer is: tell users to wear headphones for clean separation. You could also implement acoustic echo cancellation (AEC) using `AVAudioEngine`'s voice processing mode, but that adds significant complexity and is out of scope for v1.

---

## Performance Expectations

On an M2 Max (96GB):
- **SpeechTranscriber latency:** ~130ms from audio input to first partial result
- **SpeechTranscriber throughput:** ~60-90x real-time (batch), near real-time for streaming
- **Memory:** The speech model runs OUT OF PROCESS. Your app's memory footprint will be ~50-80MB. The system speech process adds ~200-400MB but that's not charged to your app.
- **CPU:** Minimal. The heavy lifting runs on ANE (Apple Neural Engine). Expect <5% CPU usage during active transcription.
- **Two concurrent pipelines:** No problem. ANE handles concurrent inference workloads efficiently.

---

## Future Enhancements (Not in V1)

1. **Per-app capture** - Instead of global system audio, capture from a specific app (e.g., only Zoom). Use `CATapDescription(processes:)` with the target app's PID.
2. **Speaker diarization within system audio** - If there are multiple speakers in a YouTube video, use FluidAudio's offline diarizer to split them into Speaker A, Speaker B, etc.
3. **Live summary** - Feed finalized transcript to Apple's on-device Foundation Model (also available in macOS 26) for real-time summarization.
4. **Acoustic echo cancellation** - Enable `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` to reduce speaker bleed into the mic.
5. **Language auto-detection** - Use SpeechDetector module alongside SpeechTranscriber to detect language changes.
