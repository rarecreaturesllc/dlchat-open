import XCTest
@testable import DLCore

final class MeshMapTests: XCTestCase {
    func testParsesWorldwideNodesAndSkipsBadOnes() throws {
        let json = """
        {"1000789369":{"longName":"Meshtastic d579","shortName":"d579","hwModel":"RAK4631","latitude":527695872,"longitude":136577024,
          "seenBy":{"msh/EU_868/a":1794160956,"msh/EU_868/b":1794160999}},
         "42":{"longName":"No position","shortName":"np"},
         "not-a-number":{"longName":"bad"},
         "7":"not an object"}
        """
        let nodes = try XCTUnwrap(MeshMap.parseWorldwide(Data(json.utf8)))
        XCTAssertEqual(nodes.count, 2)
        let d579 = try XCTUnwrap(nodes.first { $0.num == 1_000_789_369 })
        XCTAssertEqual(d579.latitude!, 52.7695872, accuracy: 1e-7)
        XCTAssertEqual(d579.longitude!, 13.6577024, accuracy: 1e-7)
        XCTAssertEqual(d579.lastHeard, Date(timeIntervalSince1970: 1_794_160_999), "the latest sighting")
        XCTAssertEqual(d579.source, .worldwide)
        XCTAssertFalse(try XCTUnwrap(nodes.first { $0.num == 42 }).hasLocation)
        XCTAssertNil(MeshMap.parseWorldwide(Data("[1,2]".utf8)))
    }

    func testNamesFromStrangersAreTrimmedAndCapped() {
        let node = MeshNode(num: 0xBEEF, longName: "  evil\u{0007}\nname" + String(repeating: "x", count: 100), source: .worldwide)
        XCTAssertFalse(node.longName.contains("\u{0007}"))
        XCTAssertFalse(node.longName.contains("\n"))
        XCTAssertLessThanOrEqual(node.longName.count, 40)
        XCTAssertEqual(MeshNode(num: 0xBEEF, source: .radio).displayName, "Meshtastic beef")
    }

    func testDistanceAndBearing() {
        // San Francisco to Oakland: about 13 km, roughly east-north-east.
        let d = MeshMap.distance(fromLat: 37.7749, lon: -122.4194, toLat: 37.8044, lon: -122.2712)
        XCTAssertEqual(d, 13_400, accuracy: 300)
        let b = MeshMap.bearing(fromLat: 37.7749, lon: -122.4194, toLat: 37.8044, lon: -122.2712)
        XCTAssertEqual(b, 76, accuracy: 3)
        XCTAssertEqual(MeshMap.compass(b), "E")
        XCTAssertEqual(MeshMap.compass(0), "N")
        XCTAssertEqual(MeshMap.compass(350), "N")
        XCTAssertEqual(MeshMap.compass(225), "SW")
    }

    func testRadioNodeInfoWithPosition() throws {
        var position = Meshtastic.Writer()
        position.fixed32(field: 1, UInt32(bitPattern: Int32(377_749_000)))
        position.fixed32(field: 2, UInt32(bitPattern: Int32(-1_224_194_000)))
        var user = Meshtastic.Writer(); user.bytes(field: 2, Data("Hilltop".utf8)); user.bytes(field: 3, Data("HT".utf8))
        var info = Meshtastic.Writer()
        info.varint(field: 1, 0xC3)
        info.bytes(field: 2, user.data)
        info.bytes(field: 3, position.data)
        info.fixed32(field: 5, 1_794_160_000)
        info.varint(field: 9, 2)
        var from = Meshtastic.Writer(); from.bytes(field: 4, info.data)
        let node = try XCTUnwrap(Meshtastic.meshNode(fromNodeInfo: from.data))
        XCTAssertEqual(node.num, 0xC3)
        XCTAssertEqual(node.displayName, "Hilltop")
        XCTAssertEqual(node.latitude!, 37.7749, accuracy: 1e-6)
        XCTAssertEqual(node.longitude!, -122.4194, accuracy: 1e-6)
        XCTAssertEqual(node.hops, 2)
        XCTAssertEqual(node.lastHeard, Date(timeIntervalSince1970: 1_794_160_000))
    }

    func testMilesOrKilometres() {
        XCTAssertEqual(MeshMap.format(metres: 1200, miles: false), "1.2 km")
        XCTAssertEqual(MeshMap.format(metres: 1609.344, miles: true), "1.0 mi")
        XCTAssertEqual(MeshMap.format(metres: 25_000, miles: false), "25 km")
        XCTAssertEqual(MeshMap.format(metres: 25_000, miles: true), "16 mi")
        XCTAssertEqual(MeshMap.ranges(miles: true).first!, 1609.344, accuracy: 0.001)
        XCTAssertTrue(MeshMap.prefersMiles(Locale(identifier: "en_US")))
        XCTAssertFalse(MeshMap.prefersMiles(Locale(identifier: "de_DE")))
    }
}
