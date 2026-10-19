import XCTest
@testable import MNetBox

final class CableCreationTests: XCTestCase {
    private var a: CableEndpointSelection { .init(family: .interfaces, id: 1503, deviceID: 301, deviceName: "Core-switch", name: "Gi1/0/3") }
    private var b: CableEndpointSelection { .init(family: .interfaces, id: 1601, deviceID: 303, deviceName: "Edge-router", name: "eth1") }
    private func plan(_ endpoint: CableEndpointSelection? = nil) -> CableCreationPlan { .init(a: a, b: endpoint ?? b, label: "Patch test", type: "cat6", status: "connected", color: "0088ff") }
    func testTypedPayloadAndSamePortAndUnsupportedFamily() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan())) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["a_terminations", "b_terminations", "label", "type", "status", "color"])
        XCTAssertEqual((body["a_terminations"] as? [[String: Any]])?.first?["object_type"] as? String, "dcim.interface")
        XCTAssertThrowsError(try plan(a).validated())
        XCTAssertThrowsError(try plan(.init(family: .power, id: 1, deviceID: 301, deviceName: "A", name: "PSU")).validated())
        XCTAssertNoThrow(try plan(.init(family: .front, id: 1503, deviceID: 301, deviceName: "A", name: "Front1")).validated())
    }
    func testExplicitFreshOccupancyMetadataRequired() throws {
        var row = PortPanelFixture.row(3)
        func decode() throws -> CableEndpointSnapshot { try JSONDecoder().decode(CableEndpointSnapshot.self, from: JSONSerialization.data(withJSONObject: row)) }
        XCTAssertNoThrow(try decode().validate(a))
        row["mark_connected"] = true; XCTAssertThrowsError(try decode().validate(a))
        row["mark_connected"] = false; row["_occupied"] = true; XCTAssertThrowsError(try decode().validate(a))
        row.removeValue(forKey: "_occupied"); XCTAssertThrowsError(try decode())
        row["_occupied"] = false; row.removeValue(forKey: "cable"); XCTAssertThrowsError(try decode())
    }
    func testVirtualWirelessAndChannelInterfacesRejected() throws {
        for type in ["virtual", "lag", "bridge", "ieee802.11ax", "other-wireless", "5g", "channel"] {
            var row = PortPanelFixture.row(3); row["type"] = ["value": type]
            let endpoint = try JSONDecoder().decode(CableEndpointSnapshot.self, from: JSONSerialization.data(withJSONObject: row))
            XCTAssertThrowsError(try endpoint.validate(a))
        }
    }
    @MainActor func testReviewThenOneSuccessfulAttempt() async throws {
        let fixture = CableCreationFixture(), client = try api(fixture)
        let model = CableCreateModel(client: client, source: a); model.destination = b; model.label = "Patch test"; model.type = "cat6"
        await model.review(); XCTAssertNotNil(model.reviewed); XCTAssertEqual(fixture.posts, 0)
        await model.create(); XCTAssertEqual(model.created?.id, 9902); XCTAssertEqual(fixture.posts, 1)
        await model.create(); XCTAssertEqual(fixture.posts, 1)
        await client.close()
    }
    @MainActor func testPortBecomesOccupiedBeforeConfirmationBlocksPost() async throws {
        let fixture = CableCreationFixture(); fixture.occupiedAtConfirm = true
        let client = try api(fixture), model = CableCreateModel(client: client, source: a); model.destination = b
        await model.review(); XCTAssertNotNil(model.reviewed)
        await model.create(); XCTAssertNil(model.created); XCTAssertEqual(fixture.posts, 0); XCTAssertNotNil(model.errorMessage)
        await client.close()
    }
    @MainActor func testDeniedAndInvalidRepliesDoNotRetry() async throws {
        for status in [403, 500, 201] {
            let fixture = CableCreationFixture(); fixture.statusCode = status; fixture.wrongReply = status == 201
            let client = try api(fixture), model = CableCreateModel(client: client, source: a); model.destination = b
            await model.review(); await model.create(); await model.create()
            XCTAssertNil(model.created); XCTAssertNotNil(model.errorMessage); XCTAssertEqual(fixture.posts, 1)
            await client.close()
        }
    }
    private func api(_ fixture: CableCreationFixture) throws -> APIClient {
        CableCreationProtocol.fixture = fixture
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CableCreationProtocol.self]
        return APIClient(credential: .init(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
}
private final class CableCreationProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture = CableCreationFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = Self.fixture.response(request), let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
