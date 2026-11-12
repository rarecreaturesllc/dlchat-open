import DLCore
import XCTest
@testable import DLChat

/// Read receipts in the sealed store: off by default, both ways or not at all, only chat arrivals.
@MainActor
final class ReadReceiptBookTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-receipts-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    /// Two phones holding the same phrase.
    private func makePhones() throws -> (GroupBook, ChatGroup, GroupBook, ChatGroup) {
        let prepared = PreparedGroup(phrase: try Phrase.generate(words: 10))
        let a = GroupBook(vault: makeVault()), b = GroupBook(vault: makeVault())
        return (a, try a.add(name: "Maple", prepared: prepared), b, try b.add(name: "Maple", prepared: prepared))
    }

    private func chat(_ text: String, book: GroupBook, group: ChatGroup) throws -> ReadMessage {
        let keys = try XCTUnwrap(try book.keys(for: group))
        let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keys), ttl: 0)
        return try XCTUnwrap(Receiver.readNearby(wire: wire, trying: [keys]))
    }

    func testOffByDefaultNothingIsReportedOrNoted() throws {
        let (a, ga, b, gb) = try makePhones()
        let message = try chat("need water at north gate", book: a, group: ga)
        try a.recordSent(message, group: ga, room: "", via: "online", relays: 1)
        try b.record(message, group: gb, room: "", chat: true)
        XCTAssertTrue(try b.receiptGroups().isEmpty)
        XCTAssertEqual(try b.takeUnreported(groupID: gb.id), [])
        XCTAssertFalse(try a.applyReceipt(groupID: ga.id, reader: 9, refs: [ReadReceipt.ref(of: message, room: "")]))
    }

    /// Phone B reads phone A's message; A sees "Read by 1". The whole trip through a sealed receipt.
    func testReceiptGoesFromReaderToSender() throws {
        let (a, ga, b, gb) = try makePhones()
        try a.setReceipts(true, for: ga.id)
        try b.setReceipts(true, for: gb.id)
        let message = try chat("need water at north gate", book: a, group: ga)
        try a.recordSent(message, group: ga, room: "", via: "online", relays: 1)
        try b.record(message, group: gb, room: "", chat: true)

        let refs = try b.takeUnreported(groupID: gb.id)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(try b.takeUnreported(groupID: gb.id), [], "each message is reported once")

        let reader = try XCTUnwrap(try b.receiptSetting(for: gb.id)).reader
        let bKeys = try XCTUnwrap(try b.keys(for: gb)).receiptKeys
        let wire = try ReadReceipt.wire(reader: reader, refs: refs, keys: bKeys)
        let aKeys = try XCTUnwrap(try a.keys(for: ga)).receiptKeys
        let opened = try XCTUnwrap(ReadReceipt.open(wire: wire, trying: [aKeys]))
        XCTAssertTrue(try a.applyReceipt(groupID: ga.id, reader: opened.reader, refs: opened.refs))
        XCTAssertFalse(try a.applyReceipt(groupID: ga.id, reader: opened.reader, refs: opened.refs), "a reader counts once")
        XCTAssertEqual(try a.messages(groupID: ga.id).first?.readBy, [reader])
        XCTAssertEqual(ReadReceipts.label(try XCTUnwrap(try a.messages(groupID: ga.id).first), on: true), "Read by 1")
        XCTAssertNil(ReadReceipts.label(try XCTUnwrap(try a.messages(groupID: ga.id).first), on: false))
    }

    func testSenderWithReceiptsOffTakesNoNoticeAndOwnTagIsIgnored() throws {
        let (a, ga, _, _) = try makePhones()
        let message = try chat("need water at north gate", book: a, group: ga)
        try a.recordSent(message, group: ga, room: "", via: "online", relays: 1)
        let ref = ReadReceipt.ref(of: message, room: "")
        XCTAssertFalse(try a.applyReceipt(groupID: ga.id, reader: 5, refs: [ref]))
        try a.setReceipts(true, for: ga.id)
        let mine = try XCTUnwrap(try a.receiptSetting(for: ga.id)).reader
        XCTAssertFalse(try a.applyReceipt(groupID: ga.id, reader: mine, refs: [ref]))
        XCTAssertFalse(try a.applyReceipt(groupID: ga.id, reader: mine &+ 1, refs: [ref &+ 1]))
    }

    /// Decrypted on Receive, received before receipts were on, or encrypted words: never reported.
    func testOnlyChatArrivalsAfterTurningOnAreReported() throws {
        let (a, ga, b, gb) = try makePhones()
        let start = Date()
        try b.record(try chat("before it was on", book: a, group: ga), group: gb, room: "", chat: true, now: start.addingTimeInterval(-60))
        try b.setReceipts(true, for: gb.id, now: start)
        try b.record(try chat("decrypted in receive", book: a, group: ga), group: gb, room: "", now: start.addingTimeInterval(1))
        let keys = try XCTUnwrap(try a.keys(for: ga))
        let carried = try XCTUnwrap(ChatCarry.text(words: try Composer.compose(text: "meet at noon", keys: keys)))
        try b.record(try chat(carried, book: a, group: ga), group: gb, room: "", chat: true, now: start.addingTimeInterval(2))
        XCTAssertEqual(try b.takeUnreported(groupID: gb.id), [])
        let plain = try chat("in the chat", book: a, group: ga)
        try b.record(plain, group: gb, room: "", chat: true, now: start.addingTimeInterval(3))
        XCTAssertEqual(try b.takeUnreported(groupID: gb.id), [ReadReceipt.ref(of: plain, room: "")])
    }

    func testTurningOffForgetsTheTagAndRemovingTheGroupClearsIt() throws {
        let (a, ga, _, _) = try makePhones()
        try a.setReceipts(true, for: ga.id)
        XCTAssertEqual(try a.receiptGroups(), [ga.id])
        try a.setReceipts(false, for: ga.id)
        XCTAssertNil(try a.receiptSetting(for: ga.id))
        try a.setReceipts(true, for: ga.id)
        try a.removeGroup(ga)
        XCTAssertTrue(try a.receiptGroups().isEmpty)
    }
}
