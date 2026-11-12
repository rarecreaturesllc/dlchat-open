import CryptoKit
import XCTest
@testable import DLCore

final class SupportReportTests: XCTestCase {
    private let developer = Curve25519.KeyAgreement.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private var recipient: String { developer.publicKey.rawRepresentation.base64EncodedString() }

    func testOnlyTheDeveloperKeyOpensIt() throws {
        let report = "Tones never decode 😴\n\n--- Debug logs ---\nApp: DLChat 0.1 (11)"
        let event = try SupportReport.event(text: report, now: now, recipient: recipient)
        XCTAssertEqual(SupportReport.text(from: event, privateKey: developer), report)
        XCTAssertNil(SupportReport.text(from: event, privateKey: Curve25519.KeyAgreement.PrivateKey()))
    }

    func testLooksLikeAnyOtherGiftWrap() throws {
        let a = try SupportReport.event(text: "a", now: now, recipient: recipient)
        let b = try SupportReport.event(text: "a", now: now, recipient: recipient)
        XCTAssertTrue(a.isValid)
        XCTAssertEqual(a.kind, 1059)
        XCTAssertEqual(a.tags.first, ["p", SupportReport.mailbox])
        XCTAssertEqual(a.tags.last?.first, "expiration")
        // A throwaway author and fresh sealing per post: two identical reports share nothing.
        XCTAssertNotEqual(a.pubkey, b.pubkey)
        XCTAssertNotEqual(a.content, b.content)
        XCTAssertLessThanOrEqual(a.createdAt, Int(now.timeIntervalSince1970))
        XCTAssertGreaterThanOrEqual(a.createdAt, Int(now.timeIntervalSince1970 - Online.blur))
    }

    func testTamperingIsRejected() throws {
        let event = try SupportReport.event(text: "hello", now: now, recipient: recipient)
        var content = Array(Data(base64Encoded: event.content)!)
        content[40] ^= 1
        let forged = Online.Event(id: event.id, pubkey: event.pubkey, createdAt: event.createdAt, kind: event.kind,
                                  tags: event.tags, content: Data(content).base64EncodedString(), sig: event.sig)
        XCTAssertNil(SupportReport.text(from: forged, privateKey: developer))
    }

    func testLengthOnlyShowsABucketAndHasALimit() throws {
        func sealedSize(_ text: String) throws -> Int {
            Data(base64Encoded: try SupportReport.event(text: text, now: now, recipient: recipient).content)!.count
        }
        // 32-byte encapsulated key + padded plaintext + 16-byte tag.
        XCTAssertEqual(try sealedSize("short"), 32 + 1024 + 16)
        XCTAssertEqual(try sealedSize(String(repeating: "x", count: 900)), 32 + 1024 + 16)
        XCTAssertEqual(try sealedSize(String(repeating: "x", count: 3_000)), 32 + 4096 + 16)
        XCTAssertThrowsError(try SupportReport.event(text: String(repeating: "x", count: 4_095), now: now, recipient: recipient))
    }

    func testShippedKeyAndMailboxAreWellFormed() throws {
        // The reader on the developer's Mac looks for this exact mailbox: changing it strands reports.
        XCTAssertEqual(SupportReport.mailbox, "5283f1180d39b00b3ba90d7e7e61c1b63d5526360135c48f14bc2ae3788f46a0")
        XCTAssertNoThrow(try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: XCTUnwrap(Data(base64Encoded: SupportReport.developerKey))))
        XCTAssertNoThrow(try SupportReport.event(text: "shipped key", now: now))
    }
}
