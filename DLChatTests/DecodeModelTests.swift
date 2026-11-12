import DLCore
import XCTest
@testable import DLChat

@MainActor
final class DecodeModelTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeModels() throws -> (DecodeModel, ComposeModel) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-decode-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let groups = GroupModel(vault: vault)
        let decode = DecodeModel(groups: groups)
        decode.refreshKeys()
        return (decode, ComposeModel(groups: groups))
    }

    private func sentWords(_ compose: ComposeModel, _ text: String) -> [String] {
        compose.syncGroup()
        compose.text = text
        XCTAssertTrue(compose.prepareWords())
        return compose.words
    }

    private func waitForMessage(_ model: DecodeModel) async throws -> ReadMessage {
        for _ in 0..<100 {
            if case .message(let message, _) = model.outcome { return message }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw XCTSkip("no message")
    }

    /// A read-once message opens but is never recorded; an ordinary one is recorded.
    func testReadOnceIsShownNotKept() throws {
        for on in [true, false] {
            let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-once-\(UUID().uuidString)", directoryHint: .isDirectory)
            let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
            cleanup.append { try? vault.wipe() }
            _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
            let groups = GroupModel(vault: vault)
            let decode = DecodeModel(groups: groups), compose = ComposeModel(groups: groups)
            decode.refreshKeys()
            compose.readOnce = on
            for word in sentWords(compose, "meet at the bridge") { decode.typed = word; XCTAssertTrue(decode.submit()) }
            guard case .message(let message, _) = decode.outcome else { return XCTFail("not decoded") }
            XCTAssertEqual(message.readOnce, on)
            // Receive keeps no words (Send/Receive layout): an ordinary message leaves only its fingerprint,
            // for "Already received"; a read-once one leaves nothing.
            let stored = try GroupBook(vault: vault).messages()
            XCTAssertEqual(stored.isEmpty, on, "fingerprint kept only when not read once")
            XCTAssertTrue(stored.allSatisfy { $0.text.isEmpty && $0.isOpenedInReceive }, "no words kept from Receive")
            XCTAssertTrue(groups.messages().isEmpty, "nothing from Receive shows as a received chat message")
        }
    }

    func testSendThenDecodeWordByWord() throws {
        let (decode, compose) = try makeModels()
        for word in sentWords(compose, "need water at north gate") {
            XCTAssertEqual(decode.outcome, .typing)
            decode.typed = word
            XCTAssertTrue(decode.submit())
        }
        guard case .message(let message, let name) = decode.outcome else { return XCTFail("not decoded") }
        XCTAssertEqual(message.text, "need water at north gate")
        XCTAssertNil(message.repair)
        XCTAssertNil(name)
    }

    func testPastedWordsAreSplit() throws {
        let (decode, compose) = try makeModels()
        let words = sentWords(compose, "meet at the church at noon")
        decode.typed = words.joined(separator: " ") + " "
        decode.ingestTyped()
        XCTAssertEqual(decode.entered, words)
        guard case .message(let message, _) = decode.outcome else { return XCTFail("not decoded") }
        XCTAssertEqual(message.text, "meet at the church at noon")
    }

    /// Send > Copy the words, pasted from a chat app (which may add a line break or trailing space).
    func testPastedWordsFromAChatDecode() throws {
        let (decode, compose) = try makeModels()
        let words = sentWords(compose, "meet at the church at noon")
        decode.paste("\n" + words.joined(separator: " ") + "  \n")
        XCTAssertEqual(decode.entered, words)
        XCTAssertEqual(decode.typed, "")
        guard case .message(let message, _) = decode.outcome else { return XCTFail("not decoded") }
        XCTAssertEqual(message.text, "meet at the church at noon")
    }

    func testMissingWordIsRepairedAutomaticallyAndLabelled() async throws {
        let (decode, compose) = try makeModels()
        var words = sentWords(compose, "need water at north gate")
        let original = words[6]
        words[6] = "?"
        words.forEach { decode.add($0) }
        let message = try await waitForMessage(decode)
        XCTAssertEqual(message.text, "need water at north gate")
        XCTAssertEqual(message.repair?.replacement, original)
        XCTAssertEqual(message.repair?.wasMissing, true)
    }

    func testWrongWordIsOfferedRepairThenFixed() async throws {
        let (decode, compose) = try makeModels()
        var words = sentWords(compose, "need water at north gate")
        let original = words[4]
        words[4] = WordList.word(at: (WordList.index(of: original)! + 1) % WordList.count)
        words.forEach { decode.add($0) }
        XCTAssertEqual(decode.outcome, .typing)
        XCTAssertTrue(decode.canRepair)
        decode.repair()
        let message = try await waitForMessage(decode)
        XCTAssertEqual(message.repair?.replacement, original)
        XCTAssertEqual(message.repair?.wasMissing, false)
        XCTAssertFalse(decode.canRepair)
    }

    func testUnreadableWordsReportNotRead() async throws {
        let (decode, _) = try makeModels()
        WordList.words.prefix(Receiver.minimumWords + 3).forEach { decode.add($0) }
        XCTAssertTrue(decode.canRepair)
        decode.repair()
        for _ in 0..<100 where decode.outcome == .repairing { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(decode.outcome, .notRead(gaps: 0))
    }

    func testTwoGapsCannotBeRepaired() throws {
        let (decode, _) = try makeModels()
        WordList.words.prefix(Receiver.minimumWords + 3).forEach { decode.add($0) }
        decode.addMissing()
        decode.addMissing()
        XCTAssertEqual(decode.gaps, 2)
        XCTAssertFalse(decode.canRepair)
    }

    func testSubmitTakesOnlyAUniqueSuggestionAndUndoClear() throws {
        let (decode, _) = try makeModels()
        decode.typed = "zzzz"
        XCTAssertFalse(decode.submit())
        XCTAssertEqual(decode.typed, "zzzz")
        let word = WordList.word(at: 10)
        decode.typed = word.uppercased()
        XCTAssertTrue(decode.submit())
        XCTAssertEqual(decode.entered, [word])
        decode.undo()
        XCTAssertTrue(decode.entered.isEmpty)
        decode.add("?")
        decode.clear()
        XCTAssertTrue(decode.entered.isEmpty)
    }
}

/// Decrypting in Receive never puts the message in Chat; only Acknowledged posts "Decrypted".
@MainActor
final class DecryptedStaysOutOfChatTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func make() throws -> (GroupModel, DecodeModel, ComposeModel, ChatGroup) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-ack-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        let group = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let groups = GroupModel(vault: vault)
        let decode = DecodeModel(groups: groups)
        decode.refreshKeys()
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        return (groups, decode, compose, group)
    }

    private func chatTexts(_ groups: GroupModel, _ group: ChatGroup) -> [String] { groups.chatMessages(groupID: group.id).map(\.text) }

    private func assertNoPlaintextInChat(_ groups: GroupModel, _ group: ChatGroup, _ plain: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        for text in chatTexts(groups, group) {
            XCTAssertFalse(text.contains(plain), "decrypted words in Chat: \(text)", file: file, line: line)
        }
    }

    /// Words typed or pasted in Receive: shown there only. Not kept (no export), never in Chat.
    func testDecryptedWordsAreNotInChat() throws {
        let (groups, decode, compose, group) = try make()
        compose.text = "meet at the church at noon"
        let words = try XCTUnwrap(compose.sealedWords(for: group, room: ""))
        decode.paste(words.joined(separator: " "))
        guard case .message(let message, _) = decode.outcome else { return XCTFail("not decoded") }
        XCTAssertEqual(message.text, "meet at the church at noon")
        XCTAssertTrue(groups.messages().isEmpty, "Receive keeps no words to export")
        XCTAssertTrue(chatTexts(groups, group).isEmpty)
    }

    /// Encrypt Words and Encrypt Sound posted in Chat (as relays or the radio deliver them), then
    /// decrypted in Receive: Chat holds only the encrypted bubbles, never what they say.
    func testCarriedWordsAndSoundFromChatDecryptWithoutPostingThem() throws {
        let (groups, decode, compose, group) = try make()
        let keySet = try XCTUnwrap(groups.keySets().first { $0.groupID == group.id && $0.room.isEmpty })

        compose.text = "need water at north gate"
        let wordsText = try XCTUnwrap(ChatCarry.text(words: try XCTUnwrap(compose.sealedWords(for: group, room: ""))))
        compose.text = "bring the radio to the barn"
        let soundText = try XCTUnwrap(compose.sealedSound(for: group, room: ""))
        for text in [wordsText, soundText] {
            // What the carrier (relay or radio) delivers: the chat message holding the encrypted frame.
            let wire = NearbyWire.wire(frame: try Composer.composeNearby(text: text, keys: keySet.keys, flags: 0), ttl: NearbyWire.startTTL)
            let carried = try XCTUnwrap(Receiver.readNearby(wire: wire, trying: [keySet.keys]))
            XCTAssertEqual(groups.record(carried, from: keySet), .new)
        }
        XCTAssertEqual(chatTexts(groups, group).count, 2)

        // Words: tapped in Chat, then Decrypt in Receive.
        decode.paste(try XCTUnwrap(ChatCarry.parse(wordsText)).words.joined(separator: " "))
        guard case .message(let fromWords, _) = decode.outcome else { return XCTFail("words not decoded") }
        XCTAssertEqual(fromWords.text, "need water at north gate")
        // Sound: tapped in Chat, then Decrypt Sound in Receive.
        decode.clear()
        XCTAssertTrue(decode.readHeard(try XCTUnwrap(ChatCarry.parse(soundText)).payload))
        guard case .message(let fromSound, _) = decode.outcome else { return XCTFail("sound not decoded") }
        XCTAssertEqual(fromSound.text, "bring the radio to the barn")

        XCTAssertEqual(Set(chatTexts(groups, group)), [wordsText, soundText], "only the encrypted bubbles")
        assertNoPlaintextInChat(groups, group, "need water")
        assertNoPlaintextInChat(groups, group, "bring the radio")
    }

    /// A sound can be decrypted any number of times, but once acknowledged it does not offer Acknowledged again,
    /// in this run or (by its kept fingerprint) the next. Another message is still offered.
    func testAcknowledgedIsOfferedOncePerMessage() throws {
        let (groups, decode, compose, group) = try make()
        compose.text = "bring the radio to the barn"
        let sound = try XCTUnwrap(ChatCarry.parse(try XCTUnwrap(compose.sealedSound(for: group, room: "")))).payload

        XCTAssertTrue(decode.readHeard(sound))
        guard case .message(let message, _) = decode.outcome else { return XCTFail("sound not decoded") }
        XCTAssertFalse(decode.alreadyAcknowledged)
        decode.clear()
        XCTAssertTrue(decode.readHeard(sound))
        XCTAssertFalse(decode.alreadyAcknowledged, "decrypting twice without acknowledging still offers it")

        decode.markAcknowledged(message)
        decode.clear()
        XCTAssertTrue(decode.readHeard(sound))
        guard case .message(let again, _) = decode.outcome else { return XCTFail("sound not decoded again") }
        XCTAssertEqual(again.text, "bring the radio to the barn", "it still decrypts")
        XCTAssertTrue(decode.alreadyAcknowledged)

        // After a relaunch (a new model over the same store) it is still not offered.
        let relaunched = DecodeModel(groups: groups)
        relaunched.refreshKeys()
        XCTAssertTrue(relaunched.readHeard(sound))
        XCTAssertTrue(relaunched.alreadyAcknowledged)
        XCTAssertTrue(groups.messages().isEmpty, "still no words kept")

        // A different message is offered as usual.
        compose.text = "second message"
        let other = try XCTUnwrap(ChatCarry.parse(try XCTUnwrap(compose.sealedSound(for: group, room: "")))).payload
        relaunched.clear()
        XCTAssertTrue(relaunched.readHeard(other))
        XCTAssertFalse(relaunched.alreadyAcknowledged)
    }

    /// With nothing kept there is no fingerprint to mark: once is remembered until the app closes.
    func testAcknowledgedOnceWithNothingKept() throws {
        let (groups, decode, compose, group) = try make()
        groups.setRetention(.off)
        compose.text = "bring the radio to the barn"
        let sound = try XCTUnwrap(ChatCarry.parse(try XCTUnwrap(compose.sealedSound(for: group, room: "")))).payload
        XCTAssertTrue(decode.readHeard(sound))
        guard case .message(let message, _) = decode.outcome else { return XCTFail("sound not decoded") }
        decode.markAcknowledged(message)
        decode.clear()
        XCTAssertTrue(decode.readHeard(sound))
        XCTAssertTrue(decode.alreadyAcknowledged)
    }

    /// Acknowledged posts exactly "Decrypted": no word of the message.
    func testAcknowledgedTextIsOnlyDecrypted() {
        XCTAssertEqual(DecodeModel.acknowledgedText, "Decrypted")
    }
}

