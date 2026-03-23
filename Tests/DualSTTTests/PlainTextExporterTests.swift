import Testing
import Foundation
@testable import DualSTT

@Suite("PlainTextExporter")
struct PlainTextExporterTests {

    private func makeEntry(
        source: AudioSource,
        text: String,
        hour: Int,
        minute: Int,
        second: Int
    ) -> TranscriptEntry {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.date(
            from: DateComponents(hour: hour, minute: minute, second: second)
        )!
        return TranscriptEntry(source: source, timestamp: date, text: text, isFinal: true)
    }

    @Test("exports single entry")
    func singleEntry() {
        let entries = [makeEntry(source: .me, text: "hello", hour: 14, minute: 5, second: 30)]
        let result = PlainTextExporter.export(entries)

        #expect(result == "[14:05:30] [ME] hello")
    }

    @Test("exports multiple entries")
    func multipleEntries() {
        let entries = [
            makeEntry(source: .me, text: "hello", hour: 14, minute: 5, second: 30),
            makeEntry(source: .them, text: "hi there", hour: 14, minute: 5, second: 32),
            makeEntry(source: .me, text: "how are you", hour: 14, minute: 5, second: 35),
        ]
        let result = PlainTextExporter.export(entries)
        let lines = result.split(separator: "\n")

        #expect(lines.count == 3)
        #expect(lines[0] == "[14:05:30] [ME] hello")
        #expect(lines[1] == "[14:05:32] [THEM] hi there")
        #expect(lines[2] == "[14:05:35] [ME] how are you")
    }

    @Test("exports empty list")
    func emptyList() {
        let result = PlainTextExporter.export([])
        #expect(result == "")
    }
}
