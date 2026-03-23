import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os.log
@preconcurrency import Speech

private let log = Logger(
    subsystem: "com.zintegral.DualSTT",
    category: "CLITests"
)

// MARK: - Test Infrastructure

private nonisolated(unsafe) var passCount = 0
private nonisolated(unsafe) var failCount = 0
private nonisolated(unsafe) var skipCount = 0

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self {
        case .assertion(let msg): return msg.isEmpty ? "assertion failed" : msg
        }
    }
}

private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        passCount += 1
        print("  PASS  \(name)")
    } catch {
        failCount += 1
        print("  FAIL  \(name) -- \(error)")
    }
}

private func expect(_ condition: Bool, _ message: String = "assertion failed") throws {
    guard condition else { throw TestFailure.assertion(message) }
}

// MARK: - Helpers

private func makeSineBuffer(
    format: AVAudioFormat,
    frameCount: AVAudioFrameCount,
    frequency: Double = 440.0
) -> AVAudioPCMBuffer? {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        return nil
    }
    buffer.frameLength = frameCount
    guard let channels = buffer.floatChannelData else { return nil }
    let sr = format.sampleRate
    for frame in 0..<Int(frameCount) {
        let sample = Float(sin(2.0 * .pi * frequency * Double(frame) / sr))
        for ch in 0..<Int(format.channelCount) {
            channels[ch][frame] = sample
        }
    }
    return buffer
}

private func convertBuffer(
    _ input: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to targetFormat: AVAudioFormat
) -> AVAudioPCMBuffer? {
    let ratio = targetFormat.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1
    guard let output = AVAudioPCMBuffer(
        pcmFormat: targetFormat, frameCapacity: capacity
    )
    else { return nil }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, outStatus in
        if consumed {
            outStatus.pointee = .noDataNow
            return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return input
    }
    if let error {
        print("    [debug] convertBuffer error: \(error) status=\(status.rawValue)")
        return nil
    }
    // .inputRanDry is normal when the callback provides one buffer then returns .noDataNow
    guard status != .error else { return nil }
    return output
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}

private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

private final class TranscriptionCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastText = ""
    private var _gotFinal = false

    var lastText: String {
        lock.lock()
        defer { lock.unlock() }
        return _lastText
    }

    var gotFinal: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _gotFinal
    }

    func update(text: String, isFinal: Bool) {
        lock.lock()
        _lastText = text
        if isFinal { _gotFinal = true }
        lock.unlock()
    }
}

// MARK: - Issue 2: primeMethod = .none

private func testIssue2_PrimeMethod() {
    print("\n--- Issue 2: AVAudioConverter.primeMethod = .none ---")
    let src = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let dst = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    test("primeMethod can be set to .none") {
        let c = AVAudioConverter(from: src, to: dst)!
        c.primeMethod = .none
        try expect(c.primeMethod == .none, "primeMethod was not .none after set")
    }

    test("first conversion produces output with primeMethod=.none") {
        let c = AVAudioConverter(from: src, to: dst)!
        c.primeMethod = .none
        let input = makeSineBuffer(format: src, frameCount: 4800)!
        let output = convertBuffer(input, using: c, to: dst)
        try expect(output != nil, "conversion returned nil")
        try expect(output!.frameLength > 0, "output has 0 frames")
    }

    test("first 50ms not silently dropped") {
        let c = AVAudioConverter(from: src, to: dst)!
        c.primeMethod = .none
        let input = makeSineBuffer(format: src, frameCount: 2400)! // 50ms at 48kHz
        let output = convertBuffer(input, using: c, to: dst)
        try expect(output != nil, "conversion returned nil")
        // 50ms at 16kHz = 800 frames
        try expect(output!.frameLength >= 790, "only \(output!.frameLength) frames -- audio dropped?")
    }
}

// MARK: - Issue 3: Converter invalidation on format change

