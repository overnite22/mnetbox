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

@MainActor final class CableLifecycleTransportTests: XCTestCase {
    private func client(_ scenario: String) throws -> APIClient {
        LifecycleProtocol.state.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private func endpoint(_ id: Int) -> CableEndpointSelection {
        .init(family: .interfaces, id: id, deviceID: 301, deviceName: "Device", name: "Port \(id)")
    }
    func testRewireRepeatsPreflightAndSendsOneVersionedPatch() async throws {
        let api = try client("success")
        let model = CableRewireModel(client: api, cableID: 7, side: .a)
        await model.load(); model.destination = endpoint(3)
        await model.review(); XCTAssertNotNil(model.reviewed)
        await model.confirm(); XCTAssertNotNil(model.moved)
        await model.confirm()
        let patches = LifecycleProtocol.state.requests.filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches.first?.url?.path, "/api/dcim/cables/7/")
        XCTAssertEqual(patches.first?.value(forHTTPHeaderField: "If-Match"), "W/\"revision-1\"")
        XCTAssertEqual(LifecycleProtocol.state.requests.filter { $0.url?.path == "/api/dcim/interfaces/3/" }.count, 2)
        await api.close()
    }
    func testChangedCableOrOccupiedDestinationBlocksMutation() async throws {
        for scenario in ["conflict", "occupied", "renamed"] {
            let api = try client(scenario)
            let model = CableRewireModel(client: api, cableID: 7, side: .a)
            await model.load(); model.destination = endpoint(3)
            await model.review(); XCTAssertNil(model.reviewed); XCTAssertNotNil(model.errorMessage)
            await model.confirm()
            XCTAssertFalse(LifecycleProtocol.state.requests.contains { $0.httpMethod == "PATCH" })
            await api.close()
        }
    }
    func testLostRewireReplyCannotBeRetriedInTheSameForm() async throws {
        let api = try client("lost")
        let model = CableRewireModel(client: api, cableID: 7, side: .a)
        await model.load(); model.destination = endpoint(3); await model.review()
        await model.confirm(); XCTAssertNil(model.moved); XCTAssertTrue(model.attempted)
        XCTAssertNotNil(model.errorMessage)
        await model.confirm(); await model.load()
        XCTAssertEqual(LifecycleProtocol.state.requests.filter { $0.httpMethod == "PATCH" }.count, 1)
        await api.close()
    }
    func testConnectedMarkWritesOnlyTheBooleanOnce() async throws {
        let api = try client("success")
        let model = MarkConnectedModel(client: api, port: endpoint(3))
        await model.load(); XCTAssertTrue(model.canSave)
        await model.save(); XCTAssertTrue(model.saved)
        await model.save()
        let patches = LifecycleProtocol.state.requests.filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(patches.count, 1)
        let patch = try XCTUnwrap(patches.first)
        XCTAssertEqual(patch.value(forHTTPHeaderField: "If-Match"), "W/\"revision-1\"")
        let body = try XCTUnwrap(requestBody(patch))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["mark_connected"])
        XCTAssertEqual(object["mark_connected"] as? Bool, true)
        await api.close()
    }
    func testCabledPortAndLostMarkReplyDoNotCauseExtraPatches() async throws {
        for scenario in ["occupied", "lost"] {
            let api = try client(scenario)
            let model = MarkConnectedModel(client: api, port: endpoint(3))
            await model.load(); await model.save(); await model.save()
            XCTAssertFalse(model.saved)
            XCTAssertEqual(LifecycleProtocol.state.requests.filter { $0.httpMethod == "PATCH" }.count, scenario == "occupied" ? 0 : 1)
            await api.close()
        }
    }
}

private final class LifecycleProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URLRequest] = []
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
        func add(_ request: URLRequest) { lock.lock(); stored.append(request); lock.unlock() }
        func reset() { lock.lock(); stored = []; lock.unlock() }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        let scenario = url.host?.components(separatedBy: ".").first ?? "success"
        let patch = request.httpMethod == "PATCH"
        if patch && scenario == "lost" {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
        }
        var responseBody: [String: Any]
        if url.path == "/api/dcim/cables/7/" {
            func end(_ id: Int) -> [String: Any] {
                ["object_type": "dcim.interface", "object_id": id, "object": ["id": id, "name": "Port \(id)", "device": ["id": 301, "name": "Device"]]]
            }
            responseBody = ["id": 7, "a_terminations": [end(patch ? 3 : 1)], "b_terminations": [end(2)]]
        } else if url.path == "/api/dcim/devices/301/" {
            responseBody = ["id": 301, "name": "Device"]
        } else {
            responseBody = ["id": 3, "name": scenario == "renamed" ? "Changed" : "Port 3", "device": ["id": 301, "name": "Device"], "cable": scenario == "occupied" ? ["id": 9] : NSNull(), "_occupied": scenario == "occupied", "mark_connected": patch, "type": ["value": "1000base-t", "label": "1GE"]]
        }
        let changed = scenario == "conflict" && Self.state.requests.filter { $0.url?.path == "/api/dcim/cables/7/" }.count > 1
        let headers = ["Content-Type": "application/json", "ETag": changed ? "W/\"revision-2\"" : "W/\"revision-1\""]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers), let data = try? JSONSerialization.data(withJSONObject: responseBody) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
