import SwiftUI
import DualSTT

struct RecordingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(isAnimating ? 0.3 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            Text("Recording")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { isAnimating = true }
    }
}
