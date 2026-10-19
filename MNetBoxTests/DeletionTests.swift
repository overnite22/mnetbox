import XCTest
@testable import MNetBox

final class DeletionTests: XCTestCase {
    override func setUp() { DeleteProtocol.state.reset() }
    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeleteProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private let ip = DeletionTarget(collection: .ipAddresses, id: 10)
    func testAllFourCollectionsDeleteWithPairedETagAndNoBody() async throws {
        for collection in [DeletionTarget.Collection.prefixes, .ipAddresses, .physicalInterfaces, .virtualInterfaces] {
            DeleteProtocol.state.reset()
            let target = DeletionTarget(collection: collection, id: 10, parentID: collection.interfaceKind == nil ? nil : 301)
            let api = try client(), snapshot = try await api.deletionSnapshot(target)
            XCTAssertTrue(snapshot.blockers.isEmpty)
            try await api.deleteObject(snapshot)
            let writes = DeleteProtocol.state.requests.filter { $0.httpMethod == "DELETE" }
            XCTAssertEqual(writes.count, 1)
            XCTAssertEqual(writes.first?.url?.absoluteString, "https://example.test/api/" + (try target.path))
            XCTAssertEqual(writes.first?.value(forHTTPHeaderField: "If-Match"), "W/\"revision-1\"")
            XCTAssertNil(writes.first?.httpBody)
        }
    }
    func testNewDependencyOrChangedRevisionPreventsDelete() async throws {
        for mode in ["new-dependency", "conflict"] {
            DeleteProtocol.state.reset()
            let api = try client(), snapshot = try await api.deletionSnapshot(ip)
            DeleteProtocol.state.mode = mode
            do { try await api.deleteObject(snapshot); XCTFail("Must reject changed preview") }
            catch { XCTAssertEqual(error as? APIError, mode == "conflict" ? .conflict : .deletionBlocked) }
            XCTAssertFalse(DeleteProtocol.state.requests.contains { $0.httpMethod == "DELETE" })
        }
    }
    func testMissingFieldsWrongParentAndMissingETagFailClosed() async throws {
        for mode in ["missing-fields", "wrong-parent", "missing-etag"] {
            DeleteProtocol.state.reset(); DeleteProtocol.state.mode = mode
            let target = DeletionTarget(collection: .virtualInterfaces, id: 10, parentID: 301)
            do { _ = try await client().deletionSnapshot(target); XCTFail("Must reject incomplete identity or metadata") }
            catch { XCTAssertNotNil(error as? APIError) }
            XCTAssertFalse(DeleteProtocol.state.requests.contains { $0.httpMethod == "DELETE" })
        }
    }
    func testPrimaryReferenceOnSecondPageBlocksEvenIfUnassigned() async throws {
        DeleteProtocol.state.mode = "primary-page-two"
        let snapshot = try await client().deletionSnapshot(ip)
        XCTAssertTrue(snapshot.blockers.contains("Primary IP address"))
        XCTAssertTrue(DeleteProtocol.state.requests.contains { $0.url?.query?.contains("offset=1") == true })
        do { try await client().deleteObject(snapshot); XCTFail("Must reject primary IP") }
        catch { XCTAssertEqual(error as? APIError, .deletionBlocked) }
        XCTAssertFalse(DeleteProtocol.state.requests.contains { $0.httpMethod == "DELETE" })
    }
    @MainActor func testExactIDConfirmationAndOneAttemptAfterUncertainResponse() async throws {
        DeleteProtocol.state.mode = "uncertain"
        let model = DeletionModel(client: try client(), target: ip)
        await model.load()
        for text in ["", "010", " 10", "11"] { model.confirmation = text; XCTAssertFalse(model.canDelete) }
        model.confirmation = "10"; XCTAssertTrue(model.canDelete)
        await model.delete(); XCTAssertTrue(model.attempted); XCTAssertFalse(model.deleted)
        await model.delete(); await model.checkCurrent(); await model.delete()
        XCTAssertFalse(model.deleted)
        XCTAssertFalse(model.canDelete)
        XCTAssertTrue(model.errorMessage?.contains("does not prove deletion") == true || model.errorMessage?.contains("ne prouve") == true)
        XCTAssertEqual(DeleteProtocol.state.requests.filter { $0.httpMethod == "DELETE" }.count, 1)
    }
    func testForbiddenConflictAndUnexpectedSuccessAreNeverRetried() async throws {
        for mode in ["forbidden", "server-conflict", "unexpected-success"] {
            DeleteProtocol.state.reset()
            let api = try client(), snapshot = try await api.deletionSnapshot(ip)
            DeleteProtocol.state.mode = mode
            do { try await api.deleteObject(snapshot); XCTFail("Must not infer deletion") }
            catch { XCTAssertEqual(error as? APIError, mode == "forbidden" ? .forbidden : mode == "server-conflict" ? .conflict : .invalidResponse) }
            XCTAssertEqual(DeleteProtocol.state.requests.filter { $0.httpMethod == "DELETE" }.count, 1)
        }
    }
    func testCanceledTaskNeverSendsDelete() async throws {
        let api = try client(), snapshot = try await api.deletionSnapshot(ip)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; try await api.deleteObject(snapshot) }
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(DeleteProtocol.state.requests.contains { $0.httpMethod == "DELETE" })
    }
    func testPhysicalDependenciesAndPrefixContentsAreBlocked() async throws {
        for collection in [DeletionTarget.Collection.physicalInterfaces, .prefixes] {
            DeleteProtocol.state.reset(); DeleteProtocol.state.mode = "blocked"
            let target = DeletionTarget(collection: collection, id: 10, parentID: collection == .physicalInterfaces ? 301 : nil)
            let snapshot = try await client().deletionSnapshot(target)
            XCTAssertFalse(snapshot.blockers.isEmpty)
            do { try await client().deleteObject(snapshot); XCTFail("Expected dependency block") }
            catch { XCTAssertEqual(error as? APIError, .deletionBlocked) }
            XCTAssertFalse(DeleteProtocol.state.requests.contains { $0.httpMethod == "DELETE" })
        }
    }
}

