import XCTest
@testable import MNetBox

final class DevicePortsTests: XCTestCase {
    private func api() throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DevicePortProtocol.self]
        return APIClient(credential: .init(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testSixPortFamiliesUseExactParentAndTypedDetail() async throws {
        let api = try api()
        for kind in DevicePortKind.allCases {
            let service = DevicePortService(client: api, kind: kind, deviceID: 301)
            let page = try await service.page(query: .init(), next: nil); XCTAssertEqual(page.count, 51)
            let detail = try await service.detail(id: 1201); XCTAssertEqual(detail.device.id, 301)
            XCTAssertThrowsError(try detail.validate(deviceID: 999))
            XCTAssertThrowsError(try detail.validate(deviceID: 301, id: 999))
            do { _ = try await service.page(query: .init(search: "keep"), next: "https://example.test/api/\(kind.path)?device_id=999&limit=50&ordering=name,id&q=keep"); XCTFail("Wrong parent") } catch {}
        }
        await api.close()
    }
    func testActivePortsHaveNativeTraceButPassivePathsAreNotMisused() async throws {
        let api = try api()
        for kind in DevicePortKind.allCases {
            if kind.traceable {
                let trace = try await api.cableTrace(id: 1201, portKind: kind)
                XCTAssertEqual(trace.segments.first?.near.first?.kind, kind.rawValue)
            } else {
                do { _ = try await api.cableTrace(id: 1201, portKind: kind); XCTFail("No trace route on passive ports") } catch { XCTAssertEqual(error as? APIError, .invalidURL) }
            }
        }
        await api.close()
    }
    @MainActor func testPortPaginationLoadsBeyondFirstFiftyAndKeepsSearch() async throws {
        let api = try api(), service = DevicePortService(client: api, kind: .console, deviceID: 301)
        let query = DevicePortQuery(search: "keep")
        let model = PaginatedListModel(query: query, fetch: { try await service.page(query: $0, next: $1) })
        await model.reload(query: query); XCTAssertEqual(model.objects.count, 50); XCTAssertNotNil(model.next)
        await model.loadMore(); XCTAssertEqual(model.objects.count, 51); XCTAssertEqual(model.total, 51); XCTAssertNil(model.next); XCTAssertNil(model.errorMessage)
        await api.close()
    }
    func testPortPaginationCannotChangeCollectionSearchOrOrdering() async throws {
        let api = try api(), service = DevicePortService(client: api, kind: .console, deviceID: 301)
        for next in ["https://example.test/api/dcim/devices/?device_id=301&limit=50&ordering=name,id", "https://example.test/api/dcim/console-ports/?device_id=301&limit=50&ordering=id", "https://example.test/api/dcim/console-ports/?device_id=301&limit=50&ordering=name,id&q=changed"] {
            do { _ = try await service.page(query: .init(search: "keep"), next: next); XCTFail("Wrong pagination") } catch {}
        }
        await api.close()
    }
}
private final class DevicePortProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let reply = DevicePortsFixture.response(request), let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
