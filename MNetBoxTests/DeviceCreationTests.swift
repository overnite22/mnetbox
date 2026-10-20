import XCTest
@testable import MNetBox

final class DeviceCreationTests: XCTestCase {
    override func setUp() { DeviceCreationProtocol.state.reset() }
    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeviceCreationProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private var plan: DeviceCreationPlan {
        var plan = DeviceCreationPlan()
        plan.name = " edge-02 "; plan.deviceType = .init(id: 7, title: "Switch 48"); plan.role = .init(id: 4, title: "Access")
        plan.site = .init(id: 101, title: "Example Paris"); plan.rack = .init(id: 201, title: "Rack-A"); plan.position = 12; plan.face = "front"
        plan.serial = "SN-1"; return plan
    }
    private var posts: [URLRequest] { DeviceCreationProtocol.state.requests.filter { $0.httpMethod == "POST" } }

    func testPayloadSendsIDsAndNullAssetTag() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.validated())) as? [String: Any])
        XCTAssertEqual(body["name"] as? String, "edge-02")
        XCTAssertEqual(body["device_type"] as? Int, 7); XCTAssertEqual(body["role"] as? Int, 4); XCTAssertEqual(body["site"] as? Int, 101)
        XCTAssertEqual(body["rack"] as? Int, 201); XCTAssertEqual(body["position"] as? Int, 12); XCTAssertEqual(body["face"] as? String, "front")
        XCTAssertTrue(body["asset_tag"] is NSNull); XCTAssertTrue(body["tenant"] is NSNull)
    }
    func testLocalValidation() {
        var missing = plan; missing.role = nil
        XCTAssertThrowsError(try missing.validated())
        var noFace = plan; noFace.face = ""
        XCTAssertThrowsError(try noFace.validated())
        var outOfRange = plan; outOfRange.position = 0
        XCTAssertThrowsError(try outOfRange.validated())
        var noRack = plan; noRack.rack = nil
        XCTAssertNil(try noRack.validated().position, "Position is dropped without a rack")
        var badStatus = plan; badStatus.status = "unknown"
        XCTAssertThrowsError(try badStatus.validated())
    }
    func testSuccessfulCreationIsOnePost() async throws {
        let reply = try await client().createDevice(plan)
        XCTAssertEqual(reply.id, 9301); XCTAssertEqual(posts.count, 1)
        XCTAssertTrue(DeviceCreationProtocol.state.requests.contains { $0.url?.query?.contains("name=edge-02") == true })
    }
    func testDuplicateNameRackInOtherSiteAndWrongReplyNeverRetry() async throws {
        for mode in ["duplicate", "foreign-rack", "wrong-reply"] {
            DeviceCreationProtocol.state.reset(); DeviceCreationProtocol.state.mode = mode
            do { _ = try await client().createDevice(plan); XCTFail("Must fail: \(mode)") }
            catch { XCTAssertEqual(error as? APIError, mode == "duplicate" ? .duplicateDevice : mode == "foreign-rack" ? .invalidReference : .invalidResponse, mode) }
            XCTAssertEqual(posts.count, mode == "wrong-reply" ? 1 : 0, mode)
        }
    }
}

private final class DeviceCreationProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var storedMode = "", storedRequests: [URLRequest] = []
        var mode: String { get { lock.lock(); defer { lock.unlock() }; return storedMode } set { lock.lock(); storedMode = newValue; lock.unlock() } }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storedRequests }
        func add(_ request: URLRequest) { lock.lock(); storedRequests.append(request); lock.unlock() }
        func reset() { lock.lock(); storedMode = ""; storedRequests = []; lock.unlock() }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        // URL.path drops the trailing slash; URLComponents keeps the exact API path.
        let mode = Self.state.mode, path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? url.path
        var status = 200
        var body: Any = ["count": 0, "next": NSNull(), "previous": NSNull(), "results": []]
        if request.httpMethod == "POST" {
            status = 201
            body = ["id": 9301, "name": "edge-02", "site": ["id": 101], "device_type": ["id": 7], "role": ["id": mode == "wrong-reply" ? 5 : 4],
                    "rack": ["id": 201], "status": ["value": "active", "label": "Active"]]
        } else if path == "/api/dcim/racks/201/" {
            body = ["id": 201, "site": ["id": mode == "foreign-rack" ? 999 : 101]]
        } else if let id = Int(url.lastPathComponent) {
            body = ["id": id, "name": "Reference \(id)"]
        } else if path == "/api/dcim/devices/", mode == "duplicate", url.query?.contains("name=") == true {
            body = ["count": 1, "next": NSNull(), "previous": NSNull(), "results": [["id": 300]]]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
