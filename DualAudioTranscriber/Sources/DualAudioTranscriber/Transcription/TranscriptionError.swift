import Foundation

enum TranscriptionError: Error, LocalizedError {
    case localeNotSupported(Locale)
    case modelNotInstalled(Locale)
    case modelDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .localeNotSupported(let locale):
            return "Speech recognition locale '\(locale.identifier)' is not supported on this device."
        case .modelNotInstalled(let locale):
            return "The speech model for '\(locale.identifier)' is not installed. "
                + "Enable Apple Intelligence in System Settings > Apple Intelligence & Siri, "
                + "then download the speech model."
        case .modelDownloadFailed(let reason):
            return "Speech model download failed: \(reason)"
        }
    }
}
