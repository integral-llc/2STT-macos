import Foundation

public struct TranscriptEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: AudioSource
    public let timestamp: Date
    public let text: String
    public let isFinal: Bool

    public init(
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

    public func with(text: String? = nil, isFinal: Bool? = nil) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            source: source,
            timestamp: timestamp,
            text: text ?? self.text,
            isFinal: isFinal ?? self.isFinal
        )
    }
}
