@testable import DualSTT
import Foundation
import Testing

struct TranscriptionErrorTests {
    @Test
    func `appleIntelligenceRequired mentions Apple Intelligence and System Settings`() {
        let error = TranscriptionError.appleIntelligenceRequired
        let description = error.errorDescription ?? ""

        #expect(description.contains("Apple Intelligence"))
        #expect(description.contains("System Settings"))
    }

    @Test
    func `localeNotSupported includes locale identifier`() {
        let locale = Locale(identifier: "ja-JP")
        let error = TranscriptionError.localeNotSupported(locale)
        let description = error.errorDescription ?? ""

        #expect(description.contains("ja-JP"))
    }

    @Test
    func `modelNotInstalled includes locale and Apple Intelligence instructions`() {
        let locale = Locale(identifier: "fr-FR")
        let error = TranscriptionError.modelNotInstalled(locale)
        let description = error.errorDescription ?? ""

        #expect(description.contains("fr-FR"))
        #expect(description.contains("Apple Intelligence"))
        #expect(description.contains("System Settings"))
    }

    @Test
    func `modelDownloadFailed includes reason string`() {
        let reason = "network timeout"
        let error = TranscriptionError.modelDownloadFailed(reason)
        let description = error.errorDescription ?? ""

        #expect(description.contains(reason))
    }
}
