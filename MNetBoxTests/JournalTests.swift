import XCTest
@testable import MNetBox

final class JournalTests: XCTestCase {
    override func setUp() { JournalProtocol.state.reset() }
    private func client() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JournalProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
    private let target = JournalTarget(kind: .devices, id: 301)

    func testDraftValidationAndPayload() throws {
        XCTAssertThrowsError(try JournalDraft(target: target, kind: "info", comments: "   ").validated())
        XCTAssertThrowsError(try JournalDraft(target: target, kind: "critical", comments: "x").validated())
        XCTAssertThrowsError(try JournalDraft(target: JournalTarget(kind: .devices, id: 0), comments: "x").validated())
        let draft = try JournalDraft(target: target, kind: "warning", comments: "  Fan replaced  ").validated()
        XCTAssertEqual(draft.comments, "Fan replaced")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["assigned_object_type", "assigned_object_id", "kind", "comments"])
        XCTAssertEqual(body["assigned_object_type"] as? String, "dcim.device")
        XCTAssertEqual(JournalTarget(kind: .virtualMachines, id: 1).objectType, "virtualization.virtualmachine")
    }
    func testListingIsScopedAndRejectsForeignEntries() async throws {
        let page = try await client().journalEntries(target, next: nil)
        XCTAssertEqual(page.results.map(\.id), [12, 11])
        XCTAssertEqual(page.results.first?.createdText, "2026-10-20 09:15")
        let query = JournalProtocol.state.requests.first?.url?.query ?? ""
        XCTAssertTrue(query.contains("assigned_object_type=dcim.device") && query.contains("assigned_object_id=301"))
        JournalProtocol.state.mode = "foreign"
        do { _ = try await client().journalEntries(target, next: nil); XCTFail("Must reject another object's entry") }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }
    func testCreationIsOnePostWithVerifiedReply() async throws {
        let draft = JournalDraft(target: target, kind: "success", comments: "Cabling checked")
        let entry = try await client().createJournalEntry(draft)
        XCTAssertEqual(entry.id, 13)
        XCTAssertEqual(JournalProtocol.state.requests.filter { $0.httpMethod == "POST" }.count, 1)
        JournalProtocol.state.reset(); JournalProtocol.state.mode = "wrong-reply"
        do { _ = try await client().createJournalEntry(draft); XCTFail("Must reject a mismatched reply") }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        XCTAssertEqual(JournalProtocol.state.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
}

private final class JournalProtocol: URLProtocol, @unchecked Sendable {
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
    private static func entry(_ id: Int, object: Int = 301, kind: String = "info", comments: String) -> [String: Any] {
        ["id": id, "assigned_object_type": "dcim.device", "assigned_object_id": object, "created": "2026-10-20T09:15:42.123456Z",
         "created_by": ["id": 1, "display": "fixture-user"], "kind": ["value": kind, "label": kind.capitalized], "comments": comments]
    }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.state.add(request)
        let mode = Self.state.mode
        var status = 200
        var body: Any
        if request.httpMethod == "POST" {
            status = 201
            body = Self.entry(13, kind: mode == "wrong-reply" ? "info" : "success", comments: "Cabling checked")
        } else if url.path == "/api/extras/journal-entries/" {
            body = ["count": 2, "next": NSNull(), "previous": NSNull(),
                    "results": [Self.entry(12, comments: "Rebooted"), Self.entry(11, object: mode == "foreign" ? 999 : 301, comments: "Installed")]]
        } else {
            body = ["id": Int(url.lastPathComponent) ?? 0, "name": "Core-switch"]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
