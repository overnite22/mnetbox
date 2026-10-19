#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class InventoryTests: XCTestCase {
    private func service(_ kind: InventoryKind, host: String = "example.test") throws -> InventoryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InventoryProtocol.self]
        return InventoryService(client: APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(host)"),
                                                                        token: "test-placeholder", kind: .legacy),
                                                session: URLSession(configuration: config)), kind: kind)
    }

    func testAllFourCollectionsPaginateAndRefresh() async throws {
        for kind in InventoryKind.allCases {
            let service = try service(kind)
            let model = InventoryListModel(service: service)
            await model.reload(query: InventoryQuery())
            XCTAssertEqual(model.objects.count, 2, kind.rawValue)
            XCTAssertEqual(model.total, 3)
            XCTAssertNotNil(model.next)
            await model.loadMore()
            XCTAssertEqual(model.objects.count, 3)
            XCTAssertNil(model.next)
            await model.reload(query: InventoryQuery())
            XCTAssertEqual(model.objects.count, 2)
            XCTAssertNil(model.errorMessage)
            await service.client.close()
        }
    }

    func testSearchStatusAndEmptyResults() async throws {
        let service = try service(.virtualMachines)
        let model = InventoryListModel(service: service)
        await model.reload(query: InventoryQuery(search: "monitoring", status: "active"))
        XCTAssertEqual(model.objects.map(\.title), ["monitoring-01"])
        await model.reload(query: InventoryQuery(status: "offline"))
        XCTAssertEqual(model.objects.map(\.title), ["offline-01"])
        await model.reload(query: InventoryQuery(search: "no-match"))
        XCTAssertTrue(model.objects.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertNil(model.errorMessage)
        await service.client.close()
    }

    func testTypedDetailsAndDecimalRepresentations() async throws {
        let sites = try service(.sites)
        let site = try await sites.detail(id: 101)
        XCTAssertEqual(site.physicalAddress, "Example address, Paris")
        let racks = try service(.racks)
        let rack = try await racks.detail(id: 201)
        XCTAssertEqual(rack.height?.text, "42")
        let devices = try service(.devices)
        let device = try await devices.detail(id: 301)
        XCTAssertEqual(device.deviceType?.text, "Example Switch")
        XCTAssertEqual(device.position?.text, "1.5")
        XCTAssertEqual(device.primaryIP4?.text, "192.0.2.10/24")
        let unnamed = try await devices.detail(id: 302)
        XCTAssertEqual(unnamed.title, "Unnamed device")
        let vms = try service(.virtualMachines)
        let vm = try await vms.detail(id: 401)
        XCTAssertEqual(vm.vcpus?.text, "1.50")
        XCTAssertEqual(vm.memory?.text, "2048")
        XCTAssertEqual(vm.cluster?.text, "Example Cluster")
        XCTAssertNil(vm.site)
        let secondVM = try await vms.detail(id: 402)
        XCTAssertEqual(secondVM.vcpus?.text, "2")
        for client in [sites.client, racks.client, devices.client, vms.client] { await client.close() }
    }

    func testConfinementPermissionsAndMissingDetail() async throws {
        let service = try service(.devices)
        for link in ["https://evil.test/api/dcim/devices/", "https://example.test/api/dcim/sites/"] {
            do { _ = try await service.page(query: InventoryQuery(), next: link); XCTFail("Invalid next link") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        let missing = InventoryDetailModel(service: service, id: 999)
        await missing.reload()
        XCTAssertNil(missing.object)
        XCTAssertEqual(missing.errorMessage, APIError.http(404, [:]).localizedDescription)
        let forbidden = try self.service(.racks, host: "forbidden.test")
        let model = InventoryListModel(service: forbidden)
        await model.reload(query: InventoryQuery())
        XCTAssertEqual(model.errorMessage, APIError.forbidden.localizedDescription)
        await forbidden.client.close()
        await service.client.close()
    }
}

private final class InventoryProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var (status, body) = InventoryFixture.response(url) ?? (404, "{}")
        if url.host == "forbidden.test" { status = 403 }
        if Int(url.lastPathComponent) == nil {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if !query.contains(URLQueryItem(name: "limit", value: "50"))
                || !query.contains(URLQueryItem(name: "ordering", value: "id")) { status = 400; body = "{}" }
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
