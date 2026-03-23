import Testing
import Foundation
@testable import DualAudioTranscriber

@Suite("TranscriptStore")
struct TranscriptStoreTests {

    @Test("appends new finalized entry")
    @MainActor
    func appendsFinalEntry() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "hello world", isFinal: true)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].source == .me)
        #expect(store.entries[0].text == "hello world")
        #expect(store.entries[0].isFinal == true)
    }

    @Test("appends new volatile entry")
    @MainActor
    func appendsVolatileEntry() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "hel", isFinal: false)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].isFinal == false)
    }

    @Test("updates volatile entry in-place with new text")
    @MainActor
    func updatesVolatileInPlace() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "hel", isFinal: false)
        let originalID = store.entries[0].id

        store.handleResult(source: .me, text: "hello wor", isFinal: false)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].id == originalID)
        #expect(store.entries[0].text == "hello wor")
        #expect(store.entries[0].isFinal == false)
    }

    @Test("finalizes volatile entry")
    @MainActor
    func finalizesVolatileEntry() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "hell", isFinal: false)
        let originalID = store.entries[0].id

        store.handleResult(source: .me, text: "hello world", isFinal: true)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].id == originalID)
        #expect(store.entries[0].text == "hello world")
        #expect(store.entries[0].isFinal == true)
    }

    @Test("creates new entry after previous volatile is finalized")
    @MainActor
    func newEntryAfterFinalized() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "first", isFinal: true)
        store.handleResult(source: .me, text: "second", isFinal: false)

        #expect(store.entries.count == 2)
        #expect(store.entries[0].text == "first")
        #expect(store.entries[1].text == "second")
    }

    @Test("tracks volatile entries per source independently")
    @MainActor
    func independentVolatilePerSource() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "me partial", isFinal: false)
        store.handleResult(source: .them, text: "them partial", isFinal: false)

        #expect(store.entries.count == 2)

        store.handleResult(source: .me, text: "me updated", isFinal: false)
        store.handleResult(source: .them, text: "them updated", isFinal: false)

        #expect(store.entries.count == 2)
        #expect(store.entries[0].text == "me updated")
        #expect(store.entries[1].text == "them updated")
    }

    @Test("interleaves entries from both sources chronologically")
    @MainActor
    func interleavedOrdering() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "first", isFinal: true)
        store.handleResult(source: .them, text: "second", isFinal: true)
        store.handleResult(source: .me, text: "third", isFinal: true)

        #expect(store.entries.count == 3)
        #expect(store.entries[0].source == .me)
        #expect(store.entries[1].source == .them)
        #expect(store.entries[2].source == .me)
    }

    @Test("filters empty text")
    @MainActor
    func filtersEmptyText() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "", isFinal: true)
        store.handleResult(source: .me, text: "   ", isFinal: true)
        store.handleResult(source: .me, text: "\n\t", isFinal: true)

        #expect(store.entries.isEmpty)
    }

    @Test("trims whitespace from text")
    @MainActor
    func trimsWhitespace() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "  hello  ", isFinal: true)

        #expect(store.entries[0].text == "hello")
    }

    @Test("clear removes all entries and resets volatile tracking")
    @MainActor
    func clearResetsState() {
        let store = TranscriptStore()
        store.handleResult(source: .me, text: "volatile", isFinal: false)
        store.handleResult(source: .them, text: "also volatile", isFinal: false)
        store.clear()

        #expect(store.entries.isEmpty)

        store.handleResult(source: .me, text: "fresh start", isFinal: false)
        #expect(store.entries.count == 1)
        #expect(store.entries[0].text == "fresh start")
    }

    @Test("does not create duplicate entries for rapid volatile updates")
    @MainActor
    func noDuplicatesOnRapidUpdates() {
        let store = TranscriptStore()
        for i in 1...10 {
            store.handleResult(source: .me, text: "partial \(i)", isFinal: false)
        }

        #expect(store.entries.count == 1)
        #expect(store.entries[0].text == "partial 10")
    }
}
