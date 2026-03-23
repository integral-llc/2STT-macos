import Foundation

enum PlainTextExporter {

    static func export(_ entries: [TranscriptEntry]) -> String {
        entries.map { entry in
            let time = formatTime(entry.timestamp)
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