private final class DeleteProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var storedMode = "", storedRequests: [URLRequest] = [], absent = false
        var mode: String { get { lock.lock(); defer { lock.unlock() }; return storedMode } set { lock.lock(); storedMode = newValue; lock.unlock() } }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return storedRequests }
        var missing: Bool { lock.lock(); defer { lock.unlock() }; return absent }
        func markMissing() { lock.lock(); absent = true; lock.unlock() }
        func add(_ request: URLRequest) { lock.lock(); storedRequests.append(request); lock.unlock() }
        func reset() { lock.lock(); storedMode = ""; storedRequests = []; absent = false; lock.unlock() }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        let mode = Self.state.mode
        var status = 200, body: [String: Any] = ["count": 0, "next": NSNull(), "previous": NSNull(), "results": []]
        var headers = ["Content-Type": "application/json", "ETag": mode == "conflict" ? "W/\"revision-2\"" : "W/\"revision-1\""]
        if mode == "missing-etag" { headers.removeValue(forKey: "ETag") }
        var empty = false
        if request.httpMethod == "DELETE" {
            status = mode == "forbidden" ? 403 : mode == "server-conflict" ? 412 : mode == "unexpected-success" ? 200 : mode == "uncertain" ? 503 : 204
            empty = status == 204
            if mode == "uncertain" { Self.state.markMissing() }
        } else if url.lastPathComponent == "10" {
            if Self.state.missing { status = 404; body = [:] }
            else if url.path.contains("/prefixes/") {
                body = ["id": 10, "prefix": "203.0.113.0/24", "vrf": NSNull(), "children": mode == "blocked" ? 1 : 0]
            } else if url.path.contains("/ip-addresses/") {
                body = ["id": 10, "address": "203.0.113.10/24", "vrf": NSNull(), "assigned_object_type": NSNull(), "assigned_object_id": NSNull(), "assigned_object": NSNull(), "nat_inside": NSNull(), "nat_outside": []]
            } else {
                let physical = url.path.contains("/dcim/")
                body = FixtureDeletions.completeInterface(["id": 10, "name": "eth9", physical ? "device" : "virtual_machine": ["id": mode == "wrong-parent" ? 999 : 301, "name": "Parent"]], physical: physical)
                if mode == "blocked" { body["cable"] = ["id": 99, "display": "Cable"] }
                if mode == "missing-fields" { body.removeValue(forKey: "parent") }
            }
        } else if mode == "new-dependency", url.lastPathComponent == "ip-addresses", url.query?.contains("nat_inside_id") == true {
            body["count"] = 1; body["results"] = [["id": 20]]
        } else if mode == "primary-page-two", url.lastPathComponent == "devices", url.query?.contains("q=") == true {
            let second = url.query?.contains("offset=1") == true
            body = ["count": 2, "next": second ? NSNull() : "https://example.test/api/dcim/devices/?q=203.0.113.10&ordering=id&limit=50&offset=1" as Any, "previous": NSNull(), "results": [["id": second ? 302 : 301, "primary_ip4": second ? ["id": 10, "address": "203.0.113.10/24"] : NSNull() as Any, "primary_ip6": NSNull()]]]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: empty ? Data() : data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
