import Accelerate
import Foundation

/// 16-MFSK tone modem for a voice radio (blueprint section 4). Mono samples at 8000 Hz.
///
/// Layout of one burst, one symbol = 256 samples = 31.25 baud, 4 bits per symbol, high nibble first:
/// lead-in tone for VOX, 12 preamble symbols, a header holding the payload length as Reed-Solomon
/// (1 data + 4 parity bytes), then the payload as Reed-Solomon (data + 16 parity bytes).
/// Tones are 700 Hz + 125 Hz * n, so they stay orthogonal over one symbol, and detection is
/// non-coherent (energy per tone), which survives clipping and level changes.
///
/// The decoder searches receiver clock drift of +-2% in 0.2% steps: a fast or slow clock stretches
/// both symbol time and tone pitch. Only a simulator has measured this (`ChannelSim`, in the tests).
public enum Modem {
    public static let sampleRate = 8000.0
    public static let maxPayload = 255 - bodyParity

    static let symbolSamples = 256
    static let toneCount = 16
    static let baseHz = 700.0
    static let spacingHz = 125.0
    static let leadInSymbols = 16
    static let leadInTone = 8
    static let preamble = [0, 5, 2, 7, 1, 6, 3, 4, 7, 0, 5, 2]
    static let headerParity = 4
    static let bodyParity = 16
    static let headerSymbols = 2 * (1 + headerParity)
    static let amplitude: Float = 0.9
    static let taperSamples = 16

    /// Seconds a burst carrying `count` payload bytes plays for, without making its samples.
    public static func duration(bytes count: Int) -> Double {
        Double((leadInSymbols + preamble.count + headerSymbols + 2 * (count + bodyParity)) * symbolSamples) / sampleRate
    }

    /// A burst carrying `payload` (1 to `maxPayload` bytes), ready to play.
    public static func encode(_ payload: [UInt8]) -> [Float] {
        precondition((1...maxPayload).contains(payload.count), "payload size out of range")
        var symbols = [Int](repeating: leadInTone, count: leadInSymbols) + preamble
        for byte in ReedSolomon.encode([UInt8(payload.count)], parity: headerParity)
            + ReedSolomon.encode(payload, parity: bodyParity)
        {
            symbols.append(Int(byte >> 4))
            symbols.append(Int(byte & 0x0F))
        }

        var out = [Float]()
        out.reserveCapacity(symbols.count * symbolSamples)
        for symbol in symbols {
            let omega = 2 * Double.pi * (baseHz + Double(symbol) * spacingHz) / sampleRate
            for n in 0..<symbolSamples {
                let edge = min(n, symbolSamples - 1 - n)
                let taper = edge >= taperSamples ? 1 : 0.5 - 0.5 * cos(Double.pi * Double(edge) / Double(taperSamples))
                out.append(amplitude * Float(taper * sin(omega * Double(n))))
            }
        }
        return out
    }

    /// A sealed frame as a burst; frames use the 128-bit tag on tones, as on QR.
    public static func encode(_ frame: Frame) -> [Float] {
        encode(frame.bits.bytes)
    }

    /// The frame a decoded burst carries. A frame is a whole number of 10-bit words, so the bit count
    /// follows from the byte count, as for QR.
    public static func frame(from payload: Data) -> Frame? {
        let bytes = [UInt8](payload)
        let bits = (bytes.count * 8 / WordList.bitsPerWord) * WordList.bitsPerWord
        guard bits > 0, (bits + 7) / 8 == bytes.count, bits >= QRTransport.tagBits + Frame.headerBits else {
            return nil
        }
        return Frame(bits: Bits(bytes: bytes, count: bits))
    }

    // MARK: Analysis shared with the decoder

    static let hop = 64
    static let gridStep = 0.002
    static let gridCenter = 10
    static let gridCount = 21
    static let maxBufferSamples = Int(20 * sampleRate)

    /// One tone detector per hypothesised clock scale.
    static let banks: [ToneBank] = (0..<gridCount).map {
        ToneBank(scale: 1 + Double($0 - gridCenter) * gridStep)
    }
}