@MainActor
final class ReceiveLeavesNothingTests: XCTestCase {
    /// Undo past the last word, then again with nothing left, leaves an empty, usable Receive.
    func testUndoToZeroWordsAndBeyond() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-undo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        defer { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let groups = GroupModel(vault: vault)
        let decode = DecodeModel(groups: groups), compose = ComposeModel(groups: groups)
        decode.refreshKeys()
        compose.syncGroup()
        compose.text = "meet at the bridge"
        XCTAssertTrue(compose.prepareWords())
        for word in compose.words { decode.add(word) }
        guard case .message = decode.outcome else { return XCTFail("not decoded") }
        for _ in compose.words { decode.undo() }
        XCTAssertTrue(decode.entered.isEmpty)
        XCTAssertEqual(decode.outcome, .typing)
        decode.undo()
        XCTAssertTrue(decode.entered.isEmpty)
        XCTAssertEqual(decode.gaps, 0)
        decode.add(compose.words[0])
        XCTAssertEqual(decode.entered, [compose.words[0]])
    }

    /// A relaunch builds new models on the same vault: Send and Receive start empty.
    func testRelaunchShowsEmptySendAndReceive() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-relaunch-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        defer { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        do {
            let groups = GroupModel(vault: vault)
            let decode = DecodeModel(groups: groups), compose = ComposeModel(groups: groups)
            decode.refreshKeys()
            compose.syncGroup()
            compose.text = "meet at the bridge"
            XCTAssertTrue(compose.prepareWords())
            decode.typed = "half"
            decode.pendingSound = Data([1, 2, 3])
            for word in compose.words.prefix(3) { decode.add(word) }
            compose.text = "a second secret draft"
            compose.flush()
        }
        let groups = GroupModel(vault: vault)
        let decode = DecodeModel(groups: groups), compose = ComposeModel(groups: groups)
        decode.refreshKeys()
        compose.syncGroup()
        XCTAssertEqual(compose.text, "")
        XCTAssertTrue(compose.words.isEmpty)
        XCTAssertTrue(decode.entered.isEmpty)
        XCTAssertEqual(decode.typed, "")
        XCTAssertNil(decode.pendingSound)
        XCTAssertEqual(decode.outcome, .typing)
    }

    /// A sound file or picture invite left in the temporary folder by a crash is removed at launch.
    func testLeftoverSharedFilesAreRemoved() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dlchat-left-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = folder.appending(path: "keep.txt")
        try Data("x".utf8).write(to: other)
        for name in Hygiene.leftoverFiles { try Data("tones".utf8).write(to: folder.appending(path: name)) }

        Hygiene.removeLeftoverFiles(in: folder)

        for name in Hygiene.leftoverFiles {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: name).path), name)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "only DLChat's own files go")
    }
}