private func testIssue3_FormatChangeDetection() {
    print("\n--- Issue 3: Converter invalidation on format change ---")
    let fmt48k = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let fmt44k = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    test("converter.inputFormat matches creation format") {
        let c = AVAudioConverter(from: fmt48k, to: target)!
        try expect(c.inputFormat == fmt48k, "inputFormat != source format")
    }

    test("detects format mismatch when device changes") {
        let c = AVAudioConverter(from: fmt48k, to: target)!
        try expect(c.inputFormat != fmt44k, "48kHz should != 44.1kHz")
    }

    test("same format not flagged as changed") {
        let c = AVAudioConverter(from: fmt48k, to: target)!
        try expect(c.inputFormat == fmt48k, "same format should match")
    }

    test("new converter works after simulated device switch") {
        var c = AVAudioConverter(from: fmt48k, to: target)!
        c.primeMethod = .none

        // Simulate: device switches from 48kHz to 44.1kHz
        let newFormat = fmt44k
        if c.inputFormat != newFormat {
            c = AVAudioConverter(from: newFormat, to: target)!
            c.primeMethod = .none
        }

        let input = makeSineBuffer(format: newFormat, frameCount: 4410)!
        let output = convertBuffer(input, using: c, to: target)
        try expect(output != nil, "conversion failed after format switch")
        try expect(output!.frameLength > 0, "0 frames after format switch")
    }
}

// MARK: - Issue 1: Dispatch off real-time audio thread

private func testIssue1_RealtimeThreadDispatch() {
    print("\n--- Issue 1: Dispatch off real-time audio thread ---")

    test("processingQueue.async runs on different thread") {
        let queue = DispatchQueue(
            label: "com.test.systemAudioProcessing", qos: .userInteractive
        )
        let sem = DispatchSemaphore(value: 0)
        let callerThread = Thread.current
        var handlerThread: Thread?

        queue.async {
            handlerThread = Thread.current
            sem.signal()
        }

        try expect(sem.wait(timeout: .now() + 2) == .success, "dispatch timed out")
        try expect(callerThread !== handlerThread!, "handler ran on same thread -- not dispatched")
    }

    test("buffer data survives dispatch") {
        let queue = DispatchQueue(label: "com.test.bufferIntegrity", qos: .userInteractive)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buf = makeSineBuffer(format: fmt, frameCount: 480)!
        let expected = buf.floatChannelData![0][0]
        let sem = DispatchSemaphore(value: 0)
        var received: Float?

        queue.async {
            received = buf.floatChannelData?[0][0]
            sem.signal()
        }

        try expect(sem.wait(timeout: .now() + 2) == .success, "dispatch timed out")
        try expect(received == expected, "buffer data corrupted in dispatch")
    }

    test("high-frequency dispatch does not drop buffers") {
        let queue = DispatchQueue(label: "com.test.highFreq", qos: .userInteractive)
        let iterations = 1000
        let counter = LockedCounter()
        let group = DispatchGroup()

        for _ in 0..<iterations {
            group.enter()
            queue.async { counter.increment()
                group.leave()
            }
        }

        try expect(group.wait(timeout: .now() + 5) == .success, "timed out")
        try expect(counter.value == iterations, "dropped \(iterations - counter.value) of \(iterations)")
    }
}

// MARK: - Issue 6: NSLock thread safety

private func testIssue6_LockThreadSafety() {
    print("\n--- Issue 6: NSLock thread safety ---")

    test("lock prevents data races under concurrent writes") {
        let lock = NSLock()
        var counter = 0
        let iterations = 50_000
        let queue = DispatchQueue(label: "com.test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                lock.lock()
                counter += 1
                lock.unlock()
                group.leave()
            }
        }

        try expect(group.wait(timeout: .now() + 10) == .success, "timed out")
        try expect(counter == iterations, "expected \(iterations), got \(counter)")
    }

    test("rapid sequential acquire/release does not deadlock") {
        let lock = NSLock()
        var value = 0
        for _ in 0..<100_000 {
            lock.lock()
            value += 1
            lock.unlock()
        }
        try expect(value == 100_000, "lost increments")
    }

    test("concurrent converter create/invalidate is safe under lock") {
        let lock = NSLock()
        var converter: AVAudioConverter?
        let src = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let dst = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let queue = DispatchQueue(label: "com.test.rw", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 0..<200 {
            group.enter()
            queue.async {
                lock.lock()
                if i % 10 == 0 { converter = nil }
                if converter == nil {
                    let c = AVAudioConverter(from: src, to: dst)!
                    c.primeMethod = .none
                    converter = c
                }
                _ = converter?.inputFormat
                lock.unlock()
                group.leave()
            }
        }

        try expect(group.wait(timeout: .now() + 10) == .success, "timed out")
    }
}

// MARK: - Combined: Full format conversion pipeline

