import XCTest
@testable import DLChat

final class SupportMailTests: XCTestCase {
    func testDraftGoesToSupportWithTheNoteFirst() throws {
        let body = SupportMail.body(problem: "  Tones never decode & stalls 😴  ")
        XCTAssertTrue(body.hasPrefix("Tones never decode & stalls 😴\n\n--- Debug logs"))
        let url = try XCTUnwrap(SupportMail.url(body: body))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, SupportMail.address)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "body" }?.value, body)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "subject" }?.value, "DLChat debug logs")
    }
}
