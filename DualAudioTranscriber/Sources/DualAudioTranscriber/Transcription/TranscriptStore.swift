import Foundation

@Observable
@MainActor
final class TranscriptStore {
    private(set) var entries: [TranscriptEntry] = []
    private var currentVolatileID: [AudioSource: UUID] = [:]

    func handleResult(source: AudioSource, text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingID = currentVolatileID[source],
           let index = entries.firstIndex(where: { $0.id == existingID }) {
            let updated = entries[index].with(
                text: trimmed,
                isFinal: isFinal ? true : nil
            )
            entries[index] = updated
            if isFinal {
                currentVolatileID[source] = nil
            }
        } else {
            let entry = TranscriptEntry(source: source, text: trimmed, isFinal: isFinal)
            entries.append(entry)
            if !isFinal {
                currentVolatileID[source] = entry.id
            }
        }
    }

    func clear() {
        entries = []
        currentVolatileID = [:]
    }

    func allText(includingVolatile: Bool = true) -> String {
        let source = includingVolatile ? entries : entries.filter(\.isFinal)
        return source.map { entry in
            let time = Self.formatTime(entry.timestamp)
            return "[\(time)] [\(entry.source.rawValue)] \(entry.text)"
        }.joined(separator: "\n")
    }

    private static func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
