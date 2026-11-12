import DLCore
import XCTest
@testable import DLChat

@MainActor
final class ComposeModelTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeVault() -> Vault {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-compose-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        return vault
    }

    private func addGroup(_ vault: Vault) throws {
        _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
    }

    /// Harold's rule: if the app crashes or is killed, nothing typed in Send remains.
    func testDraftDoesNotSurviveRelaunch() throws {
        let vault = makeVault()
        try addGroup(vault)

        let first = ComposeModel(groups: GroupModel(vault: vault))
        first.syncGroup()
        first.text = "need water at north gate"
        first.flush()
        XCTAssertEqual(first.text, "need water at north gate")

        // A new model on the same vault is what a killed and relaunched app builds.
        let second = ComposeModel(groups: GroupModel(vault: vault))
        second.syncGroup()
        XCTAssertEqual(second.text, "")
        XCTAssertEqual(second.count, 0)
        let id = try XCTUnwrap(try GroupBook(vault: vault).groups().first?.id)
        XCTAssertEqual(try GroupBook(vault: vault).draft(for: id), "", "no draft reaches the store")
    }

    /// Builds up to 15 saved drafts in the store; the first launch of this build erases them.
    func testDraftSavedByAnOlderBuildIsErasedAtLaunch() throws {
        let vault = makeVault()
        try addGroup(vault)
        let book = GroupBook(vault: vault)
        let id = try XCTUnwrap(try book.groups().first?.id)
        try book.setDraft("left by build 15", for: id)
        try book.setDraft("typed before a group", for: nil)

        let compose = ComposeModel(groups: GroupModel(vault: vault))
        compose.syncGroup()

        XCTAssertEqual(compose.text, "")
        XCTAssertEqual(try book.draft(for: id), "")
        XCTAssertEqual(try book.draft(for: nil), "")
    }

    func testDraftIsKeptWhenSwitchingGroups() throws {
        let vault = makeVault()
        try addGroup(vault)
        try addGroup(vault)
        let model = GroupModel(vault: vault)
        let compose = ComposeModel(groups: model)
        compose.syncGroup()
        compose.text = "meet at the old barn"

        model.setActive(try XCTUnwrap(model.groups.last))
        compose.syncGroup()
        XCTAssertEqual(compose.text, "")
        model.setActive(try XCTUnwrap(model.groups.first))
        compose.syncGroup()
        XCTAssertEqual(compose.text, "meet at the old barn")
    }

    func testDraftIsPerGroupAndNotInTheStoreInPlaintext() throws {
        let vault = makeVault()
        try addGroup(vault)
        let model = ComposeModel(groups: GroupModel(vault: vault))
        model.syncGroup()
        model.text = "marker plaintext zebra"
        model.flush()
        let file = try Data(contentsOf: vault.storeURL)
        XCTAssertNil(file.range(of: Data("zebra".utf8)))
        XCTAssertEqual(try GroupBook(vault: vault).draft(for: nil), "")
    }

    func testTextTypedBeforeAnyGroupMovesToTheFirstGroup() throws {
        let vault = makeVault()
        let groups = GroupModel(vault: vault)
        let model = ComposeModel(groups: groups)
        model.syncGroup()
        model.text = "meet at the church"
        model.flush()

        try addGroup(vault)
        groups.reload()
        model.syncGroup()
        XCTAssertEqual(model.text, "meet at the church")
        XCTAssertEqual(groups.draft(for: groups.groups.first?.id), "meet at the church")
        XCTAssertEqual(groups.draft(for: nil), "")
    }

    func testRemovingTheActiveGroupDoesNotWriteItsDraftBack() throws {
        let vault = makeVault()
        try addGroup(vault)
        try addGroup(vault)
        let model = GroupModel(vault: vault)
        let compose = ComposeModel(groups: model)
        compose.syncGroup()
        let removed = try XCTUnwrap(model.activeGroup)
        compose.text = "meet at the old barn"
        compose.flush()

        XCTAssertTrue(model.remove(removed))
        compose.syncGroup()

        XCTAssertEqual(compose.text, "")
        XCTAssertEqual(model.draft(for: removed.id), "", "the removed group's draft stays erased")
    }

    func testSwitchingGroupsClearsTheRoom() throws {
        let vault = makeVault()
        try addGroup(vault)
        try addGroup(vault)
        let model = GroupModel(vault: vault)
        let compose = ComposeModel(groups: model)
        compose.syncGroup()
        compose.room = "north"

        model.setActive(try XCTUnwrap(model.groups.last))
        compose.syncGroup()

        XCTAssertEqual(compose.room, "")
    }

    func testAddingAGroupKeepsDrafts() throws {
        let vault = makeVault()
        try addGroup(vault)
        let book = GroupBook(vault: vault)
        let id = try XCTUnwrap(try book.groups().first?.id)
        try book.setDraft("keep me", for: id)
        try addGroup(vault)
        XCTAssertEqual(try book.draft(for: id), "keep me")
    }

    func testPrepareWordsMatchesCountAndOpensWithGroupKeys() throws {
        let vault = makeVault()
        try addGroup(vault)
        let groups = GroupModel(vault: vault)
        let model = ComposeModel(groups: groups)
        model.syncGroup()
        model.text = "doctor needed at the smith house now"
        XCTAssertTrue(model.prepareWords())
        XCTAssertEqual(model.words.count, model.count)

        let keys = try XCTUnwrap(try groups.keys(for: XCTUnwrap(groups.groups.first)))
        let opened = try XCTUnwrap(Frame.open(try WordCodec.decode(model.words), tagBits: 64, trying: [keys]))
        XCTAssertEqual(try TextCodec.decode(opened.body), "doctor needed at the smith house now")
    }

    func testNoGroupOrEmptyTextGivesAMessageNotWords() throws {
        let model = ComposeModel(groups: GroupModel(vault: makeVault()))
        model.syncGroup()
        model.text = "hello"
        XCTAssertFalse(model.prepareWords())
        XCTAssertNotNil(model.problem)
        XCTAssertTrue(model.words.isEmpty)
    }

    /// Voice typing writes the text it heard back into the box after Send empties it. That echo is
    /// dropped, and the emptied box is what gets saved as the draft.
    func testSentTextWrittenBackByVoiceTypingIsDropped() async throws {
        let vault = makeVault()
        try addGroup(vault)
        let groups = GroupModel(vault: vault)
        let model = ComposeModel(groups: groups)
        model.syncGroup()
        model.text = "meet at the bridge"
        model.flush()
        model.sent()
        XCTAssertEqual(model.text, "")

        model.text = "meet at the bridge"  // dictation's write-back
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.count, 0)
        model.text = "meet at the bridge "  // with the space dictation adds
        XCTAssertEqual(model.text, "")

        // Something new is typed as usual.
        model.text = "meet at the gate"
        XCTAssertEqual(model.text, "meet at the gate")
        model.text = ""
        try await Task.sleep(for: .milliseconds(600))  // past the draft autosave
        XCTAssertEqual(ComposeModel(groups: GroupModel(vault: vault)).draftAfterSync, "")
    }

    func testSentEchoOnlyMatchesTheSameTextSoonAfter() {
        var echo = SentEcho()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(echo.isEcho("", now: start), "nothing sent yet")
        echo.sent("hello porch", now: start)
        XCTAssertTrue(echo.isEcho("hello porch", now: start.addingTimeInterval(1)))
        XCTAssertTrue(echo.isEcho(" hello porch ", now: start.addingTimeInterval(1)))
        XCTAssertFalse(echo.isEcho("hello", now: start.addingTimeInterval(1)))
        XCTAssertFalse(echo.isEcho("", now: start.addingTimeInterval(1)))
        XCTAssertFalse(echo.isEcho("hello porch", now: start.addingTimeInterval(SentEcho.window + 1)), "sending it again later is fine")
    }
}

private extension ComposeModel {
    /// The draft a fresh model loads for the first group.
    var draftAfterSync: String { syncGroup(); return text }
}
