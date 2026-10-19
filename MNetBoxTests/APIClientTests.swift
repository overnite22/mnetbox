import XCTest
@testable import MNetBox

final class APIClientTests: XCTestCase {
    struct Item: Codable, Sendable { let id: Int }
    func credential(_ kind: TokenKind = .legacy) throws -> Credential {
        Credential(configuration: try NetBoxConfiguration("https://example.test/netbox"), token: "test-placeholder", kind: kind)
    }
    func client() throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return APIClient(credential: try credential(), session: URLSession(configuration: config))
    }
    func testURLValidationAndNormalization() throws {
        XCTAssertEqual(try NetBoxConfiguration("https://example.test/netbox/api/").baseURL.absoluteString, "https://example.test/netbox/api/")
        for value in ["http://example.test", "https://user:pass@example.test", "https://example.test?token=x", "https://example.test/#fragment"] {
            XCTAssertThrowsError(try NetBoxConfiguration(value))
        }
        let config = try credential().configuration
        for path in ["https://evil.test/api/", "/outside/", "../admin/", "https://example.test/netbox/api/%2e%2e/admin/"] {
            XCTAssertThrowsError(try config.validatedURL(path))
        }
    }
    func testRequestAndAuthorization() throws {
        for kind in TokenKind.allCases {
            let request = try RequestBuilder(credential: credential(kind)).get("dcim/sites/", query: [.init(name: "q", value: "rack & site")])
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), kind == .legacy ? "Token test-placeholder" : "Bearer test-placeholder")
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: true)?.queryItems?.first?.value, "rack & site")
            XCTAssertNil(request.httpBody)
        }
        let bad = Credential(configuration: try credential().configuration, token: "bad\r\nheader", kind: .legacy)
        XCTAssertThrowsError(try RequestBuilder(credential: bad).get("status/"))
    }
    func testEncodedCIDRQueryIsAllowedButEncodedPathTraversalIsRejected() throws {
        let config = try credential().configuration
        let url = try config.validatedURL("https://example.test/netbox/api/ipam/prefixes/?q=192%2E0%2E2%2E0%2F24&offset=50")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "192.0.2.0/24")
        XCTAssertThrowsError(try config.validatedURL("https://example.test/netbox/api/ipam%2Fprefixes/"))
        XCTAssertThrowsError(try config.validatedURL("https://example.test/netbox/api/%2E%2E/admin/?q=192.0.2.0%2F24"))
    }
    func testPaginationDecodingAndETag() async throws {
        let api = try client()
        let page: NetBoxPage<Item> = try await api.get("page/")
        XCTAssertEqual(page.count, 2)
        XCTAssertEqual(page.results.first?.id, 1)
        let next = try XCTUnwrap(page.next)
        let second: NetBoxPage<Item> = try await api.get(next)
        XCTAssertEqual(second.results.first?.id, 2)
        XCTAssertNil(second.next)
        let headers = try await api.ifMatchHeaders(for: "page/")
        XCTAssertEqual(headers["If-Match"], "\"revision-1\"")
        do {
            let _: Item = try await api.get("https://evil.test/api/")
            XCTFail("Cross-origin next URL must be rejected")
        } catch { XCTAssertEqual(error as? APIError, .invalidURL) }
    }
    func testErrors() async throws {
        let api = try client()
        for (path, expected) in [("401/", APIError.unauthorized), ("403/", .forbidden), ("412/", .conflict), ("invalid/", .decoding), ("html/", .invalidResponse), ("400/", .http(400, ["name": ["Required"]]))] {
            do { let _: Item = try await api.get(path); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? APIError, expected) }
        }
    }
    func testMissingAndWeakETagsFailClosed() async throws {
        let api = try client()
        for path in ["plain/", "weak/"] {
            let _: Item = try await api.get(path)
            do { _ = try await api.ifMatchHeaders(for: path); XCTFail("Missing strong ETag") }
            catch { XCTAssertEqual(error as? APIError, .missingETag) }
        }
    }
    func testCancellation() async throws {
        let api = try client()
        let task = Task { () throws -> Item in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await api.get("plain/")
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testValidation() async throws { try await client().validateConnection() }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.lastPathComponent
        let status = Int(path) ?? 200
        var headers = ["Content-Type": path == "html" ? "text/html" : "application/json"]
        var body = "{\"id\":1}"
        switch path {
        case "status": body = "{\"netbox-version\":\"4.4.0\"}"
        case "authentication-check": body = "{\"id\":1,\"username\":\"fixture-user\"}"
        case "sites": body = "{\"count\":0,\"next\":null,\"previous\":null,\"results\":[]}"
        case "page":
            headers["ETag"] = "\"revision-1\""
            body = "{\"count\":2,\"next\":\"https://example.test/netbox/api/second/\",\"previous\":null,\"results\":[{\"id\":1}]}"
        case "second": body = "{\"count\":2,\"next\":null,\"previous\":null,\"results\":[{\"id\":2}]}"
        case "weak": headers["ETag"] = "W/\"revision-1\""
        case "invalid": body = "not JSON"
        case "400": body = "{\"name\":[\"Required\"]}"
        default: break
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
