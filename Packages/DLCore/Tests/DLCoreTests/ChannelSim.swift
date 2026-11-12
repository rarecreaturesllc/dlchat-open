import Foundation
@testable import DLCore

/// A seeded model of a voice radio channel, used to measure the modem. It is
/// evidence about the modem, not about real radios. The same profile and the
/// same input always give the same output.
public struct ChannelSim {
    public struct Profile: Equatable {
        public var sampleRate: Double
        public var seed: UInt64
        /// Receiver clock fast (+) or slow (-) against the sender, in parts per million.
        public var driftPPM: Double
        /// Gain applied before the hard limit; 1 leaves the signal untouched below full scale.
        public var clipGain: Float
        /// Voice-radio passband in Hz. Nil disables the filter.
        public var bandpass: ClosedRange<Double>?
        /// Noise power below the filtered signal, in dB. Nil adds no noise.
        public var snrDB: Double?
        /// Squelch chops: number of dropouts and the length of each in seconds.
        public var chopCount: Int
        public var chopSeconds: Double

        public init(
            sampleRate: Double = 8000,
            seed: UInt64 = 1,
            driftPPM: Double = 0,
            clipGain: Float = 1,
            bandpass: ClosedRange<Double>? = nil,
            snrDB: Double? = nil,
            chopCount: Int = 0,
            chopSeconds: Double = 0
        ) {
            self.sampleRate = sampleRate
            self.seed = seed
            self.driftPPM = driftPPM
            self.clipGain = clipGain
            self.bandpass = bandpass
            self.snrDB = snrDB
            self.chopCount = chopCount
            self.chopSeconds = chopSeconds
        }

        /// No impairment at all.
        public static func clean(seed: UInt64 = 1) -> Profile { Profile(seed: seed) }

        /// A handheld FM radio: 300 to 3000 Hz passband, mic overdrive, 1% drift, light noise.
        public static func handheld(seed: UInt64, snrDB: Double = 12) -> Profile {
            Profile(seed: seed, driftPPM: 10_000, clipGain: 3, bandpass: 300...3000, snrDB: snrDB)
        }
    }

    public let profile: Profile

    public init(profile: Profile) {
        self.profile = profile
    }

    /// Order: clock drift, mic clipping, radio passband, noise, squelch chops.
    public func apply(_ input: [Float]) -> [Float] {
        var rng = SplitMix64(seed: profile.seed)
        var samples = drift(input)
        clip(&samples)
        if let band = profile.bandpass { samples = filter(samples, band: band) }
        if let snr = profile.snrDB { addNoise(&samples, snrDB: snr, rng: &rng) }
        chop(&samples, rng: &rng)
        return samples
    }

    // MARK: Stages

    /// Resamples as if the receiver's clock ran `driftPPM` fast; linear interpolation.
    private func drift(_ x: [Float]) -> [Float] {
        guard profile.driftPPM != 0, x.count > 1 else { return x }
        let step = 1 + profile.driftPPM * 1e-6
        let count = Int(Double(x.count - 1) / step) + 1
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * step
            let i0 = min(Int(pos), x.count - 2)
            let frac = Float(pos - Double(i0))
            out[i] = x[i0] * (1 - frac) + x[i0 + 1] * frac
        }
        return out
    }

    private func clip(_ x: inout [Float]) {
        guard profile.clipGain != 1 else { return }
        for i in x.indices {
            x[i] = max(-1, min(1, x[i] * profile.clipGain))
        }
    }

    /// High-pass then low-pass, two cascaded biquads each (4th order).
    private func filter(_ x: [Float], band: ClosedRange<Double>) -> [Float] {
        let fs = profile.sampleRate
        let stages = [
            Biquad.highPass(cutoff: band.lowerBound, sampleRate: fs),
            Biquad.highPass(cutoff: band.lowerBound, sampleRate: fs),
            Biquad.lowPass(cutoff: min(band.upperBound, fs * 0.45), sampleRate: fs),
            Biquad.lowPass(cutoff: min(band.upperBound, fs * 0.45), sampleRate: fs),
        ]
        var y = x
        for var stage in stages {
            for i in y.indices { y[i] = stage.process(y[i]) }
        }
        return y
    }

    /// Gaussian noise through the same passband, scaled so the RMS ratio is exact.
    private func addNoise(_ x: inout [Float], snrDB: Double, rng: inout SplitMix64) {
        let signal = rms(x)
        guard signal > 0 else { return }
        var noise = (0..<x.count).map { _ in Float(rng.gaussian()) }
        if let band = profile.bandpass { noise = filter(noise, band: band) }
        let noiseRMS = rms(noise)
        guard noiseRMS > 0 else { return }
        let scale = Float(Double(signal) / pow(10, snrDB / 20)) / noiseRMS
        for i in x.indices { x[i] += noise[i] * scale }
    }

    /// Silences `chopCount` windows at seeded positions, as a squelch closing would.
    private func chop(_ x: inout [Float], rng: inout SplitMix64) {
        let length = Int(profile.chopSeconds * profile.sampleRate)
        guard profile.chopCount > 0, length > 0, x.count > length else { return }
        for _ in 0..<profile.chopCount {
            let start = Int(rng.next() % UInt64(x.count - length))
            for i in start..<(start + length) { x[i] = 0 }
        }
    }

    private func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var sum: Double = 0
        for v in x { sum += Double(v) * Double(v) }
        return Float((sum / Double(x.count)).squareRoot())
    }
}

/// Small deterministic generator so results do not depend on the platform.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in (0, 1].
    mutating func unit() -> Double {
        Double(next() >> 11 &+ 1) / Double(1 << 53)
    }

    /// Standard normal by Box-Muller.
    mutating func gaussian() -> Double {
        let u1 = unit()
        let u2 = unit()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// Direct form I biquad from the RBJ cookbook, Butterworth Q.
private struct Biquad {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    static func lowPass(cutoff: Double, sampleRate: Double) -> Biquad {
        make(cutoff: cutoff, sampleRate: sampleRate, high: false)
    }

    static func highPass(cutoff: Double, sampleRate: Double) -> Biquad {
        make(cutoff: cutoff, sampleRate: sampleRate, high: true)
    }

    private static func make(cutoff: Double, sampleRate: Double, high: Bool) -> Biquad {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * 0.7071)
        let c = cos(w0)
        let a0 = 1 + alpha
        let b0 = high ? (1 + c) / 2 : (1 - c) / 2
        let b1 = high ? -(1 + c) : 1 - c
        return Biquad(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b0 / a0),
            a1: Float(-2 * c / a0), a2: Float((1 - alpha) / a0)
        )
    }

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}