/// Correlation tables for the 16 tones at one clock scale: the window is as long as a symbol heard by
/// a clock that is `scale` times too fast, and the tones sit `scale` times higher.
struct ToneBank {
    let length: Int
    let spacing: Double
    private let cosines: [Float]
    private let sines: [Float]

    init(scale: Double) {
        length = Int((Double(Modem.symbolSamples) / scale).rounded())
        spacing = Double(Modem.symbolSamples) / scale
        var c = [Float](), s = [Float]()
        c.reserveCapacity(Modem.toneCount * length)
        s.reserveCapacity(Modem.toneCount * length)
        for tone in 0..<Modem.toneCount {
            let omega = 2 * Double.pi * (Modem.baseHz + Double(tone) * Modem.spacingHz) * scale / Modem.sampleRate
            for n in 0..<length {
                c.append(Float(cos(omega * Double(n))))
                s.append(Float(sin(omega * Double(n))))
            }
        }
        cosines = c
        sines = s
    }

    /// Energy of every tone in the window starting at `position`; the caller checks it fits.
    func energies(_ x: UnsafePointer<Float>, at position: Int) -> [Float] {
        var out = [Float](repeating: 0, count: Modem.toneCount)
        cosines.withUnsafeBufferPointer { cosPtr in
            sines.withUnsafeBufferPointer { sinPtr in
                for tone in 0..<Modem.toneCount {
                    var re: Float = 0, im: Float = 0
                    vDSP_dotpr(x + position, 1, cosPtr.baseAddress! + tone * length, 1, &re, vDSP_Length(length))
                    vDSP_dotpr(x + position, 1, sinPtr.baseAddress! + tone * length, 1, &im, vDSP_Length(length))
                    out[tone] = re * re + im * im
                }
            }
        }
        return out
    }
}

/// Listens to a stream of samples and returns every burst it can repair. Feed it any chunk size.
public final class ModemDecoder {
    private var buffer: [Float] = []

    public init() {}

    public func feed(_ samples: [Float]) -> [Data] {
        buffer.append(contentsOf: samples)
        var frames: [Data] = []
        while let (data, end) = scan() {
            frames.append(data)
            buffer.removeFirst(min(end, buffer.count))
        }
        if buffer.count > Modem.maxBufferSamples {
            buffer.removeFirst(buffer.count - Modem.maxBufferSamples)
        }
        return frames
    }

    private enum Attempt {
        case frame(Data, end: Int)
        case needMore
        case failed
    }

    private func scan() -> (Data, Int)? {
        let preambleCount = Modem.preamble.count
        let count = buffer.count
        guard count >= (preambleCount + Modem.headerSymbols + 1) * Modem.symbolSamples else { return nil }
        return buffer.withUnsafeBufferPointer { samples -> (Data, Int)? in
            let x = samples.baseAddress!
            for candidate in candidates(x, count: count) {
                var hypotheses: [(score: Float, bank: Int, start: Int)] = []
                for bank in Modem.banks.indices {
                    for offset in stride(from: -32, through: 32, by: 16) {
                        let start = candidate * Modem.hop + offset
                        guard start >= 0,
                            let score = headScore(x, count: count, bank: Modem.banks[bank], start: start)
                        else { continue }
                        hypotheses.append((score, bank, start))
                    }
                }
                hypotheses.sort { $0.score > $1.score }
                for hypothesis in hypotheses.prefix(3) {
                    switch attempt(x, count: count, bank: Modem.banks[hypothesis.bank], start: hypothesis.start) {
                    case .frame(let data, let end): return (data, end)
                    case .needMore: return nil
                    case .failed: continue
                    }
                }
            }
            return nil
        }
    }

