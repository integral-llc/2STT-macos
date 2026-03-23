import Testing
import Foundation
@testable import DualAudioTranscriber

@Suite("SRTExporter")
struct SRTExporterTests {

    private func makeEntry(
        source: AudioSource,
        text: String,
        hour: Int,
        minute: Int,
        second: Int,
        millisecond: Int = 0
    ) -> TranscriptEntry {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let date = calendar.date(
            from: DateComponents(
                hour: hour,
                minute: minute,
                second: second,
                nanosecond: millisecond * 1_000_000
            )
        )!
        return TranscriptEntry(source: source, timestamp: date, text: text, isFinal: true)
    }

    @Test("exports single entry with 3-second fallback duration")
    func singleEntry() {
        let entries = [makeEntry(source: .me, text: "hello", hour: 10, minute: 0, second: 0)]
        let result = SRTExporter.export(entries)

        let expected = """
        1
        10:00:00,000 --> 10:00:03,000
        [ME] hello
        """
        #expect(result == expected)
    }

    @Test("exports multiple entries with sequential numbering")
    func multipleEntries() {
        let entries = [
            makeEntry(source: .me, text: "hello", hour: 10, minute: 0, second: 0),
            makeEntry(source: .them, text: "hi", hour: 10, minute: 0, second: 5),
            makeEntry(source: .me, text: "bye", hour: 10, minute: 0, second: 10),
        ]
        let result = SRTExporter.export(entries)
        let blocks = result.components(separatedBy: "\n\n")

        #expect(blocks.count == 3)
        #expect(blocks[0].hasPrefix("1\n"))
        #expect(blocks[1].hasPrefix("2\n"))
        #expect(blocks[2].hasPrefix("3\n"))
    }

    @Test("end time of entry equals start time of next entry")
    func endTimeMatchesNextStart() {
        let entries = [
            makeEntry(source: .me, text: "first", hour: 10, minute: 0, second: 0),
            makeEntry(source: .them, text: "second", hour: 10, minute: 0, second: 5),
        ]
        let result = SRTExporter.export(entries)
        let blocks = result.components(separatedBy: "\n\n")

        let firstTimeline = blocks[0].split(separator: "\n")[1]
        #expect(firstTimeline == "10:00:00,000 --> 10:00:05,000")

        let secondTimeline = blocks[1].split(separator: "\n")[1]
        #expect(secondTimeline == "10:00:05,000 --> 10:00:08,000")
    }

    @Test("embeds speaker tag in text")
    func speakerTagInText() {
        let entries = [
            makeEntry(source: .them, text: "spoken words", hour: 10, minute: 0, second: 0),
        ]
        let result = SRTExporter.export(entries)

        #expect(result.contains("[THEM] spoken words"))
    }

    @Test("exports empty list as empty string")
    func emptyList() {
        let result = SRTExporter.export([])
        #expect(result == "")
    }

    @Test("preserves millisecond precision")
    func millisecondPrecision() {
        let entries = [
            makeEntry(source: .me, text: "precise", hour: 10, minute: 0, second: 0, millisecond: 500),
        ]
        let result = SRTExporter.export(entries)

        #expect(result.contains("10:00:00,500"))
    }
}
