# PRD-0001: DualAudioTranscriber - Tasks

Derived from [prd.md](./prd.md). Update as implementation progresses.

## Tasks

### Project Setup
- [ ] Create Xcode project (macOS App, SwiftUI, Swift 6, arm64)
- [ ] Configure deployment target macOS 26.0
- [ ] Disable App Sandbox, enable Hardened Runtime with audio input
- [ ] Create entitlements file (sandbox disabled, audio input enabled)
- [ ] Add Info.plist keys (NSMicrophoneUsageDescription, NSAudioCaptureUsageDescription, NSSpeechRecognitionUsageDescription)
- [ ] Link frameworks (AVFoundation, CoreAudio, AudioToolbox, Speech)

### Data Models
- [ ] Implement AudioSource enum (.me, .them)
- [ ] Implement TranscriptEntry struct (id, source, timestamp, text, isFinal)
- [ ] Write unit tests for TranscriptEntry

### Audio Capture Layer
- [ ] Implement MicCaptureManager (AVAudioEngine, inputNode tap, hardware format)
- [ ] Implement AudioCaptureError enum with localized descriptions
- [ ] Implement SystemAudioCaptureManager (CATapDescription, process tap, aggregate device, IO proc)
- [ ] Handle own-process exclusion in system audio tap
- [ ] Implement cleanup (destroy aggregate device, process tap on stop/deinit)
- [ ] Define AudioCapturing protocol for testability

### Transcription Layer
- [ ] Implement SpeechPipeline actor (SpeechAnalyzer + SpeechTranscriber wrapper)
- [ ] Implement model download with progress reporting via AssetInventory
- [ ] Implement volatile/partial result streaming via progressiveLiveTranscription preset
- [ ] Implement finalize-and-finish on stop

### Orchestration
- [ ] Implement TranscriptionEngine (@Observable, @MainActor)
- [ ] Wire mic capture -> mic SpeechPipeline
- [ ] Wire system capture -> system SpeechPipeline
- [ ] Implement volatile-to-final entry management (in-place update, no duplicates)
- [ ] Implement zero-buffering policy (immediate forwarding)
- [ ] Implement startRecording (prepare pipelines, wire callbacks, start capture)
- [ ] Implement stopRecording (stop capture, finalize pipelines, cleanup)
- [ ] Implement clearTranscript
- [ ] Write unit tests for entry management logic (volatile replacement, ordering, empty-text filtering)

### Export
- [ ] Implement plain text export ([HH:MM:SS] [ME/THEM] text format)
- [ ] Implement SRT export (single file, sequential numbering, local timecodes, speaker tags in text)
- [ ] Implement "copy all" action (full transcript including volatile text to clipboard)
- [ ] Write unit tests for plain text exporter
- [ ] Write unit tests for SRT exporter

### UI
- [ ] Implement App entry point (WindowGroup, default size)
- [ ] Implement ContentView (header with recording indicator, transcript list, control bar, error alert)
- [ ] Implement RecordingIndicator (pulsing red dot)
- [ ] Implement TranscriptListView (scrollable list, auto-scroll to latest)
- [ ] Implement TranscriptRowView (source tag with color, timestamp, text, volatile styling)
- [ ] Implement ControlBarView (Record/Stop, Clear, Export, Copy All, entry count)
- [ ] Add keyboard shortcut Cmd+Return for Record/Stop
- [ ] Add NSSavePanel for SRT and text file export

### Error Handling
- [ ] Handle permission denial for mic (clear error message)
- [ ] Handle permission denial for system audio (OSStatus 'nope', guide user to System Settings)
- [ ] Handle no microphone available
- [ ] Handle Bluetooth device change mid-recording (monitor kAudioDevicePropertyDeviceHasChanged)

### Manual Testing
- [ ] Test mic-only recording (speak, verify [ME] entries)
- [ ] Test system audio-only (YouTube video, verify [THEM] entries)
- [ ] Test dual stream (YouTube + mic, verify interleaved [ME]/[THEM] with no cross-contamination)
- [ ] Test volatile-to-final refinement (partial results update in-place, then lock)
- [ ] Test SRT export (valid format, correct timecodes, speaker tags)
- [ ] Test copy-all (includes latest volatile text)
- [ ] Test stop/restart cycle (clean cleanup, no leaked taps)

## Discovered During Implementation

- [ ] ...
