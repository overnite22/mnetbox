import XCTest
@testable import MNetBox

final class IPRangeTests: XCTestCase {
    private func object(start: String = "198.51.100.10/24", end: String = "198.51.100.20/24", family: Int = 4, vrf: Int? = nil) throws -> IPRangeObject {
        let data = try JSONSerialization.data(withJSONObject: ["id": 1, "start_address": start, "end_address": end, "family": ["value": family], "vrf": vrf.map { ["id": $0] as Any } ?? NSNull()])
        return try JSONDecoder().decode(IPRangeObject.self, from: data)
    }
    func testBothFamiliesAndLargeIPv6Bounds() throws {
        XCTAssertNoThrow(try object().validate())
        XCTAssertNoThrow(try object(start: "2001:db8::1/64", end: "2001:db8::ffff/64", family: 6).validate())
        XCTAssertNoThrow(try object(start: "198.51.100.10/24", end: "198.51.100.10/24").validate())
    }
    func testReversedBoundsMixedFamiliesAndInvalidReferencesFailClosed() throws {
        XCTAssertThrowsError(try object(start: "198.51.100.20/24", end: "198.51.100.10/24").validate())
        XCTAssertThrowsError(try object(end: "2001:db8::1/64").validate())
        XCTAssertThrowsError(try object(family: 6).validate())
        XCTAssertThrowsError(try object(vrf: 0).validate())
    }
    func testGlobalVRFIsDistinctFromAnUnfilteredQuery() throws {
        var query = IPRangeQuery()
        XCTAssertTrue(query.matches(try object(vrf: 7)))
        query.vrf = ReferenceSelection(id: 0, title: "Global")
        XCTAssertTrue(query.matches(try object()))
        XCTAssertFalse(query.matches(try object(vrf: 7)))
        XCTAssertEqual(query.items.first { $0.name == "vrf_id" }?.value, "null")
        query.vrf = ReferenceSelection(id: 7, title: "VRF")
        XCTAssertTrue(query.matches(try object(vrf: 7)))
        XCTAssertFalse(query.matches(try object()))
    }
    func testPaginationCannotDropOrDuplicateFiltersOrChangeCollection() throws {
        var query = IPRangeQuery(search: "edge", family: "4")
        query.vrf = ReferenceSelection(id: 7, title: "VRF")
        var components = try XCTUnwrap(URLComponents(string: "https://example.test/api/ipam/ip-ranges/"))
        components.queryItems = query.items + [.init(name: "offset", value: "50")]
        XCTAssertNoThrow(try CollectionLinks.validate(components.string, path: IPRangeService.path, required: query.items))
        components.queryItems?.removeAll { $0.name == "vrf_id" }
        XCTAssertThrowsError(try CollectionLinks.validate(components.string, path: IPRangeService.path, required: query.items))
        components.queryItems = query.items + [.init(name: "vrf_id", value: "8")]
        XCTAssertThrowsError(try CollectionLinks.validate(components.string, path: IPRangeService.path, required: query.items))
        components.queryItems = query.items; components.path = "/api/ipam/ip-addresses/"
        XCTAssertThrowsError(try CollectionLinks.validate(components.string, path: IPRangeService.path, required: query.items))
    }
}
