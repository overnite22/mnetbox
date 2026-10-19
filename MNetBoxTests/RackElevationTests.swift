#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class RackElevationTests: XCTestCase {
    private func client(_ host: String = "example.test") throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ElevationProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(host)"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
    }

    func testElevationCombinesPagesAndPreservesHalfUnitsAndRestrictions() async throws {
        let client = try client()
        let service = RackElevationService(client: client, rackID: 201)
        let units = try await service.units(face: .front)
        XCTAssertEqual(units.map(\.id), ["4.5", "4", "3.5", "3", "2.5", "2", "1.5", "1"])
        XCTAssertTrue(units[0].occupied)
        XCTAssertNil(units[0].device)
        XCTAssertEqual(units.filter { $0.device?.id == 301 }.count, 2)
        let rear = try await service.units(face: .rear)
        XCTAssertFalse(rear.contains { $0.device != nil })
        XCTAssertTrue(rear[0].occupied)
        await client.close()
    }

    func testInvalidOrIncompleteElevationNeverPublishes() async throws {
        for host in ["cycle.test", "foreign.test", "wrongface.test", "duplicate.test", "incomplete.test", "forbidden.test"] {
            let client = try client(host)
            let model = RackElevationModel(service: RackElevationService(client: client, rackID: 201))
            await model.reload(face: .front)
            XCTAssertFalse(model.hasLoaded, host)
            XCTAssertTrue(model.units.isEmpty, host)
            XCTAssertNotNil(model.errorMessage, host)
            await client.close()
        }
    }

    func testSiteAndRackScopesFilterAndSurvivePaginationAndSearch() async throws {
        let client = try client()
        let racks = InventoryService(client: client, kind: .racks, scope: InventoryScope(parent: .site, id: 101, title: "Paris"))
        let first = try await racks.page(query: InventoryQuery(), next: nil)
        XCTAssertEqual(first.count, 3)
        let second = try await racks.page(query: InventoryQuery(), next: first.next)
        XCTAssertEqual(second.results.map(\.id), [203])
        let empty = try await InventoryService(client: client, kind: .racks, scope: InventoryScope(parent: .site, id: 102, title: "Lyon")).page(query: InventoryQuery(), next: nil)
        XCTAssertEqual(empty.count, 0)
        let devices = InventoryService(client: client, kind: .devices, scope: InventoryScope(parent: .rack, id: 201, title: "Rack-A"))
        let result = try await devices.page(query: InventoryQuery(search: "Core", status: "active"), next: nil)
        XCTAssertEqual(result.results.map(\.id), [301])
        for next in ["https://example.test/api/dcim/racks/?site_id=102", "https://example.test/api/dcim/racks/", "https://example.test/api/dcim/racks/?site_id=101&site_id=102"] {
            do { _ = try await racks.page(query: InventoryQuery(), next: next); XCTFail("Lost scope") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        await client.close()
    }
}

private final class ElevationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var (status, body) = InventoryFixture.response(url) ?? (404, "{}")
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.path.hasSuffix("/elevation/") == true {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if !query.contains(URLQueryItem(name: "expand_devices", value: "true")) || !query.contains(URLQueryItem(name: "limit", value: "100")) { status = 400 }
            if let data = body.data(using: .utf8), var page = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                switch url.host {
                case "cycle.test": page["next"] = url.absoluteString
                case "foreign.test": page["next"] = "https://evil.test/api/dcim/racks/201/elevation/?face=front&expand_devices=true"
                case "wrongface.test": page["next"] = "https://example.test/api/dcim/racks/201/elevation/?face=rear&expand_devices=true"
                case "duplicate.test": page["results"] = Array(repeating: ["id": 1, "name": "U1", "occupied": false, "device": NSNull()] as [String: Any], count: 4)
                case "incomplete.test": page["next"] = NSNull()
                case "forbidden.test": status = 403
                default: break
                }
                if let data = try? JSONSerialization.data(withJSONObject: page), let text = String(data: data, encoding: .utf8) { body = text }
            }
        }
        if request.httpMethod != "GET" || request.httpBody != nil { status = 400 }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
