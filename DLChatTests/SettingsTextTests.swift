import XCTest
@testable import DLChat

final class SettingsTextTests: XCTestCase {
    private func message(_ text: String, room: String = "", at seconds: TimeInterval, group: UUID, duress: Bool = false) -> StoredMessage {
        StoredMessage(id: text, groupID: group, room: room, text: text, sentAt: Date(timeIntervalSince1970: seconds),
                      recordedAt: Date(timeIntervalSince1970: seconds), repairedWord: nil, duress: duress, timesHeard: 1)
    }

    func testExportIsEmptyWithNoMessages() {
        XCTAssertEqual(MessageExport.text(messages: [], groupNames: [:]), "")
    }

    func testExportListsOldestFirstWithGroupRoomAndPressureMark() {
        let id = UUID()
        let text = MessageExport.text(messages: [
            message("second", room: "bridge", at: 2_000_000, group: id, duress: true),
            message("first", at: 1_000_000, group: id),
        ], groupNames: [id: "Hikers"])
        let first = text.range(of: "first")!.lowerBound
        let second = text.range(of: "second")!.lowerBound
        XCTAssertLessThan(first, second)
        XCTAssertTrue(text.contains("Hikers / bridge (sent under pressure)"))
    }

    func testCopyStatesLimitsAndMakesNoOverclaim() {
        let all = (SettingsText.protectedList + SettingsText.notProtectedList + [SettingsText.exportNote, SettingsText.deletionNote]
                   + SettingsText.documents.flatMap(\.paragraphs)).joined(separator: " ").lowercased()
        for banned in ["unbreakable", "military-grade", "military grade", "100% secure", "guaranteed"] {
            XCTAssertFalse(all.contains(banned), banned)
        }
        XCTAssertTrue(all.contains("forward secrecy"))
        XCTAssertTrue(all.contains("not been reviewed by a lawyer"))
        XCTAssertTrue(SettingsText.exportNote.contains("Phrases are never included"))
    }

    func testStatesPINAddsNoEncryptionAndForensicLimit() {
        let notProtected = SettingsText.notProtectedList.joined(separator: " ").lowercased()
        XCTAssertTrue(notProtected.contains("pin only guards the screen"))
        XCTAssertTrue(notProtected.contains("adds no encryption"))
        XCTAssertTrue(notProtected.contains("forensic recovery"))
        XCTAssertTrue(notProtected.contains("cannot rule out"))
    }

    func testThreeDocumentsAndEFFAttribution() {
        XCTAssertEqual(SettingsText.documents.map(\.id), ["privacy", "terms", "licenses"])
        XCTAssertTrue(SettingsText.licenses.paragraphs.joined().contains("Creative Commons Attribution 3.0 US"))
    }
}
