import Foundation
import AVFoundation
import Speech
import os.log

private let log = Logger(subsystem: "com.eugenerat.DualAudioTranscriber", category: "Permissions")

enum PermissionStatus: Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

@Observable
@MainActor
final class PermissionState {
    var microphone: PermissionStatus = .unknown
    var systemAudio: PermissionStatus = .unknown
    var speechRecognition: PermissionStatus = .unknown
    var speechModel: PermissionStatus = .unknown

    var allReady: Bool {
        microphone == .granted
            && speechRecognition == .granted
            && speechModel == .granted
        // systemAudio excluded - no pre-check API
    }

    func checkAll() {
        checkMicrophone()
        checkSpeechRecognition()
        checkSpeechModel()
        log.fault("Permission check: mic=\(String(describing: self.microphone)) speech=\(String(describing: self.speechRecognition)) model=\(String(describing: self.speechModel)) sysAudio=\(String(describing: self.systemAudio))")
    }

    func checkMicrophone() {
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

    func requestMicrophone() async {
        log.fault("Requesting microphone permission...")
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = granted ? .granted : .denied
        log.fault("Microphone request result: \(granted)")
    }

    func checkSpeechRecognition() {
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

    func requestSpeechRecognition() {
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

    func checkSpeechModel() {
        log.fault("Checking speech model via SFSpeechRecognizer...")
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let available = recognizer?.isAvailable ?? false
        let onDevice = recognizer?.supportsOnDeviceRecognition ?? false
        speechModel = available ? .granted : .unavailable
        log.fault("Speech model: available=\(available) onDevice=\(onDevice)")
    }

    func markSystemAudio(_ status: PermissionStatus) {
        systemAudio = status
    }
}
