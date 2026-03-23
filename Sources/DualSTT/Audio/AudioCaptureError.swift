import Foundation

public enum AudioCaptureError: Error, LocalizedError {
    case noMicrophoneAvailable
    case microphonePermissionDenied
    case tapCreationFailed(OSStatus)
    case formatReadFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .noMicrophoneAvailable:
            return "No microphone detected. Connect a microphone and try again."
        case .microphonePermissionDenied:
            return "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .tapCreationFailed(let status):
            if status == 0x6E6F7065 { // 'nope'
                return "System audio capture denied. Enable it in System Settings > Privacy & Security > Screen & System Audio Recording."
            }
            return "System audio tap creation failed (OSStatus \(status))."
        case .formatReadFailed(let status):
            return "Could not read tap audio format (OSStatus \(status))."
        case .aggregateDeviceFailed(let status):
            return "Aggregate audio device creation failed (OSStatus \(status))."
        case .ioProcFailed(let status):
            return "Audio IO proc setup failed (OSStatus \(status))."
        case .deviceStartFailed(let status):
            return "Audio device failed to start (OSStatus \(status))."
        }
    }
}
