@testable import DualSTT
import Foundation
import Testing

struct AudioCaptureErrorTests {
    @Test
    func `noMicrophoneAvailable has descriptive message`() {
        let error = AudioCaptureError.noMicrophoneAvailable
        let description = error.errorDescription ?? ""

        #expect(!description.isEmpty)
        #expect(description.contains("microphone"))
    }

    @Test
    func `tapCreationFailed with 'nope' (0x6E6F7065) mentions System Settings`() {
        let error = AudioCaptureError.tapCreationFailed(0x6E6F7065)
        let description = error.errorDescription ?? ""

        #expect(description.contains("System Settings"))
    }

    @Test
    func `tapCreationFailed with other status shows OSStatus`() {
        let status: OSStatus = -50
        let error = AudioCaptureError.tapCreationFailed(status)
        let description = error.errorDescription ?? ""

        #expect(description.contains("\(status)"))
    }

    @Test
    func `formatReadFailed shows OSStatus`() {
        let status: OSStatus = -10868
        let error = AudioCaptureError.formatReadFailed(status)
        let description = error.errorDescription ?? ""

        #expect(!description.isEmpty)
        #expect(description.contains("\(status)"))
    }

    @Test
    func `aggregateDeviceFailed has description`() {
        let error = AudioCaptureError.aggregateDeviceFailed(-50)
        let description = error.errorDescription ?? ""

        #expect(!description.isEmpty)
    }

    @Test
    func `ioProcFailed has description`() {
        let error = AudioCaptureError.ioProcFailed(-50)
        let description = error.errorDescription ?? ""

        #expect(!description.isEmpty)
    }

    @Test
    func `deviceStartFailed has description`() {
        let error = AudioCaptureError.deviceStartFailed(-50)
        let description = error.errorDescription ?? ""

        #expect(!description.isEmpty)
    }

    @Test
    func `all errors conform to LocalizedError with non-empty descriptions`() throws {
        let errors: [AudioCaptureError] = [
            .noMicrophoneAvailable,
            .microphonePermissionDenied,
            .tapCreationFailed(0x6E6F7065),
            .tapCreationFailed(-50),
            .formatReadFailed(-10868),
            .aggregateDeviceFailed(-50),
            .ioProcFailed(-50),
            .deviceStartFailed(-50)
        ]

        for error in errors {
            let description = error.errorDescription
            #expect(description != nil)
            #expect(try !(#require(description?.isEmpty)))
        }
    }
}
