import XCTest
@testable import TorKit

final class TorTests: XCTestCase {
    func testReadsBootstrapProgress() {
        let reply = ["250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=85 TAG=ap_conn_done SUMMARY=\"Connected\"", "250 OK"]
        XCTAssertEqual(Tor.progress(in: reply), 85)
        XCTAssertNil(Tor.progress(in: ["250 OK"]))
    }

    func testReadsSocksPort() {
        XCTAssertEqual(Tor.socksPort(in: ["250-net/listeners/socks=\"127.0.0.1:53211\"", "250 OK"]), 53211)
        XCTAssertNil(Tor.socksPort(in: ["250-net/listeners/socks=", "250 OK"]))
    }

    func testFinalReplyLine() {
        XCTAssertTrue(Tor.isFinal("250 OK"))
        XCTAssertFalse(Tor.isFinal("250-net/listeners/socks=x"))
        XCTAssertFalse(Tor.isFinal("250+data"))
    }

    func testRefusesLeakyConnectionsAndStartsPaused() {
        let args = Tor.arguments(dataDirectory: "/x")
        XCTAssertEqual(args[args.firstIndex(of: "--SafeSocks")! + 1], "1")
        XCTAssertEqual(args[args.firstIndex(of: "--SocksPort")! + 1], "127.0.0.1:auto")
        XCTAssertEqual(args.last, "1")  // DisableNetwork 1 until start() asks
    }

    /// Real tor network. Run with DLCHAT_REAL_TOR=1 swift test --package-path Packages/TorKit
    func testBootstrapsOnTheRealNetwork() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DLCHAT_REAL_TOR"] == "1", "set DLCHAT_REAL_TOR=1")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("torkit-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let port = try await Tor.shared.start(dataDirectory: dir) { print("TOR bootstrap \($0)%") }
        XCTAssertGreaterThan(port, 0)
        // Through tor, with the name resolved by tor (SafeSocks would refuse otherwise).
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [kCFProxyTypeKey: kCFProxyTypeSOCKS, "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": Int(port)]
        let (data, _) = try await URLSession(configuration: config).data(from: URL(string: "https://check.torproject.org/api/ip")!)
        let text = String(decoding: data, as: UTF8.self)
        print("TOR check:", text)
        XCTAssertTrue(text.contains("\"IsTor\":true"))
        // Off and on again (the Settings switch): the new port works too.
        await Tor.shared.pause()
        let again = try await Tor.shared.start(dataDirectory: dir)
        config.connectionProxyDictionary?["SOCKSPort"] = Int(again)
        let (data2, _) = try await URLSession(configuration: config).data(from: URL(string: "https://check.torproject.org/api/ip")!)
        XCTAssertTrue(String(decoding: data2, as: UTF8.self).contains("\"IsTor\":true"), "Tor works after off and on")
        await Tor.shared.pause()
    }
}
