import XCTest
@testable import MNetBox

@MainActor final class DashboardTests: XCTestCase {
    private func client(host: String = "counts.test") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(host)"),
                                                token: "test-placeholder", kind: .legacy),
                         session: URLSession(configuration: config))
    }

    func testLoadsAllTotalsWithBoundedGETRequests() async throws {
        let api = try client()
        let model = DashboardModel(client: api)
        await model.refresh()
        XCTAssertEqual(model.values, [.sites: .count(2), .racks: .count(0), .devices: .count(1200),
                                      .virtualMachines: .count(8), .prefixes: .count(6), .ipAddresses: .count(42031)])
        XCTAssertNotNil(model.lastUpdated)
        XCTAssertFalse(model.isLoading)
        await api.close()
    }

    func testForbiddenMetricDoesNotHideOtherTotals() async throws {
        let api = try client(host: "forbidden.test")
        let model = DashboardModel(client: api)
        await model.refresh()
        XCTAssertEqual(model.values[.prefixes], .failed(APIError.forbidden.localizedDescription))
        XCTAssertEqual(model.values[.ipAddresses], .count(42031))
        XCTAssertEqual(model.values.count, 6)
        await api.close()
    }

    func testInvalidCountIsNotShownAsZero() async throws {
        let api = try client(host: "invalid.test")
        let model = DashboardModel(client: api)
        await model.refresh()
        XCTAssertEqual(model.values[.sites], .failed(APIError.invalidResponse.localizedDescription))
        XCTAssertEqual(model.values[.devices], .failed(APIError.decoding.localizedDescription))
        await api.close()
    }

    func testRefreshRecoversFromFailure() async {
        let source = RetrySource()
        let model = DashboardModel { metric in try await source.count(metric) }
        await model.refresh()
        XCTAssertEqual(model.values[.sites], .failed(APIError.transport.localizedDescription))
        await model.refresh()
        XCTAssertEqual(model.values[.sites], .count(9))
        XCTAssertTrue(model.values.values.allSatisfy { $0 == .count(9) })
    }

    func testCancellationPreservesPreviousSnapshot() async {
        let source = RetrySource()
        let model = DashboardModel { metric in try await source.count(metric, delayRetry: true) }
        await model.refresh()
        let snapshot = model.values
        let updated = model.lastUpdated
        let refresh = Task { await model.refresh() }
        // Yield to start the structured loading task before cancelling it.
        for _ in 0..<100 {
            if model.isLoading { break }
            await Task.yield()
        }
        XCTAssertTrue(model.isLoading)
        refresh.cancel()
        await refresh.value
        XCTAssertEqual(model.values, snapshot)
        XCTAssertEqual(model.lastUpdated, updated)
        XCTAssertFalse(model.isLoading)
    }
}

private actor RetrySource {
    private var seen: Set<DashboardMetric> = []
    func count(_ metric: DashboardMetric, delayRetry: Bool = false) async throws -> Int {
        if seen.insert(metric).inserted { throw APIError.transport }
        if delayRetry { try await Task.sleep(for: .seconds(30)) }
        return 9
    }
}

private final class CountProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let counts = ["/api/dcim/sites/": 2, "/api/dcim/racks/": 0, "/api/dcim/devices/": 1200,
                      "/api/virtualization/virtual-machines/": 8, "/api/ipam/prefixes/": 6,
                      "/api/ipam/ip-addresses/": 42031]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        var status = 200
        var body = "{\"count\":\(counts[path] ?? -1),\"next\":null,\"previous\":null,\"results\":[{\"id\":1}]}"
        if request.httpMethod != "GET" || request.httpBody != nil || counts[path] == nil
            || !query.contains(URLQueryItem(name: "limit", value: "1"))
            || !query.contains(URLQueryItem(name: "brief", value: "true")) {
            status = 400
        } else if url.host == "forbidden.test", url.lastPathComponent == "prefixes" {
            status = 403
        } else if url.host == "invalid.test" {
            if url.lastPathComponent == "sites" { body = "{\"count\":-1}" }
            if url.lastPathComponent == "devices" { body = "{}" }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
