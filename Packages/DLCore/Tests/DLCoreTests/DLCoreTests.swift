import XCTest
@testable import DLCore

final class DLCoreTests: XCTestCase {
    func testProtocolVersionIsOne() {
        XCTAssertEqual(DLCore.protocolVersion, 1)
    }
}
