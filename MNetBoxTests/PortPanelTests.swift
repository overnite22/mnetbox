import XCTest
@testable import MNetBox

final class PortPanelTests: XCTestCase {
    private func decode(_ row: [String: Any]) throws -> PortPanelRecord { try JSONDecoder().decode(PortPanelRecord.self, from: JSONSerialization.data(withJSONObject: row)) }
    func testStateReflectsDocumentedCableAndEnabledWithoutInventingLinkStatus() throws {
        XCTAssertEqual(try decode(PortPanelFixture.row(1)).state, .cabled)
        XCTAssertEqual(try decode(PortPanelFixture.row(3)).state, .unconnected)
        XCTAssertEqual(try decode(PortPanelFixture.row(7)).state, .disabled)
        var unknown = PortPanelFixture.row(3); unknown.removeValue(forKey: "cable")
        XCTAssertEqual(try decode(unknown).state, .unknown)
        let record = try decode(unknown)
        let copy = try JSONDecoder().decode(PortPanelRecord.self, from: JSONEncoder().encode(record)); XCTAssertEqual(copy.state, .unknown)
    }
    func testConnectorTypesAndNaturalNameOrdering() throws {
        XCTAssertTrue(try decode(PortPanelFixture.row(1)).connector(family: .interfaces) == .copper)
        XCTAssertTrue(try decode(PortPanelFixture.row(50)).connector(family: .interfaces) == .fiber)
        XCTAssertTrue(try decode(PortPanelFixture.row(1)).connector(family: .outlet) == .power)
        let ports = try [10, 2, 1].map { try decode(PortPanelFixture.row($0)) }
        XCTAssertEqual(PortPanelRecord.ordered(ports).map(\.name), ["Gi1/0/1", "Gi1/0/2", "Gi1/0/10"])
    }
    func testWrongDeviceAndInvalidCableFail() throws {
        let port = try decode(PortPanelFixture.row(1)); XCTAssertThrowsError(try port.validate(deviceID: 302))
        var row = PortPanelFixture.row(1); row["cable"] = ["id": 0]; XCTAssertThrowsError(try decode(row).validate(deviceID: 301))
        row["cable"] = ["label": "Missing cable identity"]; XCTAssertThrowsError(try decode(row).validate(deviceID: 301))
    }
    @MainActor func testFiftyFourInterfacesPaginationAndSearchStayScoped() async throws {
        let api = try api(), service = PortPanelService(client: api, deviceID: 301)
        let model = PaginatedListModel(query: PortPanelQuery(), fetch: { try await service.page(query: $0, next: $1) })
        await model.reload(query: .init()); XCTAssertEqual(model.objects.count, 50); XCTAssertEqual(model.total, 54)
        await model.loadMore(); XCTAssertEqual(model.objects.count, 54); XCTAssertNil(model.next); XCTAssertNil(model.errorMessage)
        await model.reload(query: .init(search: "Te1/0")); XCTAssertEqual(model.objects.count, 6); XCTAssertEqual(model.total, 6)
        await api.close()
    }
    func testAllPortFamiliesAndWrongPaginationFilters() async throws {
        let api = try api(), service = PortPanelService(client: api, deviceID: 301)
        for family in PortPanelFamily.allCases {
            let page = try await service.page(query: .init(family: family), next: nil); XCTAssertEqual(page.results.isEmpty, ![PortPanelFamily.interfaces, .console, .power].contains(family))
            for port in page.results { try port.validate(deviceID: 301) }
        }
        for next in ["https://example.test/api/dcim/devices/?device_id=301&limit=50&ordering=name,id", "https://example.test/api/dcim/interfaces/?device_id=302&limit=50&ordering=name,id", "https://example.test/api/dcim/interfaces/?device_id=301&limit=50&ordering=id"] {
            do { _ = try await service.page(query: .init(), next: next); XCTFail("Unconfined next") } catch {}
        }
        await api.close()
    }
    func testDifferentEquipmentCannotReuseAnotherDevicesPorts() async throws {
        let api = try api()
        do {
            _ = try await PortPanelService(client: api, deviceID: 302).page(query: .init(), next: nil)
            XCTFail("Another device's actual ports must not appear")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        await api.close()
    }
    private func api() throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [PanelProtocol.self]
        return APIClient(credential: .init(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }
}
private final class PanelProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = PortPanelFixture.response(request) ?? DevicePortsFixture.response(request), let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
