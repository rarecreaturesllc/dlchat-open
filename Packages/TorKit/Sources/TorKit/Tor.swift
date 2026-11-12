import Darwin
import Foundation
import tor

/// Tor running inside the app: one tor thread per process (tor_run_main is not safe to call twice),
/// driven over its owning control socket, which only this process holds. Turning it off pauses the
/// network (DisableNetwork) rather than stopping tor, so it can be turned back on.
public final class Tor: @unchecked Sendable {
    public static let shared = Tor()

    public enum TorError: Error, Equatable { case failed(String), timedOut }

    private let queue = DispatchQueue(label: "dlchat.tor.control")
    private var control: Int32 = -1
    /// tor's thread has exited; tor_run_main cannot run twice, so only an app restart brings it back.
    private var dead = false

    /// Starts tor (or wakes it), waits until it has built a circuit, and returns the local SOCKS port.
    /// `progress` gets the bootstrap percentage on the way.
    public func start(dataDirectory: URL, timeout: Duration = .seconds(120),
                      progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws -> UInt16 {
        try await run { try self.launchIfNeeded(dataDirectory: dataDirectory) }
        try await run { try self.expectOK("SETCONF DisableNetwork=0") }
        let deadline = ContinuousClock.now + timeout
        while true {
            // After a pause, bootstrap still reads 100 while no circuit exists yet, so wait for both.
            // On a first bootstrap tor can stay silent on the control socket for more than the 30 s read
            // timeout while it loads the network consensus (seen at 30% on a fresh install). That is tor
            // being busy, not failing: ask again until the overall deadline.
            let reply: [String]
            do {
                reply = try await run { try self.command("GETINFO status/bootstrap-phase status/circuit-established") }
            } catch TorError.timedOut {
                if ContinuousClock.now > deadline { throw TorError.timedOut }
                continue
            }
            if let p = Self.progress(in: reply) {
                progress(p)
                if p >= 100, reply.contains("250-status/circuit-established=1") { break }
            }
            if ContinuousClock.now > deadline { throw TorError.timedOut }
            try await Task.sleep(for: .milliseconds(500))
        }
        // Asked every time: pausing closes the listener, and "auto" picks a new port on the way back.
        return try await run {
            guard let port = Self.socksPort(in: try self.command("GETINFO net/listeners/socks")) else {
                throw TorError.failed("no SOCKS listener")
            }
            return port
        }
    }

    /// Stops all tor network traffic until the next `start`.
    public func pause() async {
        _ = try? await run { try self.expectOK("SETCONF DisableNetwork=1") }
    }

    // MARK: Process

    private func launchIfNeeded(dataDirectory: URL) throws {
        guard control < 0 else { return }
        guard !dead else { throw TorError.failed("tor stopped; restart the app") }
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard let cfg = tor_main_configuration_new() else { throw TorError.failed("no configuration") }
        let fd = tor_main_configuration_setup_control_socket(cfg)
        guard fd >= 0 else { throw TorError.failed("no control socket") }
        let args = Self.arguments(dataDirectory: dataDirectory.path)
        // tor keeps argv for its whole life, so these copies are never freed.
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: args.count + 1)
        for (i, arg) in args.enumerated() { argv[i] = strdup(arg) }
        argv[args.count] = nil
        guard tor_main_configuration_set_command_line(cfg, Int32(args.count), argv) == 0 else {
            throw TorError.failed("bad command line")
        }
        let thread = Thread { _ = tor_run_main(cfg) }
        thread.name = "tor"
        thread.stackSize = 4 << 20
        thread.start()
        // A write after tor's thread exits must fail with EPIPE, not kill the app with SIGPIPE.
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        // A stalled tor must not hang the control queue forever.
        var wait = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        control = fd
        do {
            try expectOK("AUTHENTICATE")  // the owning socket is private to us, so no password
        } catch {
            close(fd)
            control = -1
            dead = true
            throw error
        }
    }

    static func arguments(dataDirectory: String) -> [String] {
        ["tor",
         "--DataDirectory", dataDirectory,
         "--SocksPort", "127.0.0.1:auto",
         "--SafeSocks", "1",          // refuse connections that resolved the name outside tor (DNS leak)
         "--ClientOnly", "1",
         "--AvoidDiskWrites", "1",
         "--GeoIPFile", "", "--GeoIPv6File", "",
         "--Log", "err stderr",
         "--DisableNetwork", "1"]
    }

    // MARK: Control protocol

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func expectOK(_ line: String) throws {
        let reply = try command(line)
        guard reply.last?.hasPrefix("250 ") == true else { throw TorError.failed(reply.last ?? line) }
    }

    /// Sends one command and reads its whole reply (until a line whose status code is followed by a space).
    private func command(_ line: String) throws -> [String] {
        guard control >= 0 else { throw TorError.failed("not running") }
        // A reply that arrived after an earlier command timed out is still in the socket and would be read
        // as this command's answer: drop anything waiting before asking.
        var stale = [UInt8](repeating: 0, count: 4096)
        while recv(control, &stale, stale.count, MSG_DONTWAIT) > 0 {}
        let bytes = Array((line + "\r\n").utf8)
        guard bytes.withUnsafeBytes({ write(control, $0.baseAddress, $0.count) }) == bytes.count else {
            throw TorError.failed("control write")
        }
        var lines: [String] = []
        var buffer: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(control, &chunk, chunk.count)
            if n < 0, errno == EAGAIN || errno == EWOULDBLOCK { throw TorError.timedOut }
            guard n > 0 else {
                // EOF: tor's thread is gone and cannot be started again in this process.
                close(control)
                control = -1
                dead = true
                throw TorError.failed("tor stopped")
            }
            buffer += chunk[0..<n]
            while let end = buffer.firstIndex(of: 10) {
                let text = String(decoding: buffer[..<end], as: UTF8.self).trimmingCharacters(in: .newlines)
                buffer.removeSubrange(...end)
                lines.append(text)
                if Self.isFinal(text) { return lines }
            }
        }
    }

    static func isFinal(_ line: String) -> Bool {
        let chars = Array(line)
        return chars.count >= 4 && chars[0..<3].allSatisfy(\.isNumber) && chars[3] == " "
    }

    /// `250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=85 TAG=... SUMMARY="..."` -> 85
    static func progress(in reply: [String]) -> Int? {
        for line in reply {
            guard let range = line.range(of: "PROGRESS=") else { continue }
            return Int(line[range.upperBound...].prefix(while: \.isNumber))
        }
        return nil
    }

    /// `250-net/listeners/socks="127.0.0.1:53211"` -> 53211
    static func socksPort(in reply: [String]) -> UInt16? {
        for line in reply where line.contains("net/listeners/socks=") {
            let value = line.split(separator: "=", maxSplits: 1).last.map { $0.replacingOccurrences(of: "\"", with: "") } ?? ""
            if let port = value.split(separator: " ").first?.split(separator: ":").last { return UInt16(port) }
        }
        return nil
    }
}
