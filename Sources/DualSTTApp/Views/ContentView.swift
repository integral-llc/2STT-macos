import SwiftUI
import DualSTT

struct ContentView: View {
    @State private var engine = TranscriptionEngine()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if engine.isRecording {
                deviceInfoBar
            }
            Divider()
            TranscriptListView(entries: engine.store.entries)
            Divider()
            ControlBarView(engine: engine)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            engine.permissions.checkAll()
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") { engine.error = nil }
        } message: {
            Text(engine.error ?? "")
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Dual Audio Transcriber")
                .font(.headline)
            Spacer()
            PermissionStatusView(permissions: engine.permissions)
            if engine.isRecording {
                RecordingIndicator()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var deviceInfoBar: some View {
        HStack(spacing: 16) {
            Label(engine.micDeviceName, systemImage: "mic")
            Label(engine.systemAudioInfo, systemImage: "speaker.wave.2")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { engine.error != nil },
            set: { if !$0 { engine.error = nil } }
        )
    }
}