    /// Hop positions where the unscaled tone energies look like the preamble: the best four, earliest first.
    /// Earliest first because `feed` drops everything before a decoded burst: tried by score, a later burst
    /// in the same buffer (a sound file holds them all at once) could be decoded first and erase an earlier one.
    private func candidates(_ x: UnsafePointer<Float>, count: Int) -> [Int] {
        let bank = Modem.banks[Modem.gridCenter]
        let hops = (count - bank.length) / Modem.hop + 1
        let perSymbol = Modem.symbolSamples / Modem.hop
        let span = perSymbol * (Modem.preamble.count - 1)
        guard hops > span else { return [] }

        var share = [Float](repeating: 0, count: hops * Modem.toneCount)
        for h in 0..<hops {
            let e = bank.energies(x, at: h * Modem.hop)
            let total = e.reduce(0, +)
            guard total > 1e-12 else { continue }
            for k in 0..<Modem.toneCount { share[h * Modem.toneCount + k] = e[k] / total }
        }
        let scores = (0..<(hops - span)).map { h0 -> Float in
            var sum: Float = 0
            for (k, tone) in Modem.preamble.enumerated() { sum += share[(h0 + perSymbol * k) * Modem.toneCount + tone] }
            return sum / Float(Modem.preamble.count)
        }
        var found: [(Int, Float)] = []
        for h in scores.indices where scores[h] > 0.3 {
            let near = max(0, h - 6)...min(scores.count - 1, h + 6)
            if near.allSatisfy({ scores[$0] <= scores[h] }) { found.append((h, scores[h])) }
        }
        return found.sorted { $0.1 > $1.1 }.prefix(4).map { $0.0 }.sorted()
    }

    private func symbolPosition(_ bank: ToneBank, start: Int, index: Int) -> Int {
        start + Int((Double(index) * bank.spacing).rounded())
    }

    /// How well the preamble and header symbols fit this clock scale and start; nil if they are not all in the buffer.
    private func headScore(_ x: UnsafePointer<Float>, count: Int, bank: ToneBank, start: Int) -> Float? {
        let preambleCount = Modem.preamble.count
        let symbols = preambleCount + Modem.headerSymbols
        guard symbolPosition(bank, start: start, index: symbols - 1) + bank.length <= count else { return nil }
        var sum: Float = 0
        for k in 0..<symbols {
            let e = bank.energies(x, at: symbolPosition(bank, start: start, index: k))
            let total = e.reduce(0, +)
            guard total > 1e-12 else { continue }
            sum += (k < preambleCount ? e[Modem.preamble[k]] : e.max()!) / total
        }
        return sum / Float(symbols)
    }

    private func attempt(_ x: UnsafePointer<Float>, count: Int, bank: ToneBank, start: Int) -> Attempt {
        let preambleCount = Modem.preamble.count

        func bytes(from first: Int, count byteCount: Int) -> [UInt8] {
            (0..<byteCount).map { i in
                let high = strongest(x, bank: bank, at: symbolPosition(bank, start: start, index: first + 2 * i))
                let low = strongest(x, bank: bank, at: symbolPosition(bank, start: start, index: first + 2 * i + 1))
                return UInt8(high << 4 | low)
            }
        }

        guard let header = ReedSolomon.decode(bytes(from: preambleCount, count: 1 + Modem.headerParity), parity: Modem.headerParity),
            let length = header.first, (1...Modem.maxPayload).contains(Int(length))
        else { return .failed }

        let bodyBytes = Int(length) + Modem.bodyParity
        let total = preambleCount + Modem.headerSymbols + 2 * bodyBytes
        guard symbolPosition(bank, start: start, index: total - 1) + bank.length <= count else { return .needMore }
        let word = bytes(from: preambleCount + Modem.headerSymbols, count: bodyBytes)
        guard let payload = ReedSolomon.decode(word, parity: Modem.bodyParity) else { return .failed }
        return .frame(Data(payload), end: min(count, start + Int((Double(total) * bank.spacing).rounded())))
    }

    private func strongest(_ x: UnsafePointer<Float>, bank: ToneBank, at position: Int) -> Int {
        let e = bank.energies(x, at: position)
        return e.indices.max { e[$0] < e[$1] }!
    }
}
