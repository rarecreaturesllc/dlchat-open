import XCTest
@testable import DLCore

final class ModemTests: XCTestCase {
    private func payload(_ rng: inout SplitMix64, count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    }

    private func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Modem.sampleRate))
    }

    /// One seeded burst through the handheld channel at 1% drift (either direction).
    private func transmit(_ seed: UInt64, snrDB: Double) -> (sent: [UInt8], heard: [Data]) {
        var rng = SplitMix64(seed: seed)
        let sent = payload(&rng, count: 24 + Int(rng.next() % 25))
        let lead = Double(rng.next() % 40) / 100
        let air = silence(lead) + Modem.encode(sent) + silence(0.3)
        var profile = ChannelSim.Profile.handheld(seed: seed, snrDB: snrDB)
        profile.driftPPM = seed % 2 == 0 ? 10_000 : -10_000
        let heard = ModemDecoder().feed(ChannelSim(profile: profile).apply(air))
        return (sent, heard)
    }

    private func successRate(frames: Int, snrDB: Double) -> Int {
        (0..<frames).filter { i in
            let r = transmit(UInt64(i), snrDB: snrDB)
            return r.heard == [Data(r.sent)]
        }.count
    }

    // MARK: Reed-Solomon

    func testReedSolomonRoundTripAndRepairsUpToHalfTheParity() {
        var rng = SplitMix64(seed: 5)
        for trial in 0..<50 {
            let data = payload(&rng, count: 1 + trial)
            var word = ReedSolomon.encode(data, parity: 16)
            XCTAssertEqual(ReedSolomon.decode(word, parity: 16), data)
            var hit = Set<Int>()
            while hit.count < 8 { hit.insert(Int(rng.next() % UInt64(word.count))) }
            for i in hit { word[i] ^= UInt8(1 + rng.next() % 255) }
            XCTAssertEqual(ReedSolomon.decode(word, parity: 16), data, "trial \(trial)")
        }
    }

    func testReedSolomonRejectsTooManyErrors() {
        var rng = SplitMix64(seed: 6)
        var repaired = 0
        for _ in 0..<200 {
            let data = payload(&rng, count: 30)
            var word = ReedSolomon.encode(data, parity: 16)
            var hit = Set<Int>()
            while hit.count < 12 { hit.insert(Int(rng.next() % UInt64(word.count))) }
            for i in hit { word[i] ^= UInt8(1 + rng.next() % 255) }
            if ReedSolomon.decode(word, parity: 16) != nil { repaired += 1 }
        }
        XCTAssertEqual(repaired, 0)
    }

    // MARK: Modem

    func testCleanBurstRoundTripsAtEveryLength() {
        var rng = SplitMix64(seed: 9)
        for length in [1, 2, 25, 40, 64, Modem.maxPayload] {
            let sent = payload(&rng, count: length)
            let heard = ModemDecoder().feed(silence(0.2) + Modem.encode(sent) + silence(0.2))
            XCTAssertEqual(heard, [Data(sent)], "length \(length)")
        }
    }

    func testBurstTakesAboutTenSecondsForA64ByteFrame() {
        let seconds = Double(Modem.encode([UInt8](repeating: 7, count: 64)).count) / Modem.sampleRate
        XCTAssertLessThan(seconds, 10)
    }

    func testChunkedFeedGivesTheSameFrameAndTwoBurstsInOneStream() {
        var rng = SplitMix64(seed: 11)
        let a = payload(&rng, count: 30), b = payload(&rng, count: 36)
        let stream = silence(0.3) + Modem.encode(a) + silence(0.5) + Modem.encode(b) + silence(0.2)
        let decoder = ModemDecoder()
        var heard: [Data] = []
        var index = 0
        while index < stream.count {
            let end = min(stream.count, index + 4096)
            heard += decoder.feed(Array(stream[index..<end]))
            index = end
        }
        XCTAssertEqual(heard, [Data(a), Data(b)])
    }

    func testTwoBurstsFedInOnePieceBothComeOutInOrder() {
        var rng = SplitMix64(seed: 21)
        // As a sound file gives them: everything in one call. The second is longer and louder in the scan.
        let a = payload(&rng, count: 24), b = payload(&rng, count: 60)
        let stream = silence(0.3) + Modem.encode(a).map { $0 * 0.4 } + silence(0.5) + Modem.encode(b) + silence(0.2)
        XCTAssertEqual(ModemDecoder().feed(stream), [Data(a), Data(b)])
    }

    func testNoiseAndSilenceGiveNoFrames() {
        var rng = SplitMix64(seed: 12)
        let noise = (0..<80_000).map { _ in Float(rng.gaussian()) * 0.3 }
        XCTAssertEqual(ModemDecoder().feed(noise), [])
        XCTAssertEqual(ModemDecoder().feed(silence(5)), [])
    }

    func testDestroyedBodyGivesNothingRatherThanWrongData() {
        var rng = SplitMix64(seed: 13)
        let sent = payload(&rng, count: 30)
        var air = Modem.encode(sent)
        // Silence a third of the body: far more than 8 bytes.
        let start = air.count / 2
        for i in start..<(start + air.count / 3) { air[i] = 0 }
        XCTAssertEqual(ModemDecoder().feed(air + silence(0.2)), [])
    }

    func testSurvivesAShortSquelchChop() {
        var rng = SplitMix64(seed: 14)
        let sent = payload(&rng, count: 40)
        var air = silence(0.2) + Modem.encode(sent) + silence(0.2)
        let start = air.count / 2
        for i in start..<(start + 2 * Modem.symbolSamples) { air[i] = 0 }  // 2 symbols = 1 byte
        XCTAssertEqual(ModemDecoder().feed(air), [Data(sent)])
    }

    func testFrameConvenienceCarriesARealFrameLength() throws {
        var rng = SplitMix64(seed: 15)
        var bits = Bits()
        for _ in 0..<20 { bits.append(rng.next() & 0x3FF, width: 10) }  // 200 bits
        let frame = Frame(bits: bits)
        let heard = ModemDecoder().feed(silence(0.2) + Modem.encode(frame) + silence(0.2))
        XCTAssertEqual(heard.count, 1)
        XCTAssertEqual(Modem.frame(from: heard[0]), frame)
    }

    // MARK: Channel acceptance (simulated only)

    func test500SeededFramesDecodeAtTwelveDBWithClippingAndOnePercentDrift() {
        let ok = successRate(frames: 500, snrDB: 12)
        print("MODEM-NUMBERS 12 dB, clipGain 3, 300-3000 Hz, drift +-1%: \(ok)/500 decoded")
        XCTAssertGreaterThanOrEqual(ok, 475, "needs at least 95%")
    }

    func testSuccessRateAcrossSNR() {
        for snr in [-6.0, -3, 0, 3, 9] {
            print("MODEM-NUMBERS \(Int(snr)) dB: \(successRate(frames: 100, snrDB: snr))/100 decoded")
        }
    }
}
