import CryptoKit
import XCTest
@testable import DLCore

/// Everything that reads bytes or text from someone else (a radio, a relay, a QR code, a pasted link,
/// a sound) is fed random and mangled input. Nothing here checks an answer: a Swift trap (index out of
/// range, overflow, a failed precondition) ends the test run, and that is the failure.
///
/// The inputs come from a fixed seed, so a crash happens again on the next run. To hunt further, set
/// `DLCHAT_FUZZ_SEED` to another number and `DLCHAT_FUZZ_ROUNDS` to a larger one.
final class FuzzTests: XCTestCase {
    /// SplitMix64: small, fast and the same on every machine.
    private struct Source: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private var source = Source(state: 1)
    private var rounds = 2000

    override func setUp() {
        let environment = ProcessInfo.processInfo.environment
        source = Source(state: environment["DLCHAT_FUZZ_SEED"].flatMap { UInt64($0) } ?? 0xD1C4A7)
        rounds = environment["DLCHAT_FUZZ_ROUNDS"].flatMap { Int($0) } ?? 2000
    }

    // MARK: Inputs

    private func randomBytes(upTo limit: Int) -> Data {
        let count = Int.random(in: 0...limit, using: &source)
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &source) })
    }

    /// Bytes that look like protobuf: mostly small field tags, lengths near the edges, and varints that
    /// run long, since those are what a length or index bug trips on.
    private func protobufish(upTo limit: Int) -> Data {
        var out = Data()
        while out.count < limit, Int.random(in: 0..<12, using: &source) != 0 {
            let field = UInt8.random(in: 1...15, using: &source)
            let wire = UInt8.random(in: 0...5, using: &source)
            out.append(field << 3 | wire)
            switch Int.random(in: 0..<5, using: &source) {
            case 0: out.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])
            case 1: out.append(UInt8.random(in: 0...255, using: &source))
            case 2:
                let length = UInt8.random(in: 0...40, using: &source)
                out.append(length)
                out.append(randomBytes(upTo: Int(length) + 2))
            case 3: out.append(contentsOf: [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01])
            default: out.append(randomBytes(upTo: 9))
            }
        }
        return out
    }

    /// A good input with a few bytes changed, cut short or grown, so the parser gets past its first checks.
    private func mangled(_ good: Data) -> Data {
        var bytes = [UInt8](good)
        for _ in 0..<Int.random(in: 1...4, using: &source) {
            switch Int.random(in: 0..<4, using: &source) {
            case 0 where !bytes.isEmpty:
                bytes[Int.random(in: 0..<bytes.count, using: &source)] = UInt8.random(in: 0...255, using: &source)
            case 1 where !bytes.isEmpty:
                bytes.removeLast(Int.random(in: 1...min(bytes.count, 64), using: &source))
            case 2:
                bytes.append(contentsOf: randomBytes(upTo: 32))
            default:
                if !bytes.isEmpty { bytes[Int.random(in: 0..<bytes.count, using: &source)] ^= 0x80 }
            }
        }
        return Data(bytes)
    }

    private func randomText(upTo limit: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_#:/?&=%+. \n\u{301}\u{1F600}")
        let count = Int.random(in: 0...limit, using: &source)
        return String((0..<count).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &source)] })
    }

    private func randomWords(upTo limit: Int) -> [String] {
        (0..<Int.random(in: 0...limit, using: &source)).map { _ in
            Int.random(in: 0..<20, using: &source) == 0
                ? randomText(upTo: 8) : WordList.word(at: Int.random(in: 0..<WordList.count, using: &source))
        }
    }

    private func keys() -> [Keys] {
        [Keys(masterData: Data(repeating: 1, count: 32)), Keys(masterData: Data(repeating: 2, count: 32), room: "porch")]
    }

    // MARK: Radio

    func testMeshtasticBytesFromARadioNeverTrap() {
        for round in 0..<rounds {
            let data = round % 2 == 0 ? protobufish(upTo: 300) : randomBytes(upTo: 300)
            _ = Meshtastic.Reader.fields(data)
            _ = Meshtastic.parse(data)
            _ = Meshtastic.packet(fromRadio: data)
            _ = Meshtastic.routingError(data)
            _ = Meshtastic.cleanText(data)
            _ = Meshtastic.channelInfo(data)
            _ = Meshtastic.presetName(currentLoRa: data)
            _ = Meshtastic.hopLimit(currentLoRa: data)
            _ = Meshtastic.setRegion(UInt64.random(in: 0...UInt64.max, using: &source), currentLoRa: data)
            _ = Meshtastic.locationOff(currentPosition: data)
            _ = Meshtastic.channelWithoutPosition(currentChannel: data)
            _ = Meshtastic.meshNode(fromNodeInfo: data)
        }
    }

    func testRadioMapListNeverTraps() {
        let good = Data(#"[{"num":1,"longName":"a","shortName":"b","latitude":397000000,"longitude":-1050000000}]"#.utf8)
        for round in 0..<rounds / 4 {
            _ = MeshMap.parseWorldwide(round % 2 == 0 ? mangled(good) : randomBytes(upTo: 200))
        }
    }

    // MARK: Words, QR, sound, nearby wire

    func testSealedMessagesInEveryCarrierNeverTrap() throws {
        let all = keys()
        let frame = try Frame.seal(body: WordCodec.pad(TextCodec.encode("meet at the bridge"), tagBits: 128),
                                   sentAt: Frame.epoch.addingTimeInterval(900), keys: all[0], tagBits: 128)
        let goodBytes = Data(frame.bits.bytes)
        let goodQR = QRTransport.payload(for: frame)
        for round in 0..<rounds {
            let data = round % 2 == 0 ? mangled(goodBytes) : randomBytes(upTo: 400)
            _ = Modem.frame(from: data)
            _ = Receiver.readTone(payload: data, trying: all)
            _ = NearbyWire.parse(data)
            _ = Receiver.readNearby(wire: data, trying: all)
            _ = ReadReceipt.open(wire: data, trying: all)
            let text = round % 2 == 0 ? String(decoding: mangled(Data(goodQR.utf8)), as: UTF8.self) : randomText(upTo: 300)
            _ = QRTransport.frame(from: text)
            _ = Receiver.readQR(payload: text, trying: all)
            _ = ChatCarry.parse(text)
            _ = try? Phrase.parse(text)
            let words = randomWords(upTo: 40)
            _ = try? WordCodec.decode(words)
            _ = Receiver.read(words: words, trying: all)
            _ = Receiver.gapCount(in: words)
            let bits = Bits(bytes: [UInt8](data), count: Int.random(in: 0...(data.count * 8), using: &source))
            _ = try? TextCodec.decode(bits)
            _ = Frame.open(Frame(bits: bits), tagBits: round % 2 == 0 ? 64 : 128, trying: all)
        }
    }

    func testErrorCorrectionNeverTraps() {
        // The picture invite's code: 64 parity bytes, any number of data bytes that fits one block.
        for _ in 0..<rounds / 4 {
            let count = Int.random(in: 65...255, using: &source)
            let codeword = (0..<count).map { _ in UInt8.random(in: 0...255, using: &source) }
            _ = ReedSolomon.decode(codeword, parity: 64)
        }
    }

    func testSoundDecoderNeverTrapsOnNoise() {
        // Noise, silence, clipping and odd values, in uneven pieces.
        let decoder = ModemDecoder()
        for round in 0..<40 {
            let count = Int.random(in: 0...6000, using: &source)
            let samples: [Float] = (0..<count).map { _ in
                switch round % 5 {
                case 0: return Float.random(in: -1...1, using: &source)
                case 1: return 0
                case 2: return Bool.random(using: &source) ? 1e9 : -1e9
                case 3: return Int.random(in: 0..<50, using: &source) == 0 ? .nan : Float.random(in: -1...1, using: &source)
                default: return Int.random(in: 0..<50, using: &source) == 0 ? .infinity : Float.random(in: -0.1...0.1, using: &source)
                }
            }
            _ = decoder.feed(samples)
        }
    }

    // MARK: Relays and Internet Messages

    func testRelayEventsNeverTrap() throws {
        let all = keys()
        let event = try Online.event(wire: Data(repeating: 7, count: 40), keys: all[0])
        for round in 0..<rounds / 4 {
            let content = round % 2 == 0 ? mangled(Data(event.content.utf8)) : randomBytes(upTo: 400)
            let changed = Online.Event(id: round % 3 == 0 ? randomText(upTo: 70) : event.id,
                                       pubkey: round % 5 == 0 ? randomText(upTo: 70) : event.pubkey,
                                       createdAt: Int.random(in: Int.min...Int.max, using: &source), kind: Online.kind,
                                       tags: [[randomText(upTo: 4)], [], ["p"], ["p", randomText(upTo: 70)]],
                                       content: String(decoding: content, as: UTF8.self),
                                       sig: round % 7 == 0 ? randomText(upTo: 140) : event.sig)
            _ = changed.isValid
            _ = Online.wire(from: changed, trying: all)
            _ = Direct.envelope(from: changed)
            _ = Online.Event(json: ["id": randomText(upTo: 8), "pubkey": 3, "created_at": randomText(upTo: 3), "tags": [[1]]])
        }
    }

    func testInternetMessagesBytesNeverTrap() throws {
        do { _ = try PQ.generate() } catch DirectError.needsNewerSystem { throw XCTSkip("needs macOS 26") }
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let pending = try PendingInvite.make(name: "Ana", route: .publicRelays, queue: nil, now: now)
        let (ben, hello) = try Direct.accept(pending.invite, myName: "Ben", myRoute: .publicRelays, myQueue: nil, now: now)
        let (ana, _) = try Direct.openHello(hello, pending: pending, now: now)
        let (_, envelope) = try Direct.seal(DirectMessage(text: "hello"), for: ana)
        let inner = try Direct.open(envelope.bytes, key: ana.wrapKey)
        let helloInner = try Direct.open(hello.bytes, key: pending.invite.wrapKey)
        let invite = pending.invite.encoded

        for round in 0..<rounds / 4 {
            // The invite, as bytes and as a link.
            let changedInvite = round % 2 == 0 ? mangled(invite) : randomBytes(upTo: 1400)
            _ = try? DirectInvite(encoded: changedInvite)
            _ = DirectInviteText(text: "dlchat://contact#" + changedInvite.base64URL)
            _ = DirectInviteText(text: randomText(upTo: 120))
            _ = DirectInvite(text: "dlchat://contact#" + randomText(upTo: 80))
            _ = DirectInviteLink(text: "dlchat://contact#" + randomBytes(upTo: 40).base64URL)

            // What sits inside the outer seal, sealed again so it reaches the ratchet and the hello reader.
            let changedInner = round % 2 == 0 ? mangled(inner) : Data([Direct.messageTag]) + randomBytes(upTo: 3000)
            if let sealed = try? Direct.seal(changedInner, key: ben.wrapKey) {
                _ = try? Direct.open(DirectEnvelope(bytes: sealed), from: ben)
            }
            let changedHello = round % 2 == 0 ? mangled(helloInner) : Data([Direct.helloV2Tag]) + randomBytes(upTo: 3000)
            if let sealed = try? Direct.seal(changedHello, key: pending.invite.wrapKey) {
                _ = try? Direct.openHello(DirectEnvelope(bytes: sealed), pending: pending, now: now)
            }
            // And raw bytes where an envelope should be.
            let raw = DirectEnvelope(bytes: round % 2 == 0 ? mangled(envelope.bytes) : randomBytes(upTo: 5000))
            _ = try? Direct.open(raw, from: ben)
            _ = try? Direct.openHello(raw, pending: pending, now: now)
            var reader = ByteReader(changedInner)
            _ = try? DirectRatchet.Header.decode(&reader)
            _ = try? DirectMessage(encoded: changedInner)
        }
    }
}