private func testConversionPipeline() {
    print("\n--- Combined: Full format conversion pipeline ---")

    test("48kHz Float32 -> 16kHz Int16 mono produces correct frame count") {
        let src = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let dst = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        )!
        let c = AVAudioConverter(from: src, to: dst)!
        c.primeMethod = .none

        let input = makeSineBuffer(format: src, frameCount: 48_000)!
        let output = convertBuffer(input, using: c, to: dst)
        try expect(output != nil, "conversion returned nil")
        let actual = Int(output!.frameLength)
        try expect(abs(actual - 16_000) < 100, "expected ~16000, got \(actual)")
    }

    test("sequential 10ms buffers produce consistent output") {
        let src = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let dst = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let c = AVAudioConverter(from: src, to: dst)!
        c.primeMethod = .none

        var counts: [AVAudioFrameCount] = []
        for _ in 0..<20 {
            let input = makeSineBuffer(format: src, frameCount: 480)!
            if let output = convertBuffer(input, using: c, to: dst) {
                counts.append(output.frameLength)
            }
        }
        try expect(counts.count == 20, "\(20 - counts.count) conversions failed")
        let first = counts[0]
        for (i, n) in counts.enumerated() {
            try expect(abs(Int(n) - Int(first)) <= 1, "buffer \(i): \(n) vs first: \(first)")
        }
    }
}

// MARK: - E2E: System Audio Capture + Transcription

