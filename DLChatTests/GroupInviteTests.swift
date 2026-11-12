import DLCore
import XCTest
@testable import DLChat

final class GroupInviteTests: XCTestCase {
    func testLinkRoundTripsPhraseAndName() throws {
        let phrase = try Phrase.generate(words: 15).text
        let invite = GroupInvite(phrase: phrase, name: "  Maple Street  ")
        XCTAssertTrue(invite.url.absoluteString.hasPrefix("dlchat://join?name=Maple%20Street#"))
        let back = try XCTUnwrap(GroupInvite(url: invite.url))
        XCTAssertEqual(back.phrase, phrase)
        XCTAssertEqual(back.name, "Maple Street")
        XCTAssertEqual(GroupBook.parse(back.phrase).map(\.text), .success(phrase))
    }

    func testLinkWithoutNameAndForeignLinks() throws {
        let invite = GroupInvite(phrase: "a b c", name: "")
        XCTAssertEqual(invite.url.absoluteString, "dlchat://join#a-b-c")
        XCTAssertNil(GroupInvite(url: URL(string: "dlchat://other#a-b-c")!))
        XCTAssertNil(GroupInvite(url: URL(string: "dlchat://join")!))
        XCTAssertNil(GroupInvite(url: URL(string: "https://join.example.com#a-b-c")!))
    }

    func testScannedCodesGiveThePhrase() {
        XCTAssertEqual(GroupInvite.phrase(fromCode: "dlchat://join?name=X#badge-foam"), "badge foam")
        XCTAssertEqual(GroupInvite.phrase(fromCode: " badge foam "), "badge foam", "older codes held bare words")
        XCTAssertNil(GroupInvite.phrase(fromCode: "https://example.com"))
    }
}
