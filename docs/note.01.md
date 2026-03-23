# Tech Note: DualAudioTranscriber Code Review & Fixes

## Status
The app is functional. Audio capture and SpeechAnalyzer transcription are working 
after the format conversion fix (Float32 48kHz -> bestAvailableAudioFormat which is 
16kHz Int16 mono). This note covers 6 remaining issues to fix, ranked by severity.

---

## Issue 1: AVAudioConverter called on real-time audio thread (PRIORITY: HIGH)

**File:** `SpeechPipeline.swift` line 97-138
**File:** `SystemAudioCaptureManager.swift` line 95 (IO proc callback)

The system audio IO proc callback runs on a **real-time CoreAudio thread**. The 
callback calls `onAudioBuffer` which calls `SpeechPipeline.appendAudio()` which 
calls `AVAudioConverter.convert()`. AVAudioConverter allocates memory internally. 
Memory allocation on a real-time audio thread causes **priority inversion** and 
can cause audio dropouts, stuttering, or in extreme cases system audio glitches.

The mic path (AVAudioEngine tap) is fine - it runs on a non-real-time queue.

**Fix:** In `SystemAudioCaptureManager.swift`, dispatch the buffer off the 
real-time thread before calling `onAudioBuffer`. Add a serial dispatch queue:

```swift
private let processingQueue = DispatchQueue(
    label: "com.zintegral.DualAudioTranscriber.systemAudioProcessing",
    qos: .userInteractive
)
```

Then in the IO proc callback, replace the direct call:
```swift
// BEFORE (on real-time thread):
self.onAudioBuffer?(pcmBuffer, audioTime)

// AFTER (dispatched off real-time thread):
self.processingQueue.async {
    self.onAudioBuffer?(pcmBuffer, audioTime)
}
```

This adds ~1ms latency which is negligible for transcription.

---

## Issue 2: Missing converter.primeMethod = .none (PRIORITY: HIGH)

**File:** `SpeechPipeline.swift` line 107

When creating the AVAudioConverter, the code does not set `primeMethod`. Apple's 
own sample code and the createwithswift.com tutorial both set this:

```swift
converter.primeMethod = .none
```

Without this, the converter may request additional "priming" input frames on the 
first conversion call. Since the code's input callback only provides one buffer 
and then returns `.noDataNow`, the priming request goes unsatisfied. This can 
cause the first ~50ms of audio to be silently dropped or produce garbled output.

**Fix:** After creating the converter on line 107, add:
```swift
} else if let c = AVAudioConverter(from: srcFormat, to: targetFormat) {
    c.primeMethod = .none  // ADD THIS
    self.converter = c
```

---

## Issue 3: Converter not invalidated on format change (PRIORITY: MEDIUM)

**File:** `SpeechPipeline.swift` lines 101-113

The converter is created lazily on the first buffer and cached forever. If the 
audio source changes format mid-session (e.g., Bluetooth headset disconnects, 
output device switches from 48kHz to 44.1kHz), the cached converter has a stale 
input format and will produce garbage or crash.

**Fix:** Check if the incoming buffer's format matches the converter's input format:

```swift
func appendAudio(_ buffer: AVAudioPCMBuffer) {
    guard isActive, let targetFormat else { return }

    let srcFormat = buffer.format

    // Check if format matches what we have (or if no converter yet)
    if let existingConverter = converter {
        // Invalidate if input format changed
        if existingConverter.inputFormat != srcFormat {
            log.fault("[\(source.rawValue)] input format changed, recreating converter")
            self.converter = nil
        }
    }

    if converter == nil {
        if srcFormat.sampleRate == targetFormat.sampleRate
            && srcFormat.channelCount == targetFormat.channelCount
            && srcFormat.commonFormat == targetFormat.commonFormat {
            // no conversion needed
        } else if let c = AVAudioConverter(from: srcFormat, to: targetFormat) {
            c.primeMethod = .none
            self.converter = c
            log.fault("[\(source.rawValue)] converter created: ...")
        } else {
            log.fault("[\(source.rawValue)] FAILED to create converter")
            return
        }
    }
    // ... rest of method unchanged
}
```

---

## Issue 4: isFinal detection uses undocumented CMTime API (PRIORITY: MEDIUM)

