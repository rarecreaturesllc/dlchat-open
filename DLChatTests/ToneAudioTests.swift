import AVFoundation
import DLCore
import XCTest
@testable import DLChat

@MainActor
final class ToneAudioTests: XCTestCase {
    private var cleanup: [() -> Void] = []

    override func tearDown() {
        cleanup.forEach { $0() }
        cleanup = []
    }

    private func makeModels() throws -> (DecodeModel, ComposeModel) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "dlchat-tone-\(UUID().uuidString)", directoryHint: .isDirectory)
        let vault = Vault(service: "app.dlchat.tests.\(UUID().uuidString)", directory: dir)
        cleanup.append { try? vault.wipe() }
        _ = try GroupBook(vault: vault).add(name: "Maple", prepared: PreparedGroup(phrase: try Phrase.generate(words: 10)))
        let groups = GroupModel(vault: vault)
        let decode = DecodeModel(groups: groups)
        decode.refreshKeys()
        let compose = ComposeModel(groups: groups)
        compose.syncGroup()
        return (decode, compose)
    }

    // MARK: Route warnings

    func testNoWarningOnTheBuiltInSpeakerAndMicrophone() {
        XCTAssertTrue(AudioRoute.playbackWarnings(outputs: [.builtInSpeaker]).isEmpty)
        XCTAssertTrue(AudioRoute.listenWarnings(inputs: [.builtInMic]).isEmpty)
        XCTAssertTrue(AudioRoute.playbackWarnings(outputs: []).isEmpty)
    }

    func testWarnsWhenSoundWouldNotReachTheRadio() {
        for port in [AVAudioSession.Port.bluetoothA2DP, .headphones, .airPlay, .carAudio, .usbAudio, .builtInReceiver] {
            XCTAssertEqual(AudioRoute.playbackWarnings(outputs: [port]).count, 1, "\(port)")
        }
        XCTAssertEqual(AudioRoute.playbackWarnings(outputs: [.builtInSpeaker, .bluetoothHFP]).count, 1)
        XCTAssertTrue(AudioRoute.playbackWarnings(outputs: [.bluetoothA2DP])[0].contains("Bluetooth"))
    }

    func testWarnsWhenTheMicrophoneIsNotThePhonesOwn() {
        XCTAssertEqual(AudioRoute.listenWarnings(inputs: [.bluetoothHFP]).count, 1)
        XCTAssertEqual(AudioRoute.listenWarnings(inputs: [.headsetMic]).count, 1)
    }

    // MARK: Resampling

    private func throughHardwareRate(_ samples: [Float], rate: Double, chunk: Int) throws -> [Float] {
        let up = try XCTUnwrap(AudioResampler(from: try XCTUnwrap(AudioResampler.buffer([0], rate: Modem.sampleRate)).format, rate: rate))
        let loud = try XCTUnwrap(up.convert(try XCTUnwrap(AudioResampler.buffer(samples, rate: Modem.sampleRate))))
        XCTAssertFalse(loud.isEmpty)
        let hardware = try XCTUnwrap(AudioResampler.buffer(loud, rate: rate))
        let down = try XCTUnwrap(AudioResampler(from: hardware.format))
        var out = [Float]()
        var position = 0
        while position < loud.count {
            let part = Array(loud[position..<min(position + chunk, loud.count)])
            out += down.convert(try XCTUnwrap(AudioResampler.buffer(part, rate: rate)))
            position += chunk
        }
        return out
    }

    func testBurstSurvivesTheHardwareRateAndChunkedCapture() throws {
        let payload = (0..<40).map { UInt8(($0 * 37 + 11) & 0xFF) }
        let burst = Modem.encode(payload) + [Float](repeating: 0, count: 4_000)
        for rate in [48_000.0, 44_100.0] {
            let heard = try throughHardwareRate(burst, rate: rate, chunk: 4096)
            XCTAssertEqual(Double(heard.count), Double(burst.count), accuracy: 400, "length at \(rate)")
            let frames = ModemDecoder().feed(heard)
            XCTAssertEqual(frames.first.map { [UInt8]($0) }, payload, "decoded at \(rate)")
        }
    }

    // MARK: Models

    func testSealedMessageGoesThroughSamplesAndOpensInTheDecodeModel() async throws {
        let (decode, compose) = try makeModels()
        compose.text = "need water at north gate"
        XCTAssertTrue(compose.prepareTone())
        XCTAssertFalse(compose.tone.isEmpty)
        XCTAssertLessThan(TonePlayer.duration(of: compose.tone), 10)
        let bursts = ModemDecoder().feed(compose.tone + [Float](repeating: 0, count: 4_000))
        XCTAssertEqual(bursts.count, 1)
        XCTAssertTrue(decode.readHeard(bursts[0]))
        guard case .message(let message, _) = decode.outcome else { return XCTFail("not decoded") }
        XCTAssertEqual(message.text, "need water at north gate")
    }

    func testForeignBurstIsRefusedAndLeavesTheScreenAlone() throws {
        let (decode, compose) = try makeModels()
        let stranger = Keys(phrase: try Phrase.generate(words: 10))
        let samples = try Composer.composeTone(text: "not for you", keys: stranger)
        let burst = try XCTUnwrap(ModemDecoder().feed(samples + [Float](repeating: 0, count: 4_000)).first)
        XCTAssertFalse(decode.readHeard(burst))
        XCTAssertEqual(decode.outcome, .typing)
        XCTAssertFalse(decode.readHeard(Data([9, 9, 9])))
        compose.text = ""
        XCTAssertFalse(compose.prepareTone())
        XCTAssertNotNil(compose.problem)
    }

    func testAMessageTooLongForOneBurstIsRefusedNotACrash() throws {
        let (_, compose) = try makeModels()
        compose.text = String(repeating: "zebra quartz ", count: 160)
        XCTAssertFalse(compose.prepareTone())
        XCTAssertEqual(compose.problem, "Too long for sound. Shorten the message to send it as sound.")
        XCTAssertTrue(compose.tone.isEmpty)
    }

    func testWipeForgetsThePreparedTone() throws {
        let (_, compose) = try makeModels()
        compose.text = "hello"
        XCTAssertTrue(compose.prepareTone())
        compose.discard()
        XCTAssertTrue(compose.tone.isEmpty)
    }

    func testPlayerWithNothingToPlayFailsPlainly() {
        let player = TonePlayer()
        player.play([])
        XCTAssertEqual(player.state, .failed("There is nothing to play yet."))
    }

    // MARK: Decrypt Sound level and Mute

    /// Decrypt Sound starts a quarter quieter than Send; Mute silences it; levels stay within 0...1.
    func testDecryptSoundIsQuieterAndMuteSilencesIt() {
        XCTAssertEqual(ReceiveView.decryptSoundVolume, 0.75, accuracy: 0.001)
        XCTAssertEqual(TonePlayer.outputVolume(ReceiveView.decryptSoundVolume, muted: false), 0.75, accuracy: 0.001)
        XCTAssertEqual(TonePlayer.outputVolume(ReceiveView.decryptSoundVolume, muted: true), 0)
        XCTAssertEqual(TonePlayer.outputVolume(1, muted: false), 1, "Send keeps full level for radios")
        XCTAssertEqual(TonePlayer.outputVolume(3, muted: false), 1)
        XCTAssertEqual(TonePlayer.outputVolume(-1, muted: false), 0)
    }

    /// Mute can be set before playing and stays set.
    func testMuteCanBeSetBeforePlaying() {
        let player = TonePlayer()
        player.muted = true
        player.play([], volume: ReceiveView.decryptSoundVolume)
        XCTAssertTrue(player.muted)
    }

    /// The tone player uses the `.playback` audio session, which plays with the iPhone's silent switch on.
    func testTonesPlayWithTheSilentSwitchOn() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "DLChat/AudioIO/ToneAudio.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(text.contains("session.setCategory(.playback"), "TonePlayer must use the .playback category")
    }
}
