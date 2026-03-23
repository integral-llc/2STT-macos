import AVFoundation
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualSTT", category: "MicCapture")

@Observable
public final class MicCaptureManager: AudioCapturing, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var isRunning = false

    public var onAudioBuffer: (@Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void)?

    public init() {}

    public func start() throws {
        guard !isRunning else { return }

        let inputNode = audioEngine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        log.info("Mic hardware format: sampleRate=\(hwFormat.sampleRate) channels=\(hwFormat.channelCount) bitsPerChannel=\(hwFormat.streamDescription.pointee.mBitsPerChannel)")

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            log.error("No microphone available (sampleRate=\(hwFormat.sampleRate) channels=\(hwFormat.channelCount))")
            throw AudioCaptureError.noMicrophoneAvailable
        }

        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) {
            [weak self] buffer, time in
            self?.onAudioBuffer?(buffer, time)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        log.info("Mic capture started - bufferSize=\(bufferSize)")
    }

    public func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        log.info("Mic capture stopped")
    }
}
