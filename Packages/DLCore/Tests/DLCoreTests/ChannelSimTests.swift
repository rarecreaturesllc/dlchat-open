import XCTest
@testable import DLCore

final class ChannelSimTests: XCTestCase {
    private let rate = 8000.0

    private func tone(_ hz: Double, seconds: Double = 1, amplitude: Float = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func rms(_ x: ArraySlice<Float>) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot()
    }

    func testCleanProfileLeavesSignalUntouched() {
        let x = tone(1000)
        XCTAssertEqual(ChannelSim(profile: .clean()).apply(x), x)
    }

    func testSameSeedSameOutputDifferentSeedDiffers() {
        let x = tone(1000)
        let a = ChannelSim(profile: .handheld(seed: 7)).apply(x)
        let b = ChannelSim(profile: .handheld(seed: 7)).apply(x)
        let c = ChannelSim(profile: .handheld(seed: 8)).apply(x)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testBandpassPassesInBandAndRejectsOutOfBand() {
        let sim = ChannelSim(profile: Profile(bandpass: 300...3000))
        let inBand = sim.apply(tone(1000)).dropFirst(2000)
        let low = sim.apply(tone(50)).dropFirst(2000)
        let high = sim.apply(tone(3900)).dropFirst(2000)
        let reference = rms(tone(1000).dropFirst(2000))
        XCTAssertEqual(rms(inBand) / reference, 1, accuracy: 0.15)
        XCTAssertLessThan(rms(low) / reference, 0.05)
        XCTAssertLessThan(rms(high) / reference, 0.15)
    }

    func testClippingLimitsPeaksAndFlattensTops() {
        let out = ChannelSim(profile: Profile(clipGain: 4)).apply(tone(200, amplitude: 0.5))
        XCTAssertLessThanOrEqual(out.max()!, 1)
        XCTAssertGreaterThanOrEqual(out.min()!, -1)
        XCTAssertGreaterThan(out.filter { abs($0) == 1 }.count, 1000)
    }

    func testNoiseHitsRequestedSNR() {
        let x = tone(1000)
        for snr in [6.0, 12.0, 20.0] {
            let out = ChannelSim(profile: Profile(seed: 3, snrDB: snr)).apply(x)
            let noise = zip(out, x).map { $0 - $1 }
            let measured = 20 * log10(rms(x[...]) / rms(noise[...]))
            XCTAssertEqual(measured, snr, accuracy: 0.1)
        }
    }

    func testDriftShortensOrStretchesByTheRatio() {
        let x = tone(1000, seconds: 10)
        let fast = ChannelSim(profile: Profile(driftPPM: 10_000)).apply(x)
        let slow = ChannelSim(profile: Profile(driftPPM: -10_000)).apply(x)
        XCTAssertEqual(Double(fast.count), Double(x.count) / 1.01, accuracy: 2)
        XCTAssertEqual(Double(slow.count), Double(x.count) / 0.99, accuracy: 2)
    }

    func testChopSilencesTheRequestedAmount() {
        let x = tone(1000, seconds: 5)
        let out = ChannelSim(profile: Profile(seed: 5, chopCount: 1, chopSeconds: 0.25)).apply(x)
        let silent = out.filter { $0 == 0 }.count
        XCTAssertGreaterThanOrEqual(silent, Int(0.25 * rate))
        XCTAssertLessThan(silent, Int(0.25 * rate) + 100)
    }

    private typealias Profile = ChannelSim.Profile
}
