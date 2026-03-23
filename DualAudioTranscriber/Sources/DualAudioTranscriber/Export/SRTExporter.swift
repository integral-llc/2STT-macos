import Foundation

enum SRTExporter {

    static func export(_ entries: [TranscriptEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        let blocks: [String] = entries.enumerated().map { index, entry in
            let sequenceNumber = index + 1
            let startTime = srtTimecode(entry.timestamp)
            let endTime: String
            if index + 1 < entries.count {
                endTime = srtTimecode(entries[index + 1].timestamp)
            } else {
                let fallbackEnd = entry.timestamp.addingTimeInterval(3)
                endTime = srtTimecode(fallbackEnd)
            }
            let text = "[\(entry.source.rawValue)] \(entry.text)"
            return "\(sequenceNumber)\n\(startTime) --> \(endTime)\n\(text)"
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func srtTimecode(_ date: Date) -> String {
        let calendar = Calendar.current
        let h = calendar.component(.hour, from: date)
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let ms = calendar.component(.nanosecond, from: date) / 1_000_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
