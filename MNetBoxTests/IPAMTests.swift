#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class IPAMTests: XCTestCase {
    private func service(_ kind: IPAMKind = .prefixes, host: String = "example.test") throws -> IPAMService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [IPAMProtocol.self]
        return IPAMService(client: APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(host)"),
                                                                    token: "test-placeholder", kind: .legacy),
                                            session: URLSession(configuration: config)), kind: kind)
    }

    func testListsPaginateAndRefreshResetsPages() async throws {
        let service = try service()
        let model = IPAMListModel(service: service)
        await model.reload(query: IPAMQuery())
        XCTAssertEqual(model.objects.map(\.id), [1, 2])
        XCTAssertEqual(model.total, 3)
        XCTAssertNotNil(model.next)
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [1, 2, 3])
        XCTAssertNil(model.next)
        await model.reload(query: IPAMQuery())
        XCTAssertEqual(model.objects.map(\.id), [1, 2])
        await service.client.close()
    }

    func testServerSearchFamilyAndStatusFilters() async throws {
        let service = try service()
        let model = IPAMListModel(service: service)
        await model.reload(query: IPAMQuery(search: "IPv6", family: "6", status: "active"))
        XCTAssertEqual(model.objects.map(\.id), [2])
        await model.reload(query: IPAMQuery(status: "reserved"))
        XCTAssertEqual(model.objects.map(\.id), [3])
        await model.reload(query: IPAMQuery(search: "no matches"))
        XCTAssertTrue(model.objects.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        await service.client.close()
    }

    func testPrefixAndIPDetailsDecodeNullableRelations() async throws {
        let prefixes = try service()
        let prefix = try await prefixes.detail(id: 2)
        XCTAssertEqual(prefix.title, "2001:db8::/64")
        XCTAssertEqual(prefix.family?.value, 6)
        XCTAssertNil(prefix.vrf)
        XCTAssertEqual(prefix.role?.text, "LAN")
        let addresses = try service(.ipAddresses)
        let address = try await addresses.detail(id: 11)
        XCTAssertEqual(address.title, "192.0.2.10/24")
        XCTAssertEqual(address.dnsName, "host.example.test")
        XCTAssertEqual(address.assignedObject?.text, "eth0")
        XCTAssertNil(address.role)
        await prefixes.client.close()
        await addresses.client.close()
    }

    func testPaginationRejectsExternalOrWrongCollectionLinks() async throws {
        let service = try service()
        for next in ["https://evil.test/api/ipam/prefixes/", "https://example.test/api/dcim/devices/"] {
            do { _ = try await service.page(query: IPAMQuery(), next: next); XCTFail("Invalid next link") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        await service.client.close()
    }

    func testNumericIPAddressOrderingAcrossPagesAndVRFDuplicates() async throws {
        let service = try service(.ipAddresses, host: "ordering.test")
        let model = IPAMListModel(service: service)
        await model.reload(query: IPAMQuery())
        XCTAssertEqual(model.objects.map(\.id), [40, 30])
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [40, 30, 60, 10])
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [40, 30, 60, 10, 50, 20])
        XCTAssertEqual(model.objects.map(\.title), ["198.51.100.9/24", "198.51.100.202/24", "198.51.100.202/24", "198.51.100.207/24", "198.51.100.255/24", "2001:db8::1/64"])
        XCTAssertNil(model.errorMessage)
        for ordering in ["id", "address,id", "-address,id"] {
            var parts = URLComponents(string: "https://ordering.test/api/ipam/ip-addresses/?offset=2")
            parts?.queryItems?.append(.init(name: "ordering", value: ordering))
            do { _ = try await service.page(query: IPAMQuery(), next: parts?.string); XCTFail("Changed ordering accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        await service.client.close()
    }

    func testPermissionAndMissingDetailErrors() async throws {
        let forbidden = try service(host: "forbidden.test")
        let model = IPAMListModel(service: forbidden)
        await model.reload(query: IPAMQuery())
        XCTAssertEqual(model.errorMessage, APIError.forbidden.localizedDescription)
        XCTAssertFalse(model.hasLoaded)
        let normal = try service()
        let detail = IPAMDetailModel(service: normal, id: 999)
        await detail.reload()
        XCTAssertNil(detail.object)
        XCTAssertEqual(detail.errorMessage, APIError.http(404, [:]).localizedDescription)
        await forbidden.client.close()
        await normal.client.close()
    }

    func testFailedNextPageCanRetryWithoutDroppingResults() async throws {
        let source = PageSource()
        let model = IPAMListModel { query, next in try await source.page(query, next) }
        await model.reload(query: IPAMQuery())
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [1, 2])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.failedLoadingMore)
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [1, 2, 3])
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.next)
    }

    func testPaginationCycleAndDuplicatesDoNotLoop() async throws {
        let first = try fixturePage()
        let model = IPAMListModel { _, next in
            NetBoxPage(count: 3, next: "ipam/prefixes/?offset=2", previous: nil, results: first.results)
        }
        await model.reload(query: IPAMQuery())
        await model.loadMore()
        XCTAssertEqual(model.objects.map(\.id), [1, 2])
        XCTAssertNil(model.next)
        XCTAssertNotNil(model.errorMessage)
    }

    func testOlderSearchCannotReplaceNewerResults() async throws {
        let source = SearchSource()
        let model = IPAMListModel { query, _ in try await source.page(query) }
        let old = Task { await model.reload(query: IPAMQuery(search: "old")) }
        for _ in 0..<1000 {
            if await source.isWaiting { break }
            await Task.yield()
        }
        let waiting = await source.isWaiting
        XCTAssertTrue(waiting)
        await model.reload(query: IPAMQuery(search: "IPv6"))
        await source.release()
        await old.value
        XCTAssertEqual(model.objects.map(\.id), [2])
        XCTAssertFalse(model.isLoading)
    }
}

