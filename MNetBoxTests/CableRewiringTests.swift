import XCTest
@testable import MNetBox

final class CableRewiringTests: XCTestCase {
    private func endpoint(_ id: Int, family: PortPanelFamily = .interfaces, name: String? = nil) -> CableEndpointSelection {
        .init(family: family, id: id, deviceID: 301, deviceName: "Device", name: name ?? "Port \(id)")
    }
    private func plan(side: CableSide = .a, destination: CableEndpointSelection? = nil) -> CableRewirePlan {
        .init(cableID: 7, etag: "W/\"revision-1\"", side: side, current: endpoint(1), kept: endpoint(2), destination: destination ?? endpoint(3))
    }
    private func cable(a: Int = 1, b: Int = 2, device: Int = 301) throws -> CableObject {
        func end(_ id: Int) -> [String: Any] {
            ["object_type": "dcim.interface", "object_id": id, "object": ["id": id, "name": "Port \(id)", "device": ["id": device, "name": "Device"]]]
        }
        return try JSONDecoder().decode(CableObject.self, from: JSONSerialization.data(withJSONObject: ["id": 7, "a_terminations": [end(a)], "b_terminations": [end(b)]]))
    }
    func testRewirePayloadChangesExactlyOneTypedSide() throws {
        for side in CableSide.allCases {
            let proposal = try plan(side: side).validated()
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: proposal.body) as? [String: Any])
            XCTAssertEqual(Set(body.keys), [side.key])
            let ends = try XCTUnwrap(body[side.key] as? [[String: Any]])
            XCTAssertEqual(ends.count, 1)
            XCTAssertEqual(ends[0]["object_type"] as? String, "dcim.interface")
            XCTAssertEqual(ends[0]["object_id"] as? Int, 3)
        }
    }
    func testSamePortCannotBecomeDifferentByRenamingIt() {
        XCTAssertThrowsError(try plan(destination: endpoint(1, name: "Renamed")).validated())
        XCTAssertThrowsError(try plan(destination: endpoint(2)).validated())
        XCTAssertThrowsError(try plan(destination: endpoint(3, family: .power)).validated())
    }
    func testPortIdentityIncludesModelType() throws {
        XCTAssertNoThrow(try plan(destination: endpoint(1, family: .front)).validated())
    }
    func testReviewAndReplyKeepTheOtherEndAndDeviceIdentity() throws {
        let proposal = plan()
        XCTAssertNoThrow(try proposal.matches(cable(), moved: false))
        XCTAssertNoThrow(try proposal.matches(cable(a: 3), moved: true))
        XCTAssertThrowsError(try proposal.matches(cable(a: 3), moved: false))
        XCTAssertThrowsError(try proposal.matches(cable(a: 3, b: 4), moved: true))
        XCTAssertThrowsError(try proposal.matches(cable(device: 999), moved: false))
        let opposite = CableRewirePlan(cableID: 7, etag: proposal.etag, side: .b, current: endpoint(2), kept: endpoint(1), destination: endpoint(3))
        XCTAssertNoThrow(try opposite.matches(cable(b: 3), moved: true))
    }
    func testLengthNormalizationValidationAndNullPayload() throws {
        for (input, expected) in [("12,50", "12.5"), (" 2.00 ", "2"), ("0.01", "0.01")] {
            let value = EditableTextField.length.normalized(input)
            XCTAssertEqual(value, expected)
            XCTAssertNoThrow(try EditableTextField.length.validate(value, for: .cables))
        }
        for value in ["0", "-1", "1e3", "1.234", "1000000", "nan"] {
            XCTAssertThrowsError(try EditableTextField.length.validate(value, for: .cables))
        }
        for field in [EditableTextField.length, .lengthUnit] {
            XCTAssertTrue(field.supports(.cables)); XCTAssertFalse(field.supports(.devices))
            let data = try JSONEncoder().encode(TextEditPayload(field: field, value: ""))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(body.keys), [field.rawValue]); XCTAssertTrue(body[field.rawValue] is NSNull)
        }
        XCTAssertThrowsError(try EditableTextField.lengthUnit.validate("yards", for: .cables))
    }
    func testLengthDistinguishesMissingNullAndMalformedValues() throws {
        func object(_ suffix: String) throws -> TextEditObject {
            try JSONDecoder().decode(TextEditObject.self, from: Data(("{\"id\":7,\"description\":\"\"" + suffix + "}").utf8))
        }
        XCTAssertNil(try object("").value(for: .length))
        XCTAssertEqual(try object(",\"length\":null").value(for: .length), "")
        XCTAssertEqual(try object(",\"length\":\"2.50\"").value(for: .length), "2.5")
        XCTAssertThrowsError(try object(",\"length\":{}"))
        XCTAssertThrowsError(try object(",\"length_unit\":42"))
    }
}
