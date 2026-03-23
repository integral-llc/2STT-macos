@testable import DualSTT
import Foundation
import Testing

struct PermissionStateTests {
    @Test
    @MainActor
    func `initial state is all unknown`() {
        let state = PermissionState()

        #expect(state.microphone == .unknown)
        #expect(state.systemAudio == .unknown)
        #expect(state.speechRecognition == .unknown)
        #expect(state.speechModel == .unknown)
    }

    @Test
    @MainActor
    func `allReady is false when any required permission is not granted`() {
        let state = PermissionState()

        #expect(state.allReady == false)

        state.microphone = .granted
        #expect(state.allReady == false)

        state.speechRecognition = .granted
        #expect(state.allReady == false)

        state.speechModel = .granted
        #expect(state.allReady == true)
    }

    @Test
    @MainActor
    func `markSystemAudio updates systemAudio status`() {
        let state = PermissionState()

        #expect(state.systemAudio == .unknown)

        state.markSystemAudio(.granted)
        #expect(state.systemAudio == .granted)

        state.markSystemAudio(.denied)
        #expect(state.systemAudio == .denied)
    }

    @Test
    @MainActor
    func `allReady excludes systemAudio from requirements`() {
        let state = PermissionState()
        state.microphone = .granted
        state.speechRecognition = .granted
        state.speechModel = .granted
        state.systemAudio = .denied

        #expect(state.allReady == true)
    }

    @Test
    func `PermissionStatus enum has all 4 expected cases`() {
        let statuses: [PermissionStatus] = [.unknown, .granted, .denied, .unavailable]
        #expect(statuses.count == 4)

        for status in statuses {
            switch status {
            case .unknown, .granted, .denied, .unavailable:
                break
            }
        }
    }
}
