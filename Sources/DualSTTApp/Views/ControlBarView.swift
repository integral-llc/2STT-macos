import SwiftUI
import UniformTypeIdentifiers
import AppKit
import DualSTT

struct ControlBarView: View {
    @Bindable var engine: TranscriptionEngine

    var body: some View {
        HStack(spacing: 16) {
            recordButton
            clearButton
            Spacer()
            copyAllButton
            exportMenu
            Text("\(engine.store.entries.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .buttonStyle(.bordered)
    }

    private var recordButton: some View {
        Group {
            if engine.isRecording {
                Button(action: { Task { await engine.stopRecording() } }) {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .tint(.red)
                .keyboardShortcut(.return, modifiers: .command)
            } else {
                Button(action: { Task { await engine.startRecording() } }) {
                    Label("Record", systemImage: "record.circle")
                }
                .tint(.red)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var clearButton: some View {
        Button(action: { engine.clearTranscript() }) {
            Label("Clear", systemImage: "trash")
        }
        .disabled(engine.isRecording || engine.store.entries.isEmpty)
    }

    private var copyAllButton: some View {
        Button(action: copyToClipboard) {
            Label("Copy All", systemImage: "doc.on.doc")
        }
        .disabled(engine.store.entries.isEmpty)
    }

    private var exportMenu: some View {
        Menu {
            Button("Export as Text") { exportText() }
            Button("Export as SRT") { exportSRT() }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(engine.store.entries.isEmpty)
    }

    private func copyToClipboard() {
        let text = engine.copyAll()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportText() {
        let text = engine.exportPlainText()
        saveFile(content: text, type: .plainText, extension: "txt")
    }

    private func exportSRT() {
        let text = engine.exportSRT()
        saveFile(content: text, type: .init("org.matroska.srt")!, extension: "srt")
    }

    private func saveFile(content: String, type: UTType, extension ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "transcript_\(Date().ISO8601Format()).\(ext)"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
