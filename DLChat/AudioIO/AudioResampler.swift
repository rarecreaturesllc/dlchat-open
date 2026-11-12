import AVFoundation
import DLCore

/// Converts audio buffers between the hardware rate (44.1 or 48 kHz) and the modem rate (8 kHz, mono).
/// Keeps its filter state between calls, so a stream can be fed in chunks.
final class AudioResampler {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat

    init?(from input: AVAudioFormat, rate: Double = Modem.sampleRate) {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: out)
        else { return nil }
        self.converter = converter
        outFormat = out
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return [] }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// A buffer holding `samples` at `rate`, mono.
    static func buffer(_ samples: [Float], rate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
