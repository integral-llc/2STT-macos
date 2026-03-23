import Foundation

enum TranscriptionError: Error, LocalizedError {
    case appleIntelligenceRequired
    case localeNotSupported(Locale)
    case modelNotInstalled(Locale)
    case modelDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceRequired:
            return "Apple Intelligence is required for speech recognition on macOS 26.\n\n"
                + "1. Open System Settings > Apple Intelligence & Siri\n"
                + "2. Turn on Apple Intelligence\n"
                + "3. Wait for assets to finish downloading\n"
                + "4. Restart this app"
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
