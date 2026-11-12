import AVFoundation
import DLCore

/// The tone message as a sound file, to send through a chat app, and back: Receive opens a sound file
/// and decodes it like Listen would. The file holds only the sealed tones, never the text.
enum SoundFile {
    /// Longest file Receive reads, so a huge recording cannot use up memory.
    static let maxSeconds = 180.0

    /// The shared file's name in the temporary folder. A crash can leave it there; launch removes it.
    static let fileName = "DLChat message.wav"

    /// Writes the tones as a 16-bit WAV in the temporary folder (replaced on each share).
    static func write(_ samples: [Float]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: fileName)
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Modem.sampleRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard let buffer = AudioResampler.buffer(samples, rate: Modem.sampleRate),
              let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false),
              (try? file.write(from: buffer)) != nil
        else { return nil }
        return url
    }

    /// Every message burst found in a sound file (any format iOS reads), or nil if it cannot be read.
    static func bursts(in url: URL) -> [Data]? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(min(Double(file.length), maxSeconds * format.sampleRate))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer, frameCount: frames)) != nil,
              let resampler = AudioResampler(from: format)
        else { return nil }
        return ModemDecoder().feed(resampler.convert(buffer))
    }
}
