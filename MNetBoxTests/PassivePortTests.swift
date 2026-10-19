import XCTest
@testable import MNetBox

final class PassivePortTests: XCTestCase {
    private func port(_ kind: String, id: Int) throws -> PassivePort {
        let url = try XCTUnwrap(URL(string: "https://example.test/api/dcim/\(kind)/\(id)/"))
        let body = try XCTUnwrap(CableTraceFixture.response(url)?.1)
        return try JSONDecoder().decode(PassivePort.self, from: Data(body.utf8))
    }
    func testFrontAndRearMappingsRetainExactParentAndPositions() throws {
        let rear = try port("rear-ports", id: 901); try rear.validate(kind: .rear, id: 901, deviceID: 302); XCTAssertEqual(rear.mappings.first?.frontPort, 902)
        let front = try port("front-ports", id: 902); try front.validate(kind: .front, id: 902, deviceID: 302); XCTAssertEqual(front.mappings.first?.rearPort, 901)
        XCTAssertThrowsError(try front.validate(kind: .front, id: 902, deviceID: 301)); XCTAssertThrowsError(try front.validate(kind: .rear, id: 902, deviceID: 302))
    }
    func testMissingMappingMetadataAndOutOfRangePositionFailClosed() throws {
        let url = URL(string: "https://example.test/api/dcim/rear-ports/901/")!
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CableTraceFixture.response(url)!.1.utf8)) as? [String: Any])
        row.removeValue(forKey: "front_ports"); XCTAssertThrowsError(try JSONDecoder().decode(PassivePort.self, from: JSONSerialization.data(withJSONObject: row)))
        row["front_ports"] = [["position": 2, "front_port": 902, "front_port_position": 1]]
        let invalid = try JSONDecoder().decode(PassivePort.self, from: JSONSerialization.data(withJSONObject: row)); XCTAssertThrowsError(try invalid.validate(kind: .rear, id: 901, deviceID: 302))
    }
}
