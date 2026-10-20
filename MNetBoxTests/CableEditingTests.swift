import XCTest
@testable import MNetBox

final class CableEditingTests: XCTestCase {
    override func setUp() { CableEditProtocol.state.reset() }
    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CableEditProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private let target = TextEditTarget(collection: .cables, id: 7)
    private func endpoint(_ family: PortPanelFamily, id: Int = 1) -> CableEndpointSelection {
        .init(family: family, id: id, deviceID: 301, deviceName: "Core-switch", name: "Port \(id)")
    }

    // MARK: Console and power creation

    func testNativeCompatibilityMatrixIsSymmetric() {
        let allowed: Set<String> = ["interfaces-interfaces", "interfaces-front", "interfaces-rear", "front-front", "front-rear", "rear-rear",
                                    "console-consoleServer", "console-front", "console-rear", "consoleServer-front", "consoleServer-rear", "power-outlet"]
        let names: [PortPanelFamily: String] = [.interfaces: "interfaces", .front: "front", .rear: "rear", .console: "console", .consoleServer: "consoleServer", .power: "power", .outlet: "outlet"]
        for a in PortPanelFamily.allCases {
            for b in PortPanelFamily.allCases {
                let expected = allowed.contains("\(names[a]!)-\(names[b]!)") || allowed.contains("\(names[b]!)-\(names[a]!)")
                XCTAssertEqual(CableEndpointSelection.compatible(a, b), expected, "\(a) ↔ \(b)")
                XCTAssertEqual(CableEndpointSelection.compatible(a, b), CableEndpointSelection.compatible(b, a))
            }
        }
    }
    func testConsoleAndPowerPlansUseNativeObjectTypes() throws {
        let console = CableCreationPlan(a: endpoint(.console, id: 1), b: endpoint(.consoleServer, id: 2), label: "", type: "", status: "connected", color: "333333")
        let power = CableCreationPlan(a: endpoint(.power, id: 3), b: endpoint(.outlet, id: 4), label: "PSU1", type: "power", status: "planned", color: "333333")
        for (plan, types) in [(console, ["dcim.consoleport", "dcim.consoleserverport"]), (power, ["dcim.powerport", "dcim.poweroutlet"])] {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.validated())) as? [String: Any])
            XCTAssertEqual((body["a_terminations"] as? [[String: Any]])?.first?["object_type"] as? String, types[0])
            XCTAssertEqual((body["b_terminations"] as? [[String: Any]])?.first?["object_type"] as? String, types[1])
        }
    }
    func testIncompatibleFamiliesAreRejectedBeforeAnyRequest() {
        for (a, b) in [(PortPanelFamily.power, PortPanelFamily.power), (.console, .console), (.power, .interfaces), (.outlet, .front), (.console, .outlet)] {
            let plan = CableCreationPlan(a: endpoint(a, id: 1), b: endpoint(b, id: 2), label: "", type: "", status: "connected", color: "0088ff")
            XCTAssertThrowsError(try plan.validated(), "\(a) ↔ \(b)")
        }
    }

    // MARK: Field editing

    func testCableFieldsAreSupportedOnlyOnCables() {
        for field in [EditableTextField.label, .type, .color] {
            XCTAssertTrue(field.supports(.cables))
            XCTAssertFalse(field.supports(.devices))
        }
        XCTAssertTrue(EditableTextField.status.supports(.cables))
        XCTAssertFalse(EditableTextField.name.supports(.cables))
        XCTAssertEqual(EditableTextField.status.choices(for: .cables), ["connected", "planned", "decommissioning"])
        XCTAssertEqual(try target.path, "dcim/cables/7/")
    }
    func testEachFieldSendsOneValueWithPairedETag() async throws {
        for (field, value) in [(EditableTextField.label, "Uplink A"), (.status, "planned"), (.type, "cat6a"), (.color, "00aa66"), (.color, ""), (.description, "Rack 2"), (.length, "12.5"), (.lengthUnit, "ft")] {
            CableEditProtocol.state.reset()
            let api = try client(), snapshot = try await api.textSnapshot(for: target, field: field)
            let result = try await api.updateText(snapshot, to: value)
            XCTAssertEqual(result.object.value(for: field), value)
            let patches = CableEditProtocol.state.requests.filter { $0.httpMethod == "PATCH" }
            XCTAssertEqual(patches.count, 1)
            XCTAssertEqual(patches.first?.value(forHTTPHeaderField: "If-Match"), "W/\"cable-1\"")
            let body = try XCTUnwrap(patches.first.flatMap { CableEditProtocol.body($0) })
            XCTAssertEqual(Array(body.keys), [field.rawValue])
            XCTAssertEqual(body[field.rawValue] as? String, value)
        }
    }
    func testUnknownChoicesAndControlCharactersAreRejectedLocally() async throws {
        let api = try client()
        for (field, value) in [(EditableTextField.status, "active"), (.type, "fiber-magic"), (.color, "ff0000"), (.label, "line\nbreak")] {
            let snapshot = try await api.textSnapshot(for: target, field: field)
            do { _ = try await api.updateText(snapshot, to: value); XCTFail("Must reject \(field) = \(value)") }
            catch { XCTAssertNotNil(error as? APIError) }
        }
        XCTAssertFalse(CableEditProtocol.state.requests.contains { $0.httpMethod == "PATCH" })
    }
    func testDisplayValuesAreReadable() {
        XCTAssertEqual(EditableTextField.type.displayValue(""), L10n.text("Unspecified"))
        XCTAssertEqual(EditableTextField.color.displayValue("0088FF"), L10n.text("Blue"))
        XCTAssertEqual(EditableTextField.color.normalized(" 00AA66 "), "00aa66")
    }
}

private final class CableEditProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRequests: [URLRequest] = [], storedCable: [String: Any] = [:]
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storedRequests }
        var cable: [String: Any] { get { lock.lock(); defer { lock.unlock() }; return storedCable } set { lock.lock(); storedCable = newValue; lock.unlock() } }
        func add(_ request: URLRequest) { lock.lock(); storedRequests.append(request); lock.unlock() }
        func reset() {
            lock.lock(); storedRequests = []
            storedCable = ["id": 7, "display": "#7", "label": "LAN-7", "type": "cat6", "color": "0088ff", "status": ["value": "connected", "label": "Connected"],
                           "description": "", "comments": "", "length": "2.50", "length_unit": ["value": "m", "label": "Meters"], "a_terminations": [], "b_terminations": []]
            lock.unlock()
        }
    }
    static let state = State()
    static func body(_ request: URLRequest) -> [String: Any]? {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096), collected = Data()
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; collected.append(buffer, count: count) }
            data = collected
        }
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        var cable = Self.state.cable
        if request.httpMethod == "PATCH", let body = Self.body(request) {
            for (key, value) in body { cable[key] = (key == "status" || key == "length_unit") ? ["value": value, "label": (value as? String)?.capitalized ?? ""] : value }
            Self.state.cable = cable
        }
        let headers = ["Content-Type": "application/json", "ETag": "W/\"cable-1\""]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers),
              let data = try? JSONSerialization.data(withJSONObject: cable) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
