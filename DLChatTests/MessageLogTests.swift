import DLCore
import XCTest
@testable import DLChat

@MainActor
final class MessageLogTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-log-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    private func makeBook() throws -> (GroupBook, ChatGroup) {
        let book = GroupBook(vault: makeVault())
        let group = try book.add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        return (book, group)
    }

    private func read(_ text: String, book: GroupBook, group: ChatGroup, room: String = "") throws -> ReadMessage {
        let keys = try XCTUnwrap(try book.keys(for: group, room: room))
        let words = try Composer.compose(text: text, keys: keys)
        return try XCTUnwrap(Receiver.read(words: words, trying: [keys]))
    }

    // MARK: Duplicates

    func testHearingAMessageAgainIsLabelledWithTheFirstTime() throws {
        let (book, group) = try makeBook()
        let message = try read("need water at north gate", book: book, group: group)
        let first = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(try book.record(message, group: group, room: "", now: first), .new)
        XCTAssertEqual(try book.record(message, group: group, room: "", now: first.addingTimeInterval(600)),
                       .repeated(firstHeard: first))

        let kept = try book.messages()
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].timesHeard, 2)
        XCTAssertEqual(kept[0].recordedAt, first)
        XCTAssertEqual(kept[0].text, "need water at north gate")
    }

    /// Opened in Receive: only its fingerprint is kept (repeats), with no words, and marked so Chat leaves it
    /// out. If the same message later comes by chat itself it is a chat message after all, words included.
    func testOpenedInReceiveIsMarkedAndAChatCopyClearsIt() throws {
        let (book, group) = try makeBook()
        let message = try read("need water at north gate", book: book, group: group)
        XCTAssertEqual(try book.record(message, group: group, room: "", opened: true), .new)
        XCTAssertEqual(try book.messages().map(\.isOpenedInReceive), [true])
        XCTAssertEqual(try book.messages().map(\.text), [""], "no words kept from Receive")
        XCTAssertEqual(try book.record(message, group: group, room: "", opened: true), .repeated(firstHeard: try book.messages()[0].recordedAt))
        XCTAssertEqual(try book.messages().map(\.isOpenedInReceive), [true], "heard again in Receive: still kept out of Chat")
        _ = try book.record(message, group: group, room: "")
        XCTAssertEqual(try book.messages().map(\.isOpenedInReceive), [false])
        XCTAssertEqual(try book.messages().map(\.text), ["need water at north gate"])
    }

    /// Stores written before this field existed read as ordinary chat messages.
    func testOlderStoredMessagesAreNotOpened() throws {
        let json = #"{"id":"x","groupID":"\#(UUID().uuidString)","room":"","text":"hi","sentAt":0,"recordedAt":0,"duress":false,"timesHeard":1}"#
        let stored = try JSONDecoder().decode(StoredMessage.self, from: Data(json.utf8))
        XCTAssertFalse(stored.isOpenedInReceive)
    }

    func testDifferentMessagesAreNotDuplicates() throws {
        let (book, group) = try makeBook()
        let a = try read("need water at the north gate", book: book, group: group)
        let b = try read("need food at the south gate", book: book, group: group)
        XCTAssertEqual(try book.record(a, group: group, room: ""), .new)
        XCTAssertEqual(try book.record(b, group: group, room: ""), .new)
        XCTAssertEqual(try book.messages().count, 2)
    }

    func testStoredLogDoesNotHoldPlaintextOutsideTheSealedStore() throws {
        let vault = makeVault()
        let book = GroupBook(vault: vault)
        let group = try book.add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let message = try read("zebra marker sentence", book: book, group: group)
        try book.record(message, group: group, room: "")
        let files = try FileManager.default.contentsOfDirectory(at: vault.storeURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let bytes = try Data(contentsOf: file)
            XCTAssertNil(bytes.range(of: Data("zebra marker".utf8)))
        }
    }

    func testDecodeScreenFlagsASecondHearing() async throws {
        let vault = makeVault()
        let groups = GroupModel(vault: vault)
        let prepared = PreparedGroup(phrase: try Phrase.generate(words: 10))
        try groups.save(name: "Maple", prepared: prepared)
        let decode = DecodeModel(groups: groups)
        decode.refreshKeys()
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        compose.text = "move to the bridge"
        XCTAssertTrue(compose.prepareWords())

        for word in compose.words { decode.add(word) }
        guard case .message = decode.outcome else { return XCTFail("not read") }
        XCTAssertNil(decode.heardBefore, "first hearing is new")

        // Undo and retype the last word: the same hearing, not a repeat.
        decode.undo()
        decode.add(try XCTUnwrap(compose.words.last))
        guard case .message = decode.outcome else { return XCTFail("not read again") }
        XCTAssertNil(decode.heardBefore)

        // Start over and hear it again: a repeat.
        decode.clear()
        for word in compose.words { decode.add(word) }
        XCTAssertNotNil(decode.heardBefore)
    }

    // MARK: Rooms

    func testRoomIsolatesMessagesAndKeys() throws {
        let (book, group) = try makeBook()
        let withRoom = try book.addRoom("North", to: group)
        XCTAssertEqual(withRoom.rooms, ["north"])
        XCTAssertEqual(try book.addRoom("north ", to: withRoom).rooms, ["north"], "same room once")

        let main = try XCTUnwrap(try book.keys(for: group))
        let north = try XCTUnwrap(try book.keys(for: group, room: "north"))
        let south = try XCTUnwrap(try book.keys(for: group, room: "south"))
        let words = try Composer.compose(text: "meet at dawn", keys: north)
        XCTAssertEqual(Receiver.read(words: words, trying: [north])?.text, "meet at dawn")
        XCTAssertNil(Receiver.read(words: words, trying: [main]))
        XCTAssertNil(Receiver.read(words: words, trying: [south]))

        let inNorth = try XCTUnwrap(Receiver.read(words: words, trying: [north]))
        let mainMessage = try read("hello main", book: book, group: group)
        try book.record(inNorth, group: withRoom, room: "north")
        try book.record(mainMessage, group: withRoom, room: "")
        XCTAssertEqual(try book.messages(groupID: group.id, room: "north").map(\.text), ["meet at dawn"])
        XCTAssertEqual(try book.messages(groupID: group.id, room: "").map(\.text), ["hello main"])
        XCTAssertEqual(try book.messages().count, 2)
    }

    func testSameWordsInTwoRoomsAreNotDuplicates() throws {
        let (book, group) = try makeBook()
        let room = try book.addRoom("north", to: group)
        let a = try read("hold position", book: book, group: room)
        let b = try read("hold position", book: book, group: room, room: "north")
        XCTAssertEqual(try book.record(a, group: room, room: ""), .new)
        XCTAssertEqual(try book.record(b, group: room, room: "north"), .new)
    }

    func testReceiveReadsRoomMessageAndSendUsesRoom() async throws {
        let vault = makeVault()
        let groups = GroupModel(vault: vault)
        try groups.save(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        groups.addRoom("north", to: try XCTUnwrap(groups.groups.first))
        XCTAssertEqual(groups.groups.first?.rooms, ["north"])

        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        compose.room = "north"
        compose.text = "room message"
        XCTAssertTrue(compose.prepareWords())
        let decode = DecodeModel(groups: groups)
        decode.refreshKeys()
        for word in compose.words { decode.add(word) }
        guard case .message(let message, _) = decode.outcome else { return XCTFail("room message not read") }
        XCTAssertEqual(message.text, "room message")
        // Receive keeps only a fingerprint (no words), filed under the room it was sealed for.
        XCTAssertEqual(try GroupBook(vault: vault).messages().first?.room, "north")

        // The same words with the default room cannot be read.
        compose.room = ""
        compose.text = "main message"
        XCTAssertTrue(compose.prepareWords())
        decode.clear()
        for word in compose.words { decode.add(word) }
        guard case .message(let main, _) = decode.outcome else { return XCTFail("main not read") }
        XCTAssertEqual(main.text, "main message")
        let stored = try GroupBook(vault: vault).messages()
        XCTAssertEqual(Set(stored.map(\.room)), ["", "north"])
        XCTAssertTrue(stored.allSatisfy { $0.text.isEmpty }, "Receive keeps no words")
    }

    // MARK: Retention

    func testRetentionPurgesOnSchedule() throws {
        let (book, group) = try makeBook()
        let message = try read("old news", book: book, group: group)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(try book.retention(), .week, "default is 7 days")
        try book.record(message, group: group, room: "", now: t0)

        XCTAssertEqual(try book.purgeExpired(now: t0.addingTimeInterval(7 * 86_400 - 1)), 0)
        XCTAssertEqual(try book.messages().count, 1)
        XCTAssertEqual(try book.purgeExpired(now: t0.addingTimeInterval(7 * 86_400)), 1)
        XCTAssertTrue(try book.messages().isEmpty)
        // Forgotten, so hearing it again is new.
        XCTAssertEqual(try book.record(message, group: group, room: "", now: t0.addingTimeInterval(8 * 86_400)), .new)
    }

    func testRecordingAlsoPurges() throws {
        let (book, group) = try makeBook()
        let old = try read("first message from the bridge", book: book, group: group)
        let fresh = try read("second message from the gate", book: book, group: group)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try book.record(old, group: group, room: "", now: t0)
        try book.record(fresh, group: group, room: "", now: t0.addingTimeInterval(10 * 86_400))
        XCTAssertEqual(try book.messages().map(\.text), ["second message from the gate"])
    }

    func testShorterRetentionPurgesAtOnceAndOffKeepsNothing() throws {
        let (book, group) = try makeBook()
        let a = try read("keep a day", book: book, group: group)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try book.record(a, group: group, room: "", now: t0)

        try book.setRetention(.day, now: t0.addingTimeInterval(2 * 86_400))
        XCTAssertTrue(try book.messages().isEmpty)
        XCTAssertEqual(try book.retention(), .day)

        try book.setRetention(.off, now: t0)
        let b = try read("not kept", book: book, group: group)
        XCTAssertEqual(try book.record(b, group: group, room: "", now: t0), .new)
        XCTAssertEqual(try book.record(b, group: group, room: "", now: t0), .new, "off cannot tell a repeat")
        XCTAssertTrue(try book.messages().isEmpty)
    }

    func testForeverNeverPurges() throws {
        let (book, group) = try makeBook()
        try book.setRetention(.forever)
        let message = try read("we are still here at the bridge", book: book, group: group)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try book.record(message, group: group, room: "", now: t0)
        XCTAssertEqual(try book.purgeExpired(now: t0.addingTimeInterval(3650 * 86_400)), 0)
        XCTAssertEqual(try book.messages().count, 1)
    }

    func testRetentionAndMessagesSurviveANewBookOnTheSameVault() throws {
        let vault = makeVault()
        let book = GroupBook(vault: vault)
        let group = try book.add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        try book.setRetention(.month)
        try book.record(try read("persisted", book: book, group: group), group: group, room: "")
        let reopened = GroupBook(vault: vault)
        XCTAssertEqual(try reopened.retention(), .month)
        XCTAssertEqual(try reopened.messages().map(\.text), ["persisted"])
    }
}
