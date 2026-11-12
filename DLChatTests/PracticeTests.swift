import DLCore
import XCTest
@testable import DLChat

@MainActor
final class PracticeModelTests: XCTestCase {
    private func ready() async -> PracticeModel {
        let model = PracticeModel()
        await model.begin()
        return model
    }

    private func waitForDone(_ model: PracticeModel) async {
        for _ in 0..<200 where model.step != .done { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testBeginMakesAMessageToSay() async {
        let model = await ready()
        XCTAssertEqual(model.step, .say)
        XCTAssertGreaterThanOrEqual(model.words.count, Receiver.minimumWords)
        XCTAssertNil(model.decoded)
    }

    func testTypingTheWordsBackDecodesTheMessageWithoutRadio() async {
        let model = await ready()
        model.startListening()
        XCTAssertEqual(model.step, .listen)
        for word in model.words { model.add(word) }
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.decoded, PracticeModel.message)
        XCTAssertNil(model.repairNote)
    }

    func testAMissedWordMarkedWithQuestionMarkIsFilledIn() async {
        let model = await ready()
        model.startListening()
        for (i, word) in model.words.enumerated() { i == 3 ? model.addMissing() : model.add(word) }
        await waitForDone(model)
        XCTAssertEqual(model.decoded, PracticeModel.message)
        XCTAssertNotNil(model.repairNote)
    }

    func testWrongWordsDoNotFinish() async {
        let model = await ready()
        model.startListening()
        for word in model.words.reversed() { model.add(word) }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(model.decoded)
        XCTAssertEqual(model.step, .listen)
    }

    func testPastedWordsAreIngestedAndUndoWorks() async {
        let model = await ready()
        model.startListening()
        model.typed = model.words.joined(separator: " ") + " "
        model.ingestTyped()
        XCTAssertEqual(model.decoded, PracticeModel.message)
        model.undo()
        XCTAssertNil(model.decoded)
    }

    func testEachRunUsesItsOwnThrowawayPhrase() async {
        let a = await ready()
        let b = await ready()
        XCTAssertNotEqual(a.words, b.words)
    }

    func testRestartMakesANewRun() async {
        let model = await ready()
        model.startListening()
        for word in model.words { model.add(word) }
        let first = model.words
        await model.restart()
        XCTAssertEqual(model.step, .say)
        XCTAssertNil(model.decoded)
        XCTAssertTrue(model.entered.isEmpty)
        XCTAssertNotEqual(model.words, first)
    }
}

final class RadioNoticeTests: XCTestCase {
    private func defaults() -> (UserDefaults, () -> Void) {
        let suite = "dlchat.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (d, { d.removePersistentDomain(forName: suite) })
    }

    func testNotSeenUntilMarkedThenStaysSeen() {
        let (d, clean) = defaults()
        defer { clean() }
        XCTAssertFalse(RadioNotice.seen(d))
        RadioNotice.markSeen(d)
        XCTAssertTrue(RadioNotice.seen(d))
        XCTAssertTrue(RadioNotice.seen(d))
    }

    func testResetShowsItAgain() {
        let (d, clean) = defaults()
        defer { clean() }
        RadioNotice.markSeen(d)
        RadioNotice.reset(d)
        XCTAssertFalse(RadioNotice.seen(d))
    }

    func testTextWarnsAndMakesNoLegalClaim() {
        let text = RadioNotice.paragraphs.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("may be prohibited"))
        XCTAssertTrue(text.contains("not legal advice"))
        XCTAssertTrue(text.contains("not approved or certified"))
        XCTAssertFalse(text.contains("legal to use"))
        XCTAssertFalse(text.contains("fcc approved"))
    }
}
