import Foundation

struct TranscriptEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let source: AudioSource
    let timestamp: Date
    let text: String
    let isFinal: Bool

    init(
        id: UUID = UUID(),
        source: AudioSource,
        timestamp: Date = Date(),
        text: String,
        isFinal: Bool = false
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.text = text
        self.isFinal = isFinal
    }

    func with(text: String? = nil, isFinal: Bool? = nil) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            source: source,
            timestamp: timestamp,
            text: text ?? self.text,
            isFinal: isFinal ?? self.isFinal
        )
    }
}
