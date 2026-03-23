import Foundation
import AVFoundation
import Speech
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualSTT", category: "Permissions")

public enum PermissionStatus: Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

@Observable
@MainActor
public final class PermissionState {
    public var microphone: PermissionStatus = .unknown
    public var systemAudio: PermissionStatus = .unknown
    public var speechRecognition: PermissionStatus = .unknown
    public var speechModel: PermissionStatus = .unknown

    public var allReady: Bool {
        microphone == .granted
            && speechRecognition == .granted
            && speechModel == .granted
        // systemAudio excluded - no pre-check API
    }

    public init() {}

    public func checkAll() {
        checkMicrophone()
        checkSpeechRecognition()
        checkSpeechModel()
        log.fault("Permission check: mic=\(String(describing: self.microphone)) speech=\(String(describing: self.speechRecognition)) model=\(String(describing: self.speechModel)) sysAudio=\(String(describing: self.systemAudio))")
    }

    public func checkMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphone = .granted
        case .denied, .restricted:
            microphone = .denied
        case .notDetermined:
            microphone = .unknown
        @unknown default:
            microphone = .unknown
        }
        log.fault("Microphone: AVAuth=\(status.rawValue) -> \(String(describing: self.microphone))")
    }

    public func requestMicrophone() async {
        log.fault("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
        log.fault("Microphone request result: \(granted)")
    }

    public func checkSpeechRecognition() {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            speechRecognition = .granted
        case .denied, .restricted:
            speechRecognition = .denied
        case .notDetermined:
            speechRecognition = .unknown
        @unknown default:
            speechRecognition = .unknown
        }
        log.fault("SpeechRecog: SFAuth=\(status.rawValue) -> \(String(describing: self.speechRecognition))")
    }

    public func requestSpeechRecognition() {
        log.fault("Requesting speech recognition permission...")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    self?.speechRecognition = .granted
                case .denied, .restricted:
                    self?.speechRecognition = .denied
                default:
                    self?.speechRecognition = .unknown
                }
                log.fault("SpeechRecog request result: \(status.rawValue)")
            }
        }
    }

    public func checkSpeechModel() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let available = recognizer?.isAvailable ?? false
        speechModel = available ? .granted : .unavailable
        log.fault("Speech model: available=\(available)")
    }

    public func markSystemAudio(_ status: PermissionStatus) {
        systemAudio = status
    }
}
