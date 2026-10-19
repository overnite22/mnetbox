import XCTest
@testable import MNetBox

final class CableTraceTests: XCTestCase {
    private let base = URL(string: "https://example.test/api/")!
    private func decode(_ text: String) throws -> CableTrace { try JSONDecoder().decode(CableTrace.self, from: Data(text.utf8)) }
    func testMultiCablePathAndInternalPortStepRetainEndpoints() throws {
        var trace = try decode(CableTraceFixture.body()); try trace.validate(apiURL: base, interfaceID: 501)
        XCTAssertEqual(trace.segments.count, 3); XCTAssertNil(trace.segments[1].cable)
        XCTAssertEqual(trace.segments[0].far[0].kind, "rear-ports")
        XCTAssertEqual(trace.segments[1].far[0].kind, "front-ports")
        XCTAssertEqual(trace.segments[2].far[0].id, 502)
    }
    func testEmptyAndPartialPathsRemainReadable() throws {
        var empty = try decode("[]"); try empty.validate(apiURL: base, interfaceID: 1)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CableTraceFixture.body().utf8)) as? [[Any]])
        rows = [rows[0]]; rows[0][2] = NSNull()
        var trace = try JSONDecoder().decode(CableTrace.self, from: JSONSerialization.data(withJSONObject: rows))
        try trace.validate(apiURL: base, interfaceID: 501); XCTAssertTrue(trace.segments[0].far.isEmpty)
    }
    func testWrongOriginTypeIdentityAndRepeatedCableFailClosed() throws {
        for text in [CableTraceFixture.body().replacingOccurrences(of: "https://example.test/api/dcim/interfaces/501/", with: "https://evil.test/api/dcim/interfaces/501/"), CableTraceFixture.body().replacingOccurrences(of: "/interfaces/501/", with: "/devices/501/"), CableTraceFixture.body().replacingOccurrences(of: "\"id\":702", with: "\"id\":701")] {
            var trace = try decode(text); XCTAssertThrowsError(try trace.validate(apiURL: base, interfaceID: 501))
        }
        var trace = try decode(CableTraceFixture.body()); XCTAssertThrowsError(try trace.validate(apiURL: base, interfaceID: 999))
    }
    func testMalformedTupleAndStepLimitRejectUnboundedPaths() throws {
        for text in ["[[[],null,[]]]", "[[[],null,[],null]]", "[[{},null,[]]]"] { XCTAssertThrowsError(try decode(text)) }
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CableTraceFixture.body().utf8)) as? [[Any]])
        let many = Array(repeating: rows[0], count: 65)
        XCTAssertThrowsError(try JSONDecoder().decode(CableTrace.self, from: JSONSerialization.data(withJSONObject: many)))
    }
    func testNativeEmptyLinksRawCableChoicesAndCircuitTermination() throws {
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CableTraceFixture.body().utf8)) as? [[Any]])
        rows = [rows[0]]
        rows[0][2] = [["id": 42, "url": "https://example.test/api/circuits/circuit-terminations/42/", "display": "WAN A"]]
        var trace = try JSONDecoder().decode(CableTrace.self, from: JSONSerialization.data(withJSONObject: rows))
        try trace.validate(apiURL: base, interfaceID: 501)
        XCTAssertEqual(trace.segments[0].cable?.status?.value, "connected")
        XCTAssertEqual(trace.segments[0].far[0].kind, "circuit-terminations")
        XCTAssertNil(trace.segments[0].far[0].device)
        rows[0][1] = []; rows[0][2] = []
        trace = try JSONDecoder().decode(CableTrace.self, from: JSONSerialization.data(withJSONObject: rows))
        try trace.validate(apiURL: base, interfaceID: 501); XCTAssertNil(trace.segments[0].cable)
        rows[0][1] = [1]
        XCTAssertThrowsError(try JSONDecoder().decode(CableTrace.self, from: JSONSerialization.data(withJSONObject: rows)))
    }
    func testTypedAPIUsesGetAndFixedTraceEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TraceProtocol.self]
        let api = APIClient(credential: .init(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
        let trace = try await api.cableTrace(interfaceID: 501); XCTAssertEqual(trace.segments.count, 3)
        do { _ = try await api.cableTrace(interfaceID: 0); XCTFail("Invalid ID") } catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        await api.close()
    }
}
private final class TraceProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET", request.value(forHTTPHeaderField: "Authorization") == "Token test-placeholder", let url = request.url, let reply = CableTraceFixture.response(url), let http = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type":"application/json"]) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
