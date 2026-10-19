import XCTest
@testable import MNetBox

final class CableDeletionTests: XCTestCase {
    override func setUp() { CableDeleteProtocol.state.reset() }
    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CableDeleteProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private let target = DeletionTarget(collection: .cables, id: 7)
    private var deletes: [URLRequest] { CableDeleteProtocol.state.requests.filter { $0.httpMethod == "DELETE" } }

    func testReviewedCableDeletesOnceWithPairedETagAndNoBody() async throws {
        let api = try client(), snapshot = try await api.deletionSnapshot(target)
        XCTAssertTrue(snapshot.blockers.isEmpty)
        XCTAssertEqual(snapshot.object.title, "LAN-7")
        XCTAssertEqual(snapshot.object.cableEnds, ["A · sw1 · eth1", "B · patch1 · Front 3"])
        try await api.deleteObject(snapshot)
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.url?.absoluteString, "https://example.test/api/dcim/cables/7/")
        XCTAssertEqual(deletes.first?.value(forHTTPHeaderField: "If-Match"), "W/\"revision-1\"")
        XCTAssertNil(deletes.first?.httpBody)
    }
    func testChangedTerminationsOrRevisionSinceReviewAreConflicts() async throws {
        for mode in ["moved-end", "relabelled", "revision"] {
            CableDeleteProtocol.state.reset()
            let api = try client(), snapshot = try await api.deletionSnapshot(target)
            CableDeleteProtocol.state.mode = mode
            do { try await api.deleteObject(snapshot); XCTFail("Must reject a cable changed since review: \(mode)") }
            catch { XCTAssertEqual(error as? APIError, .conflict, mode) }
            XCTAssertTrue(deletes.isEmpty, mode)
        }
    }
    func testIncompleteOrMismatchedCableFailsClosed() async throws {
        for mode in ["missing-side", "wrong-id", "invalid-end", "missing-etag"] {
            CableDeleteProtocol.state.reset(); CableDeleteProtocol.state.mode = mode
            do { _ = try await client().deletionSnapshot(target); XCTFail("Must reject: \(mode)") }
            catch { XCTAssertNotNil(error as? APIError, mode) }
            XCTAssertTrue(deletes.isEmpty, mode)
        }
    }
    func testCableTargetPathAndLabel() throws {
        XCTAssertEqual(try target.path, "dcim/cables/7/")
        XCTAssertEqual(DeletionTarget.Collection.cables.titleKey, "Cable")
        XCTAssertThrowsError(try DeletionTarget(collection: .cables, id: 0).path)
    }
    @MainActor func testExactIDConfirmationAndSingleAttemptAfterUncertainReply() async throws {
        CableDeleteProtocol.state.mode = "uncertain"
        let model = DeletionModel(client: try client(), target: target)
        await model.load()
        for text in ["", "07", "70", " 7"] { model.confirmation = text; XCTAssertFalse(model.canDelete) }
        model.confirmation = "7"; XCTAssertTrue(model.canDelete)
        await model.delete(); await model.delete()
        XCTAssertTrue(model.attempted); XCTAssertFalse(model.deleted)
        XCTAssertEqual(deletes.count, 1)
    }
}

private final class CableDeleteProtocol: URLProtocol, @unchecked Sendable {
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
    private static func cable(_ mode: String) -> [String: Any] {
        let a: [String: Any] = ["object_type": "dcim.interface", "object_id": mode == "invalid-end" ? 0 : 11,
                                "object": ["id": mode == "invalid-end" ? 0 : 11, "name": "eth1", "display": "eth1", "device": ["id": 301, "name": "sw1", "display": "sw1"]]]
        let b: [String: Any] = ["object_type": "dcim.frontport", "object_id": mode == "moved-end" ? 23 : 22,
                                "object": ["id": mode == "moved-end" ? 23 : 22, "name": "Front 3", "display": "Front 3", "device": ["id": 302, "name": "patch1", "display": "patch1"]]]
        var row: [String: Any] = ["id": mode == "wrong-id" ? 8 : 7, "display": "#7", "label": mode == "relabelled" ? "LAN-8" : "LAN-7", "type": "cat6",
                                  "status": ["value": "connected", "label": "Connected"], "color": "0000ff",
                                  "tenant": NSNull(), "bundle": NSNull(), "a_terminations": [a], "b_terminations": [b]]
        if mode == "missing-side" { row.removeValue(forKey: "b_terminations") }
        return row
    }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        let mode = Self.state.mode
        var status = 200, body: [String: Any] = Self.cable(mode)
        var headers = ["Content-Type": "application/json", "ETag": mode == "revision" ? "W/\"revision-2\"" : "W/\"revision-1\""]
        if mode == "missing-etag" { headers.removeValue(forKey: "ETag") }
        var empty = false
        if request.httpMethod == "DELETE" {
            status = mode == "uncertain" ? 503 : 204
            empty = status == 204
            body = [:]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: empty ? Data() : data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