private func fixturePage(_ query: String = "") throws -> NetBoxPage<IPAMObject> {
    let url = try XCTUnwrap(URL(string: "https://example.test/api/ipam/prefixes/?limit=50&ordering=id" + query))
    let response = try XCTUnwrap(IPAMFixture.response(url))
    return try JSONDecoder().decode(NetBoxPage<IPAMObject>.self, from: Data(response.1.utf8))
}

private actor PageSource {
    private var failed = false
    func page(_ query: IPAMQuery, _ next: String?) throws -> NetBoxPage<IPAMObject> {
        if next != nil, !failed { failed = true; throw APIError.transport }
        return try fixturePage(next == nil ? "" : "&offset=2")
    }
}

private actor SearchSource {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func page(_ query: IPAMQuery) async throws -> NetBoxPage<IPAMObject> {
        if query.search == "old" { await withCheckedContinuation { continuation = $0 } }
        return try fixturePage(query.search == "IPv6" ? "&family=6" : "")
    }
    func release() { continuation?.resume(); continuation = nil }
}

private final class IPAMProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var (status, body) = IPAMFixture.response(url) ?? (404, "{}")
        if url.host == "ordering.test" {
            let values = [(40, "198.51.100.9/24"), (30, "198.51.100.202/24"), (60, "198.51.100.202/24"), (10, "198.51.100.207/24"), (50, "198.51.100.255/24"), (20, "2001:db8::1/64")]
            let offset = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let nextItems = (parts?.queryItems ?? []).filter { $0.name != "offset" } + [URLQueryItem(name: "offset", value: String(offset + 2))]
            parts?.queryItems = nextItems
            let rows: [[String: Any]] = values.dropFirst(offset).prefix(2).map { ["id": $0.0, "address": $0.1, "vrf": $0.0 == 60 ? ["id": 7, "name": "Blue"] as Any : NSNull()] }
            let reply: [String: Any] = ["count": values.count, "results": rows, "next": offset + 2 < values.count ? (parts?.string ?? "") as Any : NSNull(), "previous": NSNull()]
            if let data = try? JSONSerialization.data(withJSONObject: reply), let text = String(data: data, encoding: .utf8) { body = text; status = 200 }
        }
        if url.host == "forbidden.test" { status = 403 }
        if Int(url.lastPathComponent) == nil {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let orderingIsValid = url.path.contains("/prefixes") ? query.contains(URLQueryItem(name: "ordering", value: "prefix,id")) : !query.contains(where: { $0.name == "ordering" })
            if !query.contains(URLQueryItem(name: "limit", value: "50")) || !orderingIsValid { status = 400; body = "{}" }
        }
        if request.httpMethod != "GET" || request.httpBody != nil { status = 400 }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