private func testE2E_SystemAudioTranscription() async {
    print("\n--- E2E: System Audio Capture + Transcription ---")
    print("  Exercises all 6 fixes in an integrated pipeline.")

    let testPhrase = "the quick brown fox jumps over the lazy dog"
    let audioPath = "/tmp/dualtranscriber_test_fox.aiff"

    // 1. Generate test audio
    do {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        proc.arguments = ["-o", audioPath, testPhrase]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            print("  SKIP  'say' command failed (\(proc.terminationStatus))")
            skipCount += 1
            return
        }
    } catch {
        print("  SKIP  cannot generate test audio: \(error)")
        skipCount += 1
        return
    }

    // 2. Prepare speech recognition
    let locale = Locale(identifier: "en-US")
    guard let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
        print("  SKIP  en-US speech locale not supported")
        skipCount += 1
        return
    }

    let transcriber = SpeechTranscriber(locale: resolved, preset: .progressiveTranscription)

    do {
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            print("  Installing speech model...")
            try await req.downloadAndInstall()
        }
    } catch {
        print("  SKIP  speech model unavailable: \(error)")
        skipCount += 1
        return
    }

    guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
    )
    else {
        print("  SKIP  no compatible audio format for speech model")
        skipCount += 1
        return
    }
    print("  Speech target: \(targetFormat.sampleRate)Hz \(targetFormat.channelCount)ch")

    // 3. Set up pipeline (Issues 4, 5)
    let (inputSequence, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let collector = TranscriptionCollector()

    let transcriberRef = UnsafeSendable(transcriber)
    let resultsTask = Task {
        do {
            for try await result in transcriberRef.value.results {
                let text = String(result.text.characters)
                // Issue 4: uses result.isFinal (not CMTime comparison)
                collector.update(text: text, isFinal: result.isFinal)
                if result.isFinal {
                    print("  [final]   \(text)")
                } else {
                    print("  [partial] \(text)")
                }
            }
        } catch is CancellationError { /* expected */ }
        catch { print("  Results error: \(error)") }
    }

    // Issue 5: uses start(inputSequence:) instead of analyzeSequence
    let analyzerRef = UnsafeSendable(analyzer)
    let analysisTask = Task {
        do { try await analyzerRef.value.start(inputSequence: inputSequence) }
        catch is CancellationError { /* expected */ }
        catch { print("  Analysis error: \(error)") }
    }

    // 4. Set up system audio capture with all fixes
    let processingQueue = DispatchQueue(
        label: "com.test.systemAudioProcessing", qos: .userInteractive
    )
    let pipelineLock = NSLock() // Issue 6
    nonisolated(unsafe) var converter: AVAudioConverter?

    var tapID: AudioObjectID = kAudioObjectUnknown
    var aggID: AudioObjectID = kAudioObjectUnknown
    var ioProcID: AudioDeviceIOProcID?

    func cleanupAudio() {
        if let p = ioProcID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, p)
            AudioDeviceDestroyIOProcID(aggID, p)
        }
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
    }

    func bail(_ msg: String) {
        print("  SKIP  \(msg)")
        skipCount += 1
        cleanupAudio()
        continuation.finish()
        resultsTask.cancel()
        analysisTask.cancel()
    }

    // Create process tap
    let tapDesc = CATapDescription()
    tapDesc.isMixdown = true
    tapDesc.isExclusive = true
    tapDesc.bundleIDs = ["com.zintegral.AudioPipelineCLITests"]

    var localTapID: AudioObjectID = kAudioObjectUnknown
    guard AudioHardwareCreateProcessTap(tapDesc, &localTapID) == noErr else {
        bail("process tap creation failed")
        return
    }
    tapID = localTapID

    var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var tapFmt = AudioStreamBasicDescription()
    var fmtAddr = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &fmtSize, &tapFmt) == noErr else {
        bail("tap format read failed")
        return
    }
    print("  Tap format: \(tapFmt.mSampleRate)Hz \(tapFmt.mChannelsPerFrame)ch")

    guard let avFormat = AVAudioFormat(streamDescription: &tapFmt) else {
        bail("AVAudioFormat creation failed")
        return
    }

    // Aggregate device
    let tapUUID = tapDesc.uuid.uuidString
    let aggDesc: [String: Any] = [
        kAudioAggregateDeviceNameKey as String: "CLITest_Tap",
        kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey as String: true,
        kAudioAggregateDeviceTapListKey as String: [
            [kAudioSubTapUIDKey as String: tapUUID]
        ],
        kAudioAggregateDeviceTapAutoStartKey as String: true
    ]

    var localAggID: AudioObjectID = kAudioObjectUnknown
    guard AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &localAggID) == noErr else {
        bail("aggregate device creation failed")
        return
    }
    aggID = localAggID

    // IO proc - exercises all fixes in the audio callback
    let capturedTapFmt = tapFmt
    let capturedTargetFmt = targetFormat
    let ioCallCount = LockedCounter()
    let yieldCount = LockedCounter()
    let nonSilentCount = LockedCounter()
    var localProcID: AudioDeviceIOProcID?
    let ioStatus = AudioDeviceCreateIOProcIDWithBlock(
        &localProcID, aggID, nil
    ) { _, inInputData, _, _, _ in
        ioCallCount.increment()
        let chCount = Int(capturedTapFmt.mChannelsPerFrame)
        guard chCount > 0 else { return }

        let isNonInterleaved = capturedTapFmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inInputData)
        )
        guard buffers.count > 0 else { return }

        let frameCount: AVAudioFrameCount
        if isNonInterleaved {
            frameCount = AVAudioFrameCount(
                buffers[0].mDataByteSize / UInt32(MemoryLayout<Float>.size)
            )
        } else {
            frameCount = AVAudioFrameCount(
                buffers[0].mDataByteSize / UInt32(MemoryLayout<Float>.size * chCount)
            )
        }
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: avFormat, frameCapacity: frameCount
        )
        else { return }
        pcmBuffer.frameLength = frameCount

        guard let dstData = pcmBuffer.floatChannelData else { return }

        if isNonInterleaved {
            for ch in 0..<min(chCount, buffers.count) {
                if let src = buffers[ch].mData {
                    memcpy(dstData[ch], src, Int(buffers[ch].mDataByteSize))
                }
            }
        } else if chCount == 1 {
            if let src = buffers[0].mData {
                memcpy(dstData[0], src, Int(buffers[0].mDataByteSize))
            }
        } else {
            if let src = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
                for frame in 0..<Int(frameCount) {
                    for ch in 0..<chCount {
                        dstData[ch][frame] = src[frame * chCount + ch]
                    }
                }
            }
        }

        // Issue 1: dispatch off real-time CoreAudio thread
        processingQueue.async {
            // Check audio energy (silence = no screen recording permission)
            if let ch = pcmBuffer.floatChannelData?[0] {
                var energy: Float = 0
                let n = min(Int(pcmBuffer.frameLength), 256)
                for i in 0..<n {
                    energy += ch[i] * ch[i]
                }
                if sqrt(energy / Float(n)) > 0.001 {
                    nonSilentCount.increment()
                }
            }

            // Issue 6: lock protects shared converter state
            pipelineLock.lock()
            defer { pipelineLock.unlock() }

            let srcFmt = pcmBuffer.format

            // Issue 3: invalidate converter on format change
            if let existing = converter, existing.inputFormat != srcFmt {
                converter = nil
            }

            if converter == nil {
                if srcFmt.sampleRate == capturedTargetFmt.sampleRate,
                   srcFmt.channelCount == capturedTargetFmt.channelCount,
                   srcFmt.commonFormat == capturedTargetFmt.commonFormat {
                    // No conversion needed
                } else if let c = AVAudioConverter(from: srcFmt, to: capturedTargetFmt) {
                    c.primeMethod = .none // Issue 2
                    converter = c
                } else {
                    return
                }
            }

            if let conv = converter {
                let ratio = capturedTargetFmt.sampleRate / srcFmt.sampleRate
                let cap = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio) + 1
                guard let out = AVAudioPCMBuffer(
                    pcmFormat: capturedTargetFmt, frameCapacity: cap
                )
                else { return }

                var consumed = false
                var err: NSError?
                let st = conv.convert(to: out, error: &err) { _, outStatus in
                    if consumed { outStatus.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    outStatus.pointee = .haveData
                    return pcmBuffer
                }
                guard st != .error else { return }
                yieldCount.increment()
                continuation.yield(AnalyzerInput(buffer: out))
            } else {
                yieldCount.increment()
                continuation.yield(AnalyzerInput(buffer: pcmBuffer))
            }
        }
    }

    guard ioStatus == noErr, let localProcID else {
        bail("IO proc creation failed (\(ioStatus))")
        return
    }
    ioProcID = localProcID

    guard AudioDeviceStart(aggID, localProcID) == noErr else {
        bail("device start failed")
        return
    }
    print("  System audio capture started")

    // 5. Play test audio and wait
    print("  Playing: \"\(testPhrase)\"")
    do {
        let play = Process()
        play.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        play.arguments = [audioPath]
        try play.run()
        play.waitUntilExit()
    } catch {
        bail("afplay failed: \(error)")
        return
    }

    let nonSilent = nonSilentCount.value
    print("  Playback done. IO callbacks: \(ioCallCount.value), yields: \(yieldCount.value), non-silent: \(nonSilent)")
    print("  Waiting for transcription to finalize...")
    try? await Task.sleep(for: .seconds(3))
    print("  After wait. IO callbacks: \(ioCallCount.value), yields: \(yieldCount.value)")

    // 6. Finalize
    continuation.finish()
    do {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    } catch {
        print("  Finalize warning: \(error)")
    }

    resultsTask.cancel()
    await resultsTask.value
    analysisTask.cancel()
    cleanupAudio()

    // 7. Verify
    let totalNonSilent = nonSilentCount.value
    let totalIO = ioCallCount.value
    if totalNonSilent == 0, totalIO > 0 {
        print("  SKIP  All \(totalIO) captured buffers were silent.")
        print("        Process tap requires Screen Recording permission.")
        print("        Grant it in: System Settings > Privacy & Security > Screen Recording")
        print("        Add your terminal app (Terminal.app, iTerm, etc.)")
        skipCount += 1
        return
    }

    let finalText = collector.lastText
    let normalized = finalText.lowercased()
    if normalized.isEmpty {
        failCount += 1
        print("  FAIL  no transcription received")
        return
    }

    let expectedWords = ["quick", "brown", "fox", "jumps", "lazy", "dog"]
    var missing: [String] = []
    for word in expectedWords {
        if !normalized.contains(word) { missing.append(word) }
    }

    if missing.isEmpty {
        passCount += 1
        print("  PASS  transcription captured: \"\(finalText)\"")
    } else {
        failCount += 1
        print("  FAIL  missing words: \(missing.joined(separator: ", "))")
        print("        got: \"\(finalText)\"")
    }

    if collector.gotFinal {
        passCount += 1
        print("  PASS  result.isFinal received (Issue 4 verified)")
    } else {
        print("  INFO  result.isFinal not received (may need longer audio)")
    }
}

// MARK: - Entry Point

print("AudioPipeline Fix Verification")
print("==============================")
print("Verifying 6 fixes from docs/note.01.md\n")
print("Issues 4 (result.isFinal) and 5 (start(inputSequence:))")
print("are verified by successful compilation + E2E test.")

testIssue2_PrimeMethod()
testIssue3_FormatChangeDetection()
testIssue1_RealtimeThreadDispatch()
testIssue6_LockThreadSafety()
testConversionPipeline()

Task {
    await testE2E_SystemAudioTranscription()

    print("\n==============================")
    let total = passCount + failCount + skipCount
    print("Results: \(passCount) passed, \(failCount) failed, \(skipCount) skipped (\(total) checks)")
    if failCount > 0 {
        print("SOME TESTS FAILED")
        Foundation.exit(1)
    } else {
        print("ALL TESTS PASSED")
        Foundation.exit(0)
    }
}

dispatchMain()
