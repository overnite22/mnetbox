import XCTest
@testable import MNetBox

@MainActor final class NetBoxImageTests: XCTestCase {
    private func api(_ host: String = "example.test") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://" + host), token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    func testMediaPolicyConfinesOriginPathAndDropsAuthentication() throws {
        let policy = NetBoxImagePolicy(apiURL: try NetBoxConfiguration("https://example.test/netbox").baseURL)
        let good = try policy.url("https://example.test/netbox/media/images/photo%20%C3%A9.png")
        let request = try policy.request(good)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        for url in ["http://example.test/netbox/media/a.png", "https://other.test/netbox/media/a.png", "https://example.test/api/a", "https://example.test/media/a.png", "https://user:password@example.test/netbox/media/a.png", "https://example.test/netbox/media/a.png?token=synthetic", "https://example.test/netbox/media/%2e%2e/a.png", "https://example.test/netbox/media/%252e%252e/a.png", "https://example.test/netbox/media/a.png#x"] { XCTAssertThrowsError(try policy.url(url)) }
    }
    func testAuthenticatedMediaConfinesBothTokenKindsAndNativeDirectories() throws {
        let configuration = try NetBoxConfiguration("https://example.test/netbox")
        let policy = NetBoxImagePolicy(apiURL: configuration.baseURL)
        for kind in TokenKind.allCases {
            let credential = Credential(configuration: configuration, token: "test-placeholder", kind: kind)
            for folder in ["image-attachments", "devicetype-images"] {
                let request = try policy.request(policy.url("https://example.test/netbox/media/\(folder)/photo%20%C3%A9.png"), credential: credential)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "\(kind == .legacy ? "Token" : "Bearer") test-placeholder")
                XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            }
            for path in ["plugin/image.png", "image-attachments-other/a.png", "a.png"] {
                XCTAssertThrowsError(try policy.request(policy.url("https://example.test/netbox/media/\(path)"), credential: credential))
            }
            let other = Credential(configuration: try NetBoxConfiguration("https://other.test"), token: "test-placeholder", kind: kind)
            XCTAssertThrowsError(try policy.request(policy.url("https://example.test/netbox/media/image-attachments/a.png"), credential: other))
        }
    }
    func testRasterResponseAndPixelBoundsRejectUnsafeFormats() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/media/a.png"))
        for (status, type, bytes) in [(200, "image/svg+xml", "10"), (200, "text/html", "10"), (403, "image/png", "10"), (200, "image/png", String(NetBoxImagePolicy.byteLimit + 1))] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type, "Content-Length": bytes])); XCTAssertThrowsError(try NetBoxImagePolicy.validateResponse(response))
        }
        XCTAssertTrue(NetBoxImagePolicy.validPixels(NetBoxImageFixture.png)); XCTAssertFalse(NetBoxImagePolicy.validPixels(Data("<html>Login</html>".utf8)))
        XCTAssertFalse(NetBoxImagePolicy.validPixels(Data(count: NetBoxImagePolicy.byteLimit + 1)))
    }
    func testAutomaticCatalogIncludesExactAttachmentAndTypeFaces() async throws {
        let api = try api(), catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: 1)
        XCTAssertEqual(catalog.images.map(\.id), ["attachment-81", "type-1-Front"]); XCTAssertFalse(catalog.unavailable)
        let loader = await api.imageLoader(), data = try await loader.data(catalog.images[0].url)
        XCTAssertTrue(NetBoxImagePolicy.validPixels(data))
        let model = NetBoxImageModel(); await model.load(catalog.images[0], loader: loader); XCTAssertNotNil(model.image); XCTAssertFalse(model.failed)
        await api.close()
    }
    func testWrongParentExternalMediaAndForbiddenCatalogRemainIndependentOfDevice() async throws {
        for host in ["wrongparent.test", "external.test", "forbidden.test"] {
            let api = try api(host), catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil)
            XCTAssertTrue(catalog.images.isEmpty); XCTAssertTrue(catalog.unavailable)
            let device = try await InventoryService(client: api, kind: .devices).detail(id: 301); XCTAssertEqual(device.id, 301)
            await api.close()
        }
    }
    func testProtectedMediaReceivesConfinedTokenButNeverBrowserCookies() async throws {
        let api = try api(), loader = await api.imageLoader()
        do { _ = try await loader.data(try XCTUnwrap(URL(string: "https://example.test/media/image-attachments/forbidden.png"))); XCTFail("Protected media") } catch { XCTAssertEqual(error as? APIError, .invalidImage) }
        let ref = NetBoxImageReference(id: "test", title: "Protected image", url: try XCTUnwrap(URL(string: "https://example.test/media/image-attachments/forbidden.png")))
        let model = NetBoxImageModel(); await model.load(ref, loader: loader); XCTAssertNil(model.image); XCTAssertTrue(model.failed)
        await api.close()
    }
}
private final class ImageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path.hasPrefix("/media/") {
            let invalid = request.value(forHTTPHeaderField: "Authorization") != "Bearer test-placeholder" || request.value(forHTTPHeaderField: "Cookie") != nil || url.lastPathComponent == "forbidden.png"
            deliver(url, invalid ? 403 : 200, "image/png", invalid ? Data() : NetBoxImageFixture.png); return
        }
        if url.host == "forbidden.test", url.path.contains("image-attachments") { deliver(url, 403, "application/json", Data("{}".utf8)); return }
        if let reply = NetBoxImageFixture.response(url) {
            var text = reply.1.replacingOccurrences(of: "https://example.test", with: "https://" + (url.host ?? "example.test"))
            if url.host == "external.test" { text = text.replacingOccurrences(of: "https://external.test/media", with: "https://other.test/media") }
            if url.host == "wrongparent.test", var row = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], var images = row["results"] as? [[String: Any]] { images[0]["parent"] = ["id": 999]; row["results"] = images; text = (try? JSONSerialization.data(withJSONObject: row)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
            deliver(url, reply.0, "application/json", Data(text.utf8)); return
        }
        if let reply = InventoryFixture.response(url) { deliver(url, reply.0, "application/json", Data(reply.1.utf8)); return }
        deliver(url, 404, "application/json", Data("{}".utf8))
    }
    private func deliver(_ url: URL, _ status: Int, _ mime: String, _ data: Data) {
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime, "Content-Length": String(data.count)]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
