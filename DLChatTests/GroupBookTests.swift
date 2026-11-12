import DLCore
import XCTest
@testable import DLChat

final class GroupBookTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    /// A fresh vault on a unique Keychain service and temp directory: one "phone".
    private func makePhone() -> (Vault, GroupBook) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-groups-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return (vault, GroupBook(vault: vault))
    }

    func testTwoPhonesGetSameKeysAndSafetyWords() throws {
        let (_, phoneA) = makePhone()
        let (_, phoneB) = makePhone()

        let created = PreparedGroup(phrase: try Phrase.generate(words: 10))
        let groupA = try phoneA.add(name: "Maple Street", prepared: created)

        // Phone B types the words that phone A displayed, in different case and spacing.
        let typed = created.phrase.words.joined(separator: "  ").uppercased()
        guard case .success(let parsed) = GroupBook.parse(typed) else { return XCTFail("phrase should parse") }
        let joined = PreparedGroup(phrase: parsed)
        let groupB = try phoneB.add(name: "Maple", prepared: joined)

        XCTAssertEqual(created.safetyWords.count, 3)
        XCTAssertEqual(created.safetyWords, joined.safetyWords)
        XCTAssertEqual(created.masterData, joined.masterData)

        // Stored keys are interchangeable: a frame sealed on A opens with B's keys, and not with another room's.
        let keysA = try XCTUnwrap(phoneA.keys(for: groupA))
        let keysB = try XCTUnwrap(phoneB.keys(for: groupB))
        let sealed = try Frame.seal(body: Bits(bytes: [0xA5, 0x5A, 0x11], count: 24), flags: 0, sentAt: Date(), keys: keysA, tagBits: 64)
        XCTAssertNotNil(Frame.open(sealed, tagBits: 64, trying: [keysB]))
        let otherRoom = try XCTUnwrap(phoneB.keys(for: groupB, room: "north"))
        XCTAssertNil(Frame.open(sealed, tagBits: 64, trying: [otherRoom]))
    }

    func testBadChecksumNamesTheProblem() throws {
        let phrase = try Phrase.generate(words: 15)
        var indices = phrase.indices
        var result: Result<Phrase, JoinProblem>?
        // Swap one word for another valid word until the checksum fails (15 of 16 swaps do).
        for candidate in 1..<1024 {
            indices[3] = (phrase.indices[3] + candidate) % 1024
            let text = indices.map(WordList.word(at:)).joined(separator: " ")
            let attempt = GroupBook.parse(text)
            if case .failure = attempt { result = attempt; break }
        }
        guard case .failure(let problem) = try XCTUnwrap(result) else { return XCTFail() }
        XCTAssertEqual(problem, .badChecksum)
        XCTAssertTrue(problem.message.contains("checksum"))
    }

    func testUnknownWordAndLengthAreNamed() throws {
        let words = try Phrase.generate(words: 10).words
        var typed = words
        typed[4] = "zzzzqx"
        XCTAssertEqual(GroupBook.parse(typed.joined(separator: " ")).failureValue, .unknownWord(position: 5, word: "zzzzqx"))
        XCTAssertTrue(JoinProblem.unknownWord(position: 5, word: "zzzzqx").message.contains("Word 5"))

        XCTAssertEqual(GroupBook.parse(words.dropLast().joined(separator: " ")).failureValue, .wrongLength(9))
        XCTAssertTrue(JoinProblem.wrongLength(9).message.contains("9"))
    }

    func testGroupsPersistAndDuplicatePhraseIsRejected() throws {
        let (vault, book) = makePhone()
        let prepared = PreparedGroup(phrase: try Phrase.generate(words: 10))
        let saved = try book.add(name: "  ", prepared: prepared)
        XCTAssertEqual(saved.name, "Group 1")

        // A new book over the same vault sees the group; the store file is not plaintext.
        let reopened = GroupBook(vault: vault)
        XCTAssertEqual(try reopened.groups().map(\.id), [saved.id])
        XCTAssertEqual(try reopened.phraseText(for: saved), prepared.phrase.text)
        let file = try Data(contentsOf: vault.storeURL)
        XCTAssertNil(file.range(of: Data("Group 1".utf8)))

        XCTAssertThrowsError(try reopened.add(name: "Again", prepared: prepared)) {
            XCTAssertEqual($0 as? JoinProblem, .alreadyJoined(name: "Group 1"))
        }
        XCTAssertEqual(try reopened.groups().count, 1)
    }

    func testWipeRemovesGroupsAndKeys() throws {
        let (vault, book) = makePhone()
        let group = try book.add(name: "Gone", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        try vault.wipe()
        XCTAssertEqual(try book.groups(), [])
        XCTAssertNil(try book.keys(for: group))
        XCTAssertNil(try book.phraseText(for: group))
    }

    /// Reads come from a decrypted copy kept in memory, but only while the file on disk is the one it came from.
    func testCachedReadsFollowOtherWritersAndWipes() throws {
        let (vault, book) = makePhone()
        let other = GroupBook(vault: vault)
        _ = try book.add(name: "One", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        XCTAssertEqual(try book.groups().map(\.name), ["One"])
        XCTAssertEqual(try book.groups().map(\.name), ["One"], "the second read is served from memory")
        _ = try other.add(name: "Two", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        XCTAssertEqual(try book.groups().map(\.name), ["One", "Two"], "a write by anyone replaces the file, so the copy is not used")
        try book.setRetention(.week)
        XCTAssertEqual(try other.retention(), .week)
        try vault.wipe()
        XCTAssertEqual(try book.groups(), [], "nothing decrypted outlives a wipe")
        XCTAssertEqual(try other.groups(), [])
    }

    // MARK: Group list (T023)

    private func addThree(_ book: GroupBook) throws -> [ChatGroup] {
        try ["A", "B", "C"].map { try book.add(name: $0, prepared: PreparedGroup(phrase: try Phrase.generate(words: 10))) }
    }

    func testActiveGroupDefaultsToFirstAndFollowsTheChoice() throws {
        let (_, book) = makePhone()
        let groups = try addThree(book)
        XCTAssertNil(try book.activeGroupID())
        try book.setActive(groups[2].id)
        XCTAssertEqual(try book.activeGroupID(), groups[2].id)
        try book.setActive(UUID())
        XCTAssertEqual(try book.activeGroupID(), groups[2].id, "unknown ids are ignored")
    }

    func testReorderRenumbersAndKeepsTheActiveChoice() throws {
        let (_, book) = makePhone()
        let groups = try addThree(book)
        try book.setActive(groups[1].id)
        try book.moveGroups(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(try book.groups().map(\.name), ["C", "A", "B"])
        XCTAssertEqual(try book.groups().map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(try book.activeGroupID(), groups[1].id)
    }

    @MainActor
    func testHistoryShowsOnlyTheActiveGroup() throws {
        let (vault, book) = makePhone()
        let groups = try addThree(book)
        for (group, text) in [(groups[0], "meet at the bridge at noon"), (groups[1], "need water at north gate")] {
            let keys = try XCTUnwrap(try book.keys(for: group))
            try book.record(try XCTUnwrap(Receiver.read(words: try Composer.compose(text: text, keys: keys), trying: [keys])), group: group, room: "")
        }
        let model = GroupModel(vault: vault)
        model.setActive(groups[1])

        XCTAssertEqual(model.messages().count, 2)
        XCTAssertEqual(model.activeGroupMessages().map(\.groupID), [groups[1].id])
    }

    func testRemovingAGroupDeletesItsKeysMessagesAndDraft() throws {
        let (vault, book) = makePhone()
        let groups = try addThree(book)
        let doomed = groups[1]
        let keys = try XCTUnwrap(try book.keys(for: doomed))
        let words = try Composer.compose(text: "need water at north gate", keys: keys)
        let message = try XCTUnwrap(Receiver.read(words: words, trying: [keys]))
        try book.record(message, group: doomed, room: "")
        let kept = try XCTUnwrap(try book.keys(for: groups[0]))
        try book.record(try XCTUnwrap(Receiver.read(words: try Composer.compose(text: "meet at the bridge at noon", keys: kept), trying: [kept])), group: groups[0], room: "")
        try book.setDraft("unsent", for: doomed.id)
        try book.setActive(doomed.id)

        try book.removeGroup(doomed)

        XCTAssertEqual(try book.groups().map(\.name), ["A", "C"])
        XCTAssertEqual(try book.groups().map(\.sortIndex), [0, 1])
        XCTAssertNil(try book.keys(for: doomed))
        XCTAssertNil(try book.phraseText(for: doomed))
        XCTAssertNil(try vault.secret(account: "master/\(doomed.id.uuidString)"))
        XCTAssertEqual(try book.messages(groupID: doomed.id), [])
        XCTAssertEqual(try book.messages(groupID: groups[0].id).count, 1)
        XCTAssertEqual(try book.draft(for: doomed.id), "")
        XCTAssertNil(try book.activeGroupID())
        XCTAssertNotNil(try book.keys(for: groups[0]), "other groups keep their keys")
    }

    @MainActor
    func testDeletingOneMessageLeavesTheRest() throws {
        let (_, book) = makePhone()
        let group = try book.add(name: "A", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let keys = try XCTUnwrap(try book.keys(for: group))
        for text in ["need water at north gate", "meet at the bridge at noon"] {
            let read = try XCTUnwrap(Receiver.read(words: try Composer.compose(text: text, keys: keys), trying: [keys]))
            try book.record(read, group: group, room: "")
        }
        let all = try book.messages()
        XCTAssertEqual(all.count, 2)
        try book.deleteMessage(id: all[0].id)
        XCTAssertEqual(try book.messages().map(\.id), [all[1].id])
    }

    @MainActor
    func testModelFollowsTheActiveGroupAndFallsBackAfterRemoval() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-groups-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        let model = GroupModel(vault: vault)
        for name in ["A", "B"] { try model.save(name: name, prepared: try await model.prepareNew(words: 10)) }
        XCTAssertEqual(model.activeGroup?.name, "A")
        model.setActive(model.groups[1])
        XCTAssertEqual(model.activeGroup?.name, "B")
        XCTAssertEqual(model.safetyWords(of: model.groups[1]).count, 3)
        XCTAssertNotNil(model.phrase(of: model.groups[1]))
        XCTAssertTrue(model.remove(model.groups[1]))
        XCTAssertEqual(model.activeGroup?.name, "A")
        XCTAssertTrue(model.remove(model.groups[0]))
        XCTAssertNil(model.activeGroup)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
