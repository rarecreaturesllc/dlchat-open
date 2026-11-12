import AVFoundation

/// What to tell the person when sound would not go through the phone's own speaker or microphone.
/// A radio hears only the speaker, and Bluetooth microphones squash the audio too much for tones.
enum AudioRoute {
    static func playbackWarnings(outputs: [AVAudioSession.Port]) -> [String] {
        guard let other = outputs.first(where: { $0 != .builtInSpeaker }) else { return [] }
        return ["Sound is going to \(name(other)), not the phone speaker. A radio next to the phone will not hear it. Disconnect it first."]
    }

    static func listenWarnings(inputs: [AVAudioSession.Port]) -> [String] {
        guard let other = inputs.first(where: { $0 != .builtInMic }) else { return [] }
        return ["The microphone in use is \(name(other)), not the phone's own. It may cut the sound too far for tones to be read. Disconnect it first."]
    }

    static func name(_ port: AVAudioSession.Port) -> String {
        switch port {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: "a Bluetooth device"
        case .headphones, .headsetMic: "headphones"
        case .airPlay: "AirPlay"
        case .carAudio: "the car"
        case .usbAudio: "a USB device"
        case .HDMI, .displayPort: "a display"
        case .builtInReceiver: "the earpiece"
        default: "another device"
        }
    }
}
