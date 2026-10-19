#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class RelationshipsTests: XCTestCase {
    private func client(_ host: String = "example.test") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelationshipProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(host)"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testPhysicalAndVirtualInterfacesStayScopedAndPaginate() async throws {
        let client = try client()
        for (kind, parent, ids) in [(InterfaceKind.physical, 301, [501, 502, 503]), (.virtual, 401, [801, 802, 803])] {
            let service = InterfaceService(client: client, kind: kind, parentID: parent)
            let model = PaginatedListModel(query: InterfaceQuery(), fetch: { try await service.page(query: $0, next: $1) })
            await model.reload(query: InterfaceQuery())
            XCTAssertEqual(model.objects.count, 2)
            await model.loadMore()
            XCTAssertEqual(model.objects.map(\.id), ids)
            await model.reload(query: InterfaceQuery(enabled: "false"))
            XCTAssertEqual(model.objects.map(\.id), [ids[1]])
            await model.reload(query: InterfaceQuery(search: "no-match"))
            XCTAssertTrue(model.objects.isEmpty)
            XCTAssertNil(model.errorMessage)
        }
        await client.close()
    }
    func testMACsCableAndMultipleTerminationsDecode() async throws {
        let client = try client()
        let physical = try await InterfaceService(client: client, kind: .physical).detail(id: 501)
        XCTAssertEqual(physical.primaryMACAddress?.text, "02:00:00:00:00:01")
        XCTAssertEqual(physical.macAddresses?.count, 2)
        XCTAssertEqual(physical.linkPeers?.map(\.id), [601])
        XCTAssertEqual(physical.connectedEndpointsType, "dcim.interface")
        let cable: CableObject = try await client.get("dcim/cables/701/")
        XCTAssertEqual(cable.aTerminations?.count, 1)
        XCTAssertEqual(cable.bTerminations?.count, 2)
        XCTAssertEqual(cable.bTerminations?.last?.objectType, "dcim.frontport")
        XCTAssertEqual(cable.length?.text, "2.50")
        let virtual = try await InterfaceService(client: client, kind: .virtual).detail(id: 801)
        XCTAssertNil(virtual.type)
        XCTAssertNil(virtual.cable)
        XCTAssertEqual(virtual.virtualMachine?.id, 401)
        await client.close()
    }
    func testPrefixGlobalAndNamedVRFsDoNotMixOverlappingNetworks() async throws {
        let client = try client()
        for (vrf, expected) in [(Optional<Int>.none, [4]), (7, [6])] {
            let context = IPAMContext.network(cidr: "192.0.2.0/24", vrfID: vrf, vrfTitle: vrf == nil ? "Global" : "Blue")
            let service = IPAMService(client: client, kind: .prefixes, context: context)
            let page = try await service.page(query: IPAMQuery(), next: nil)
            XCTAssertEqual(page.results.map(\.id), expected)
            let addresses = try await IPAMService(client: client, kind: .ipAddresses, context: context).page(query: IPAMQuery(), next: nil)
            XCTAssertEqual(addresses.results.map(\.id), vrf == nil ? [11, 14] : [13])
        }
        let ipv6 = try await IPAMService(client: client, kind: .prefixes,
            context: .network(cidr: "2001:db8::/64", vrfID: nil, vrfTitle: "Global")).page(query: IPAMQuery(), next: nil)
        XCTAssertEqual(ipv6.results.map(\.id), [7])
        await client.close()
    }
    func testAssignedAddressesAndKnownInterfaceTypesOnly() async throws {
        let client = try client()
        for (kind, id, expected) in [(InterfaceKind.physical, 501, 11), (.virtual, 801, 12)] {
            let service = IPAMService(client: client, kind: .ipAddresses, context: .interface(kind: kind, id: id, title: "eth0"))
            let page = try await service.page(query: IPAMQuery(), next: nil)
            XCTAssertEqual(page.results.map(\.id), [expected])
            XCTAssertEqual(page.results[0].interfaceAssignment?.0, kind)
            XCTAssertEqual(page.results[0].interfaceAssignment?.1, id)
        }
        for json in [
            "{\"id\":1,\"address\":\"192.0.2.1/24\",\"assigned_object_type\":\"ipam.fhrpgroup\",\"assigned_object_id\":501,\"assigned_object\":{\"id\":501}}",
            "{\"id\":1,\"address\":\"192.0.2.1/24\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":501,\"assigned_object\":{\"id\":999}}",
            "{\"id\":1,\"address\":\"192.0.2.1/24\"}"
        ] {
            let object = try JSONDecoder().decode(IPAMObject.self, from: Data(json.utf8))
            XCTAssertNil(object.interfaceAssignment)
        }
        await client.close()
    }
    func testRelationshipNextLinksCannotDropOrChangeVRFOrOwner() async throws {
        let client = try client()
        let ipam = IPAMService(client: client, kind: .prefixes, context: .network(cidr: "192.0.2.0/24", vrfID: nil, vrfTitle: "Global"))
        for next in ["https://example.test/api/ipam/prefixes/?within=192.0.2.0%2F24", "https://example.test/api/ipam/prefixes/?within=192.0.2.0%2F24&vrf_id=7", "https://evil.test/api/ipam/prefixes/?within=192.0.2.0%2F24&vrf_id=null"] {
            do { _ = try await ipam.page(query: IPAMQuery(), next: next); XCTFail("Escaped context") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        let interfaces = InterfaceService(client: client, kind: .physical, parentID: 301)
        for next in ["https://example.test/api/dcim/interfaces/?device_id=303", "https://example.test/api/dcim/interfaces/?device_id=301&device_id=303", "https://example.test/api/virtualization/interfaces/?device_id=301"] {
            do { _ = try await interfaces.page(query: InterfaceQuery(), next: next); XCTFail("Escaped owner") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        await client.close()
    }
    func testRichFiltersAndReferencePagination() async throws {
        let client = try client()
        let query = IPAMQuery(vrf: ReferenceSelection(id: 7, title: "Blue"), tenant: ReferenceSelection(id: 1, title: "Example"),
                              role: ReferenceSelection(id: 1, title: "LAN"), site: ReferenceSelection(id: 101, title: "Paris"))
        let service = IPAMService(client: client, kind: .prefixes)
        let page = try await service.page(query: query, next: nil)
        XCTAssertEqual(page.results.map(\.id), [5, 6])
        let tenant: NetBoxPage<ReferenceObject> = try await client.get("tenancy/tenants/", query: [URLQueryItem(name: "limit", value: "50")])
        XCTAssertEqual(tenant.results.first?.title, "Example tenant")
        let sites: NetBoxPage<ReferenceObject> = try await client.get("dcim/sites/", query: [URLQueryItem(name: "limit", value: "50")])
        try CollectionLinks.validate(sites.next, path: "dcim/sites/")
        let second: NetBoxPage<ReferenceObject> = try await client.get(try XCTUnwrap(sites.next))
        XCTAssertEqual(second.results.map(\.id), [103])
        await client.close()
    }
    func testForbiddenMissingAndMismatchedDetails() async throws {
        for host in ["forbidden.test", "mismatch.test"] {
            let client = try client(host)
            let model = ReadDetailModel(fetch: { try await InterfaceService(client: client, kind: .physical).detail(id: 501) })
            await model.reload()
            XCTAssertNil(model.object)
            XCTAssertNotNil(model.errorMessage)
            await client.close()
        }
        let client = try client()
        let model = ReadDetailModel(fetch: { try await InterfaceService(client: client, kind: .virtual).detail(id: 999) })
        await model.reload()
        XCTAssertNil(model.object)
        XCTAssertNotNil(model.errorMessage)
        await client.close()
    }
    func testWrongVRFOrAssignmentPayloadIsRejected() async throws {
        let client = try client("wrongcontext.test")
        for context in [IPAMContext.network(cidr: "192.0.2.0/24", vrfID: nil, vrfTitle: "Global"),
                        .interface(kind: .physical, id: 501, title: "eth0")] {
            do {
                _ = try await IPAMService(client: client, kind: .ipAddresses, context: context).page(query: IPAMQuery(), next: nil)
                XCTFail("Wrong relationship payload")
            } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        }
        await client.close()
    }
    func testStaleDetailCannotReplaceNewerResult() async throws {
        let source = DetailSource()
        let model = ReadDetailModel(fetch: { await source.value() })
        let old = Task { await model.reload() }
        for _ in 0..<1000 { if await source.waiting { break }; await Task.yield() }
        let waiting = await source.waiting
        XCTAssertTrue(waiting)
        await model.reload()
        await source.release()
        await old.value
        XCTAssertEqual(model.object, "new")
        XCTAssertFalse(model.isLoading)
    }
}
private actor DetailSource {
    private var continuation: CheckedContinuation<Void, Never>?
    private var calls = 0
    var waiting: Bool { continuation != nil }
    func value() async -> String {
        calls += 1
        if calls == 1 { await withCheckedContinuation { continuation = $0 }; return "old" }
        return "new"
    }
    func release() { continuation?.resume(); continuation = nil }
}
private final class RelationshipProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var (status, body) = ComponentFixture.response(url) ?? IPAMFixture.response(url) ?? InventoryFixture.response(url) ?? (404, "{}")
        if url.host == "forbidden.test" { status = 403 }
        if url.host == "wrongcontext.test", let data = body.data(using: .utf8),
           var page = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           var rows = page["results"] as? [[String: Any]] {
            for index in rows.indices {
                rows[index]["vrf"] = ["id": 7, "name": "Blue"]
                rows[index]["assigned_object_id"] = 999
            }
            page["results"] = rows
            if let data = try? JSONSerialization.data(withJSONObject: page), let text = String(data: data, encoding: .utf8) { body = text }
        }
        if url.host == "mismatch.test" { body = body.replacingOccurrences(of: "\"id\":501", with: "\"id\":999") }
        if request.httpMethod != "GET" || request.httpBody != nil { status = 400 }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
