import XCTest
@testable import DLChat

@MainActor
final class BackupCheckTests: XCTestCase {
    private let phrase = "badge foam chunk kingdom spoil wages denim taxi vixen flag"

    func testMatchIgnoresCaseAndSpacing() {
        XCTAssertEqual(BackupCheck.compare(typed: " Badge FOAM chunk\nkingdom spoil, wages denim taxi vixen flag ", phrase: phrase), .matches)
    }

    func testReportsWordNumbersNotWords() {
        let result = BackupCheck.compare(typed: "badge foam chunk kingdom spoil wages denim taxi fox flag", phrase: phrase)
        XCTAssertEqual(result, .differ([9]))
        XCTAssertFalse(BackupCheck.message(result).contains("vixen"), "the real word is never revealed")
        XCTAssertEqual(BackupCheck.compare(typed: "badge foam", phrase: phrase), .wordCount(typed: 2, expected: 10))
    }
}
