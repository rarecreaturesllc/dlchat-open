import DLCore
import XCTest
@testable import DLChat

/// Play as sound > Share as a sound file, then Receive > Open a sound file.
final class SoundFileTests: XCTestCase {
    func testTonesSurviveTheWavFileRoundTrip() throws {
        let payload = Data((0..<120).map { UInt8(truncatingIfNeeded: $0 &* 37) })
        let url = try XCTUnwrap(SoundFile.write(Modem.encode(Array(payload))))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "wav")
        XCTAssertEqual(SoundFile.bursts(in: url), [payload])
    }

    func testANonSoundFileIsRefused() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "not-sound-\(UUID().uuidString).wav")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(SoundFile.bursts(in: url))
    }
}
