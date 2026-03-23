import Foundation
import AVFoundation
import CoreAudio
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualSTT", category: "TranscriptionEngine")

@Observable
@MainActor
public final class TranscriptionEngine {
    public let store = TranscriptStore()
    public let permissions = PermissionState()
    public var isRecording = false
    public var error: String?
    public var micDeviceName: String = "None"
    public var systemAudioInfo: String = "None"

    private let micCapture = MicCaptureManager()
    private let systemCapture = SystemAudioCaptureManager()
    private var micPipeline: SpeechPipeline?
    private var systemPipeline: SpeechPipeline?

    public init() {}

    public func startRecording() async {
        log.fault("startRecording() called")
        guard !isRecording else { return }
        store.clear()
        error = nil

        if permissions.microphone == .unknown {
            await permissions.requestMicrophone()
        }
        if permissions.speechRecognition == .unknown {
            permissions.requestSpeechRecognition()
            try? await Task.sleep(for: .milliseconds(500))
            permissions.checkSpeechRecognition()
        }

        do {
            let micPipeline = SpeechPipeline(source: .me)
            let systemPipeline = SpeechPipeline(source: .them)

            micPipeline.onTranscript = { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.store.handleResult(source: .me, text: text, isFinal: isFinal)
                }
            }
            micPipeline.onError = { [weak self] msg in
                Task { @MainActor in self?.error = msg }
            }
            systemPipeline.onTranscript = { [weak self] text, isFinal in
                Task { @MainActor in
                    self?.store.handleResult(source: .them, text: text, isFinal: isFinal)
                }
            }
            systemPipeline.onError = { [weak self] msg in
                Task { @MainActor in self?.error = msg }
            }

            log.fault("Preparing pipelines...")
            try await micPipeline.prepare()
            try await systemPipeline.prepare()

            self.micPipeline = micPipeline
            self.systemPipeline = systemPipeline

            // Wire audio AFTER pipelines are ready
            micCapture.onAudioBuffer = { [weak micPipeline] buffer, _ in
                micPipeline?.appendAudio(buffer)
            }
            systemCapture.onAudioBuffer = { [weak systemPipeline] buffer, _ in
                systemPipeline?.appendAudio(buffer)
            }

            // Start captures AFTER everything is wired
            log.fault("Starting captures...")
            try micCapture.start()
            permissions.checkMicrophone()
            micDeviceName = Self.currentInputDeviceName()

            try systemCapture.start()
            permissions.markSystemAudio(.granted)
            systemAudioInfo = Self.currentOutputDeviceName()

            isRecording = true
            log.fault("Recording STARTED - mic=\(self.micDeviceName)")
        } catch {
            log.fault("startRecording() FAILED: \(error)")
            micCapture.stop()
            systemCapture.stop()
            await micPipeline?.finalize()
            await systemPipeline?.finalize()
            self.micPipeline = nil
            self.systemPipeline = nil

            self.error = error.localizedDescription
            permissions.checkMicrophone()
            permissions.checkSpeechRecognition()
            permissions.checkSpeechModel()
        }
    }

    public func stopRecording() async {
        log.fault("stopRecording() called")
        guard isRecording else { return }

        micCapture.stop()
        systemCapture.stop()
        await micPipeline?.finalize()
        await systemPipeline?.finalize()

        micPipeline = nil
        systemPipeline = nil
        isRecording = false
        log.fault("Recording stopped")
    }

    public func clearTranscript() {
        store.clear()
    }

    public func exportPlainText() -> String {
        PlainTextExporter.export(store.entries)
    }

    public func exportSRT() -> String {
        SRTExporter.export(store.entries)
    }

    public func copyAll() -> String {
        store.allText(includingVolatile: true)
    }

    private static func currentInputDeviceName() -> String {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceName(for: deviceID)
    }

    public static func currentOutputDeviceName() -> String {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceName(for: deviceID)
    }

    private static func deviceName(for deviceID: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        var unmanagedName: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanagedName)
        guard status == noErr, let cf = unmanagedName else { return "Unknown" }
        return cf.takeUnretainedValue() as String
    }
}