**File:** `SpeechPipeline.swift` lines 70-72

```swift
let rangeEnd = CMTimeRangeGetEnd(result.range)
let isFinal = CMTIME_IS_VALID(result.resultsFinalizationTime)
    && CMTimeCompare(rangeEnd, result.resultsFinalizationTime) <= 0
```

This uses `result.resultsFinalizationTime` and CMTime range comparisons. 
Apple's WWDC sample code and the createwithswift.com tutorial both use 
`result.isFinal` directly:

```swift
onResult(text, result.isFinal)
```

The CMTime approach might work, but `result.isFinal` is the documented, 
supported way. The CMTime property may not exist in all SDK versions or 
may behave differently for streaming vs offline modes.

**Fix:** Simplify to:
```swift
for try await result in transcriber.results {
    guard let self else { return }
    let text = String(result.text.characters)
    self.onTranscript?(text, result.isFinal)
}
```

Remove the `import CoreMedia` if it was only needed for CMTime.

---

## Issue 5: analyzeSequence vs start(inputSequence:) (PRIORITY: LOW)

**File:** `SpeechPipeline.swift` line 85

```swift
let _ = try await analyzer.analyzeSequence(inputSequence)
```

Apple's WWDC 2025 session 277 live coding demo and the createwithswift.com 
tutorial both use:

```swift
try await analyzer?.start(inputSequence: inputSequence)
```

These may be equivalent, but `start(inputSequence:)` is the documented method 
for live streaming audio. `analyzeSequence` might be intended for file-based 
batch processing where the full sequence is known upfront. If the current 
approach works, this is cosmetic, but using the documented method is safer 
for forward compatibility.

**Fix:** Change line 85 to:
```swift
try await analyzer.start(inputSequence: inputSequence)
```

---

## Issue 6: SpeechPipeline has no thread synchronization (PRIORITY: LOW)

**File:** `SpeechPipeline.swift`

The class is `@unchecked Sendable` but has no locks or actor isolation. 
`appendAudio()` is called from audio threads while `finalize()` is called 
from the main actor. Properties like `isActive`, `converter`, and 
`inputContinuation` are read/written from both without synchronization.

In practice this works because:
- `appendAudio()` runs on one consistent thread per pipeline instance
- `finalize()` sets `isActive = false` first, which gates `appendAudio()`  
- Swift's reference counting is atomic

But it's technically a data race. Two options:

**Option A (minimal):** Add a lock around the mutable state:
```swift
private let lock = NSLock()

func appendAudio(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    defer { lock.unlock() }
    guard isActive, let targetFormat else { return }
    // ...
}
```

**Option B (proper):** Make SpeechPipeline an actor. This requires making 
`appendAudio` async and dispatching from the audio callbacks, which adds 
complexity but is the correct Swift concurrency approach.

For a v1, Option A is fine. Option B is better for long-term.

---

## Non-Issues (Things That Are Actually Fine)

1. **SystemAudioCaptureManager buffer copy** - The non-interleaved handling 
   (lines 101-151) is correct. It properly checks `kAudioFormatFlagIsNonInterleaved`, 
   uses per-channel byte size for non-interleaved, and copies each channel separately.

2. **TranscriptStore volatile handling** - The update-in-place pattern for 
   volatile results is correct and efficient.

3. **Permission flow** - The sequential permission request pattern (mic, then 
   speech recognition, with a 500ms sleep for the callback) is ugly but functional.

4. **Entitlements and Info.plist** - All three required keys are present: 
   NSMicrophoneUsageDescription, NSAudioCaptureUsageDescription, 
   NSSpeechRecognitionUsageDescription. Sandbox is disabled. Audio input 
   entitlement is set.

5. **Cleanup in finalize()** - Correctly nils out all references including 
   converter and targetFormat, preventing leaks.

---

## Summary of Changes

Apply in this order:
1. Add `c.primeMethod = .none` when creating AVAudioConverter (1 line)
2. Dispatch system audio off real-time thread (add queue + async dispatch)
3. Simplify isFinal to use `result.isFinal` (delete 3 lines, add 1)
4. Add format-change detection for converter invalidation (add guard check)
5. Change `analyzeSequence` to `start(inputSequence:)` (1 line)
6. Optionally add NSLock to appendAudio (low priority)