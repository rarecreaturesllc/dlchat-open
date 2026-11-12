import AVFoundation
import DLCore
import Observation

/// Plays a tone burst through the phone speaker. The burst starts with a lead-in tone for VOX radios.
@MainActor
@Observable
final class TonePlayer {
    enum State: Equatable { case idle, starting, playing, finished, failed(String) }

    private(set) var state: State = .idle
    private(set) var progress = 0.0
    private(set) var warnings: [String] = []
    /// Silences the burst (it keeps playing, so it still finishes and opens). Can be changed while it plays.
    var muted = false { didSet { player?.volume = Self.outputVolume(volume, muted: muted) } }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var volume: Float = 1
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var routeObserver: NSObjectProtocol?

    /// Seconds the burst takes, shown before it is played.
    static func duration(of samples: [Float]) -> Double { Double(samples.count) / Modem.sampleRate }

    /// What the player node is set to: `volume` (0...1), or nothing when muted.
    nonisolated static func outputVolume(_ volume: Float, muted: Bool) -> Float { muted ? 0 : min(max(volume, 0), 1) }

    /// Plays at `volume` of full level (Send keeps full level for radios). The `.playback` session
    /// plays even with the iPhone's silent switch on.
    func play(_ samples: [Float], volume: Float = 1) {
        stop()
        self.volume = volume
        guard !samples.isEmpty, let buffer = AudioResampler.buffer(samples, rate: Modem.sampleRate) else {
            state = .failed("There is nothing to play yet.")
            return
        }
        run += 1
        let mine = run
        state = .starting
        progress = 0
        let format = buffer.format
        let length = Self.duration(of: samples)
        Task { @MainActor [weak self] in
            // Starting audio can block for seconds, so it never runs on the main thread.
            let started: Result<PlayerBox, Failure> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.setUp(format: format))
                }
            }
            guard let self, self.run == mine else {
                if case .success(let box) = started { box.engine.stop() }
                return
            }
            switch started {
            case .failure(let failure):
                self.state = .failed(failure.note)
                return
            case .success(let box):
                self.engine = box.engine
                self.player = box.player
                box.player.volume = Self.outputVolume(self.volume, muted: self.muted)
            }
            self.refreshWarnings()
            self.routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshWarnings() } }
            self.player?.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.run == mine else { return }
                    self.finish(.finished)
                }
            }
            self.player?.play()
            self.state = .playing
            let began = Date()
            while self.run == mine, self.state == .playing {
                self.progress = min(1, Date().timeIntervalSince(began) / length)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private struct Failure: Error { let note: String }
    private struct PlayerBox: @unchecked Sendable { let engine: AVAudioEngine; let player: AVAudioPlayerNode }

    nonisolated private static func setUp(format: AVAudioFormat) -> Result<PlayerBox, Failure> {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
        } catch {
            return .failure(Failure(note: "The phone could not start its speaker. Close other audio apps and try again."))
        }
        return .success(PlayerBox(engine: engine, player: player))
    }

    func stop() {
        guard state == .playing || state == .starting else { return }
        run += 1
        finish(.idle)
    }

    private func finish(_ end: State) {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if end == .finished { progress = 1 }
        state = end
    }

    private func refreshWarnings() {
        warnings = AudioRoute.playbackWarnings(outputs: AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType))
    }
}

/// Listens on the phone microphone for tone bursts. The microphone is asked for the first time it is
/// used. Samples are decoded in memory and never stored.
@MainActor
@Observable
final class ToneListener {
    enum State: Equatable { case idle, listening, denied, failed(String) }

    private(set) var state: State = .idle
    private(set) var warnings: [String] = []
    /// Loudness of the last moment, 0 to 1, so the person can see the radio is being heard.
    private(set) var level = 0.0
    var onBurst: ((Data) -> Void)?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    @ObservationIgnored private let queue = DispatchQueue(label: "dlchat.tone-decode", qos: .userInitiated)
    /// Bumped by every start and stop, so a setup that finishes after Listen was closed tears itself down.
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var starting = false

    func start() async {
        guard state != .listening, !starting else { return }
        starting = true
        defer { starting = false }
        run += 1
        let myRun = run
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        guard AVAudioApplication.shared.recordPermission == .granted else { state = .denied; return }
        guard myRun == run else { return }

        let queue = self.queue
        let deliver: @Sendable ([Data], Float) -> Void = { [weak self] bursts, rms in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.level = min(1, Double(rms) * 4)
                    for burst in bursts { self?.onBurst?(burst) }
                }
            }
        }
        // Starting audio can block for seconds, so it never runs on the main thread.
        let started: Result<EngineBox, Failure> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.setUp(queue: queue, deliver: deliver))
            }
        }
        switch started {
        case .failure(let failure):
            state = .failed(failure.note)
            return
        case .success(let box):
            guard myRun == run else {
                // Stopped while the microphone was starting: never leave it on.
                box.engine.inputNode.removeTap(onBus: 0)
                box.engine.stop()
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            engine = box.engine
        }
        refreshWarnings()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshWarnings() } }
        state = .listening
    }

    private struct Failure: Error { let note: String }
    private struct EngineBox: @unchecked Sendable { let engine: AVAudioEngine }

    nonisolated private static func setUp(queue: DispatchQueue, deliver: @escaping @Sendable ([Data], Float) -> Void) -> Result<EngineBox, Failure> {
        let session = AVAudioSession.sharedInstance()
        let engine = AVAudioEngine()
        do {
            // Measurement mode turns off the phone's voice processing, which would mangle tones.
            try session.setCategory(.record, mode: .measurement, options: [])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(builtIn)
            }
            try session.setActive(true)
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, let resampler = AudioResampler(from: format) else {
                return .failure(Failure(note: "The microphone is not available."))
            }
            let decoder = ModemDecoder()
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                let samples = resampler.convert(buffer)
                queue.async {
                    let bursts = decoder.feed(samples)
                    let rms = samples.isEmpty ? 0 : (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
                    deliver(bursts, rms)
                }
            }
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            return .failure(Failure(note: "The phone could not start its microphone. Close other audio apps and try again."))
        }
        return .success(EngineBox(engine: engine))
    }

    func stop() {
        run += 1
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        level = 0
        if state == .listening { state = .idle }
    }

    private func refreshWarnings() {
        warnings = AudioRoute.listenWarnings(inputs: AVAudioSession.sharedInstance().currentRoute.inputs.map(\.portType))
    }
}
