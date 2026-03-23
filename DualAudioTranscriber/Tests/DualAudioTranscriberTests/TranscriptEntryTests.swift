import Testing
import Foundation
@testable import DualAudioTranscriber

@Suite("TranscriptEntry")
struct TranscriptEntryTests {

    @Test("initializes with default values")
    func defaultInit() {
        let entry = TranscriptEntry(source: .me, text: "hello")

        #expect(entry.source == .me)
        #expect(entry.text == "hello")
        #expect(entry.isFinal == false)
        #expect(entry.timestamp <= Date())
    }

    @Test("initializes with explicit values")
    func explicitInit() {
        let id = UUID()
        let date = Date.distantPast
        let entry = TranscriptEntry(
            id: id,
            source: .them,
            timestamp: date,
            text: "world",
            isFinal: true
        )

        #expect(entry.id == id)
        #expect(entry.source == .them)
        #expect(entry.timestamp == date)
        #expect(entry.text == "world")
        #expect(entry.isFinal == true)
    }

    @Test("with() creates a new instance preserving identity")
    func withPreservesIdentity() {
        let original = TranscriptEntry(source: .me, text: "draft")
        let updated = original.with(text: "final version")

        #expect(updated.id == original.id)
        #expect(updated.source == original.source)
        #expect(updated.timestamp == original.timestamp)
        #expect(updated.text == "final version")
        #expect(updated.isFinal == false)
    }

    @Test("with() updates isFinal without changing text")
    func withFinalizesEntry() {
        let original = TranscriptEntry(source: .them, text: "some text")
        let finalized = original.with(isFinal: true)

        #expect(finalized.id == original.id)
        #expect(finalized.text == "some text")
        #expect(finalized.isFinal == true)
    }

    @Test("with() updates both text and isFinal")
    func withUpdatesBoth() {
        let original = TranscriptEntry(source: .me, text: "partial")
        let updated = original.with(text: "complete sentence", isFinal: true)

        #expect(updated.id == original.id)
        #expect(updated.text == "complete sentence")
        #expect(updated.isFinal == true)
    }

    @Test("with() does not mutate original")
    func withDoesNotMutateOriginal() {
        let original = TranscriptEntry(source: .me, text: "original")
        let _ = original.with(text: "changed", isFinal: true)

        #expect(original.text == "original")
        #expect(original.isFinal == false)
    }

    @Test("conforms to Identifiable")
    func identifiable() {
        let entry = TranscriptEntry(source: .me, text: "test")
        let _: any Identifiable = entry
        #expect(entry.id == entry.id)
    }

    @Test("conforms to Equatable")
    func equatable() {
        let id = UUID()
        let date = Date()
        let a = TranscriptEntry(id: id, source: .me, timestamp: date, text: "same", isFinal: false)
        let b = TranscriptEntry(id: id, source: .me, timestamp: date, text: "same", isFinal: false)
        let c = TranscriptEntry(id: UUID(), source: .me, timestamp: date, text: "same", isFinal: false)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("AudioSource raw values")
    func audioSourceRawValues() {
        #expect(AudioSource.me.rawValue == "ME")
        #expect(AudioSource.them.rawValue == "THEM")
    }
}
