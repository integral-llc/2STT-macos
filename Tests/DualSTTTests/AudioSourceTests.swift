@testable import DualSTT
import Foundation
import Testing

struct AudioSourceTests {
    @Test
    func `raw values are correct`() {
        #expect(AudioSource.me.rawValue == "ME")
        #expect(AudioSource.them.rawValue == "THEM")
    }

    @Test
    func `Codable round-trip preserves value`() throws {
        let original = AudioSource.me
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioSource.self, from: data)

        #expect(decoded == original)
    }

    @Test
    func `decodes from JSON string`() throws {
        let json = Data("\"THEM\"".utf8)
        let decoded = try JSONDecoder().decode(AudioSource.self, from: json)

        #expect(decoded == .them)
    }
}
