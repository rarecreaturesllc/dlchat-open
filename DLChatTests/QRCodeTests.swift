import CoreImage
import DLCore
import XCTest
@testable import DLChat

@MainActor
final class QRCodeTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    /// Reads QR codes out of an image the way a scanner does, with Core Image's detector.
    private func detect(_ image: UIImage) throws -> [String] {
        let ci = try XCTUnwrap(CIImage(image: image))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        return detector.features(in: ci).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    private func makeModels() -> (GroupModel, ComposeModel, DecodeModel) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-qr-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        let groups = GroupModel(vault: vault)
        return (groups, ComposeModel(groups: groups), DecodeModel(groups: groups))
    }

    func testGeneratedFrameCodeIsReadBackByTheDetector() throws {
        let keys = Keys(phrase: try Phrase.generate(words: 10))
        for text in ["ok", "need water at north gate", Array(repeating: "meet at the bridge at noon", count: 8).joined(separator: " ")] {
            let payload = try Composer.composeQR(text: text, keys: keys)
            let image = try XCTUnwrap(QRImage.make(payload), "code for \(text.count) characters")
            let found = try detect(image)
            XCTAssertEqual(found, [payload])
            XCTAssertEqual(Receiver.readQR(payload: try XCTUnwrap(found.first), trying: [keys])?.text, text)
        }
    }

    func testPhraseCodeRoundTripsToTheSameGroup() throws {
        let phrase = try Phrase.generate(words: 20)
        let image = try XCTUnwrap(QRImage.make(phrase.text))
        let found = try XCTUnwrap(try detect(image).first)
        XCTAssertTrue(GroupSetupView.looksLikePhrase(found))
        XCTAssertEqual(try Phrase.parse(found), phrase)
    }

    func testMessageCodeIsNotTakenForAPhraseAndNothingElseIsEither() throws {
        let keys = Keys(phrase: try Phrase.generate(words: 10))
        XCTAssertFalse(GroupSetupView.looksLikePhrase(try Composer.composeQR(text: "hello", keys: keys)))
        XCTAssertFalse(GroupSetupView.looksLikePhrase("https://example.com"))
    }

    func testTextTooLongForOneCodeGivesNoImage() {
        XCTAssertNil(QRImage.make(String(repeating: "A", count: 4000)))
    }

    func testScanningOpensTheMessageAndASecondScanIsLabelledARepeat() async throws {
        let (groups, compose, decode) = makeModels()
        let prepared = try await groups.prepareNew(words: 10)
        try groups.save(name: "Test", prepared: prepared)
        compose.syncGroup()
        decode.refreshKeys()

        compose.text = "need water at north gate"
        XCTAssertTrue(compose.prepareQR())
        let payload = compose.qr
        XCTAssertFalse(payload.isEmpty)

        XCTAssertTrue(decode.readScanned(payload))
        guard case .message(let message, _) = decode.outcome else { return XCTFail("no message shown") }
        XCTAssertEqual(message.text, "need water at north gate")
        XCTAssertNil(decode.heardBefore)

        XCTAssertTrue(decode.readScanned(payload))
        XCTAssertNotNil(decode.heardBefore)
    }

    func testScanningACodeFromAnotherGroupOrNoCodeChangesNothing() async throws {
        let (groups, compose, decode) = makeModels()
        let prepared = try await groups.prepareNew(words: 10)
        try groups.save(name: "Test", prepared: prepared)
        compose.syncGroup()
        decode.refreshKeys()

        let stranger = Keys(phrase: try Phrase.generate(words: 10))
        let foreign = try Composer.composeQR(text: "not for you", keys: stranger)
        XCTAssertFalse(decode.readScanned(foreign))
        XCTAssertFalse(decode.readScanned("https://example.com"))
        XCTAssertEqual(decode.outcome, .typing)
    }

    func testWipeClearsThePreparedCode() async throws {
        let (groups, compose, _) = makeModels()
        let prepared = try await groups.prepareNew(words: 10)
        try groups.save(name: "Test", prepared: prepared)
        compose.syncGroup()
        compose.text = "meet at dawn"
        XCTAssertTrue(compose.prepareQR())
        compose.discard()
        XCTAssertEqual(compose.qr, "")
    }
}
