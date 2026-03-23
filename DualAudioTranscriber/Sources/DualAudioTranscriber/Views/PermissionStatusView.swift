import SwiftUI

struct PermissionStatusView: View {
    let permissions: PermissionState

    var body: some View {
        HStack(spacing: 12) {
            indicator(label: "Mic", status: permissions.microphone)
            indicator(label: "System Audio", status: permissions.systemAudio)
            indicator(label: "Speech", status: permissions.speechRecognition)
            indicator(label: "Model", status: permissions.speechModel)
        }
        .font(.caption2)
    }

    private func indicator(label: String, status: PermissionStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: status))
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .help(tooltip(label: label, status: status))
    }

    private func color(for status: PermissionStatus) -> Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .unavailable: return .red
        case .unknown: return .orange
        }
    }

    private func tooltip(label: String, status: PermissionStatus) -> String {
        switch status {
        case .granted: return "\(label): Ready"
        case .denied: return "\(label): Denied - check System Settings > Privacy & Security"
        case .unavailable: return "\(label): Not available - enable Apple Intelligence in System Settings"
        case .unknown: return "\(label): Not yet checked"
        }
    }
}
