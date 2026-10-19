#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class ContextTests: XCTestCase {
    private func client(_ scenario: String = "valid") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ContextReadProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "synthetic-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testAllContextKindsDecodeAndPaginate() async throws {
        let client = try client()
        for kind in ContextKind.allCases {
            let service = ContextService(client: client, kind: kind)
            let model = PaginatedListModel(query: ContextQuery(), fetch: { try await service.page(query: $0, next: $1) })
            await model.reload(query: ContextQuery())
            while model.next != nil { await model.loadMore() }
            XCTAssertNil(model.errorMessage, kind.rawValue)
            XCTAssertEqual(model.objects.count, ContextFixture.records(kind).count)
            if let first = model.objects.first { let detail = try await service.detail(id: first.id); XCTAssertEqual(detail.id, first.id) }
            await model.reload(query: ContextQuery(search: "not-present"))
            XCTAssertTrue(model.objects.isEmpty); XCTAssertNil(model.errorMessage)
        }
        await client.close()
    }
    func testDuplicateVRFNamesPreserveIDsAndRouteDistinguishers() async throws {
        let client = try client()
        let page = try await ContextService(client: client, kind: .vrfs).page(query: ContextQuery(search: "Blue"), next: nil)
        XCTAssertEqual(page.results.map(\.id), [7, 8]); XCTAssertEqual(page.results.map(\.rd), ["64512:7", "64512:8"])
        let named = try await ContextService(client: client, kind: .vrfs).detail(id: 7)
        XCTAssertEqual(named.enforceUnique, true); XCTAssertEqual(named.importTargets?.first?.text, "64512:100")
        await client.close()
    }
    func testVRFContextKeepsOverlappingPrefixesSeparateAndLocksFilter() async throws {
        let client = try client()
        let context = IPAMContext.vrf(id: 7, title: "Blue")
        XCTAssertTrue(context.locksVRF)
        let page = try await IPAMService(client: client, kind: .prefixes, context: context).page(query: IPAMQuery(vrf: .init(id: 0, title: "Global")), next: nil)
        XCTAssertEqual(page.results.map(\.id), [5, 6]); XCTAssertTrue(page.results.allSatisfy { $0.vrf?.id == 7 })
        let other = try await IPAMService(client: client, kind: .prefixes, context: .vrf(id: 8, title: "Other Blue")).page(query: IPAMQuery(), next: nil)
        XCTAssertTrue(other.results.isEmpty)
        let addresses = try await IPAMService(client: client, kind: .ipAddresses, context: context).page(query: IPAMQuery(), next: nil)
        XCTAssertEqual(addresses.results.map(\.id), [13])
        await client.close()
    }
    func testTenantRoleAndExactPrefixScopeQueries() async throws {
        let client = try client()
        for context in [IPAMContext.tenant(id: 1, title: "Tenant"), .role(id: 1, title: "LAN"), .scope(type: "dcim.site", id: 101, title: "Paris")] {
            let page = try await IPAMService(client: client, kind: .prefixes, context: context).page(query: IPAMQuery(), next: nil)
            XCTAssertFalse(page.results.isEmpty); XCTAssertTrue(page.results.allSatisfy(context.matches))
        }
        XCTAssertThrowsError(try IPAMContext.role(id: 1, title: "LAN").items(kind: .ipAddresses))
        XCTAssertThrowsError(try IPAMContext.scope(type: "plugin.unknown", id: 1, title: "Unknown").items(kind: .prefixes))
        XCTAssertThrowsError(try IPAMContext.vrf(id: 0, title: "Invalid").items(kind: .prefixes))
        await client.close()
    }
    func testSiteTenantAndClusterGroupDirectoryScopes() async throws {
        let client = try client()
        for (kind, relation, id, ids) in [(ContextKind.locations, ContextScope.Relation.site, 101, [61, 62]), (.vrfs, .tenant, 1, [7]), (.clusters, .clusterGroup, 81, [9])] {
            let service = ContextService(client: client, kind: kind, scope: .init(relation: relation, id: id, title: "Scoped"))
            let model = PaginatedListModel(query: ContextQuery(), fetch: { try await service.page(query: $0, next: $1) })
            await model.reload(query: ContextQuery())
            while model.next != nil { await model.loadMore() }
            XCTAssertNil(model.errorMessage); XCTAssertEqual(model.objects.map(\.id).sorted(), ids)
        }
        await client.close()
    }
    func testTreeInventoryAllowsDescendantsAndPreservesScopeAcrossPages() async throws {
        let client = try client()
        for (kind, parent, id) in [(InventoryKind.sites, InventoryScope.Parent.region, 41), (.sites, .siteGroup, 51), (.racks, .location, 61)] {
            let service = InventoryService(client: client, kind: kind, scope: .init(parent: parent, id: id, title: "Root"))
            let model = PaginatedListModel(query: InventoryQuery(), fetch: { try await service.page(query: $0, next: $1) })
            await model.reload(query: InventoryQuery())
            while model.next != nil { await model.loadMore() }
            XCTAssertNil(model.errorMessage); XCTAssertEqual(model.objects.count, 3)
            do { _ = try await service.page(query: InventoryQuery(), next: "https://valid.test/api/" + kind.path + "?ordering=id&" + (service.scope?.key ?? "") + "=999"); XCTFail("Wrong scope accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        let machines = try await InventoryService(client: client, kind: .virtualMachines, scope: .init(parent: .cluster, id: 9, title: "Cluster")).page(query: InventoryQuery(), next: nil)
        XCTAssertEqual(machines.results.map(\.id), [401, 402])
        await client.close()
    }
    func testTreeAncestryCyclesAndUnrelatedParentsAreRejected() async throws {
        let client = try client()
        let service = ContextService(client: client, kind: .locations)
        let child = try await service.contains(62, under: 61); XCTAssertTrue(child)
        let foreign = try await service.contains(63, under: 61); XCTAssertFalse(foreign)
        await client.close()
        let cyclic = try self.client("cycle")
        do { _ = try await ContextService(client: cyclic, kind: .locations).contains(62, under: 61); XCTFail("Cycle accepted") }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        await cyclic.close()
    }
    func testChangedFiltersWrongDetailsAndWrongScopedRowsAreRejected() async throws {
        let client = try client()
        let service = ContextService(client: client, kind: .clusters, scope: .init(relation: .clusterGroup, id: 81, title: "Group"))
        for next in ["https://valid.test/api/virtualization/clusters/?ordering=name,id&group_id=82", "https://valid.test/api/virtualization/clusters/?ordering=id&group_id=81", "https://valid.test/api/dcim/sites/?ordering=name,id&group_id=81"] {
            do { _ = try await service.page(query: ContextQuery(), next: next); XCTFail("Invalid page accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        await client.close()
        for scenario in ["wrongid", "wrongscope"] {
            let invalid = try self.client(scenario)
            do {
                if scenario == "wrongid" { _ = try await ContextService(client: invalid, kind: .vrfs).detail(id: 7) }
                else { _ = try await ContextService(client: invalid, kind: .locations, scope: .init(relation: .site, id: 101, title: "Site")).page(query: ContextQuery(), next: nil) }
                XCTFail("Mismatched object accepted")
            } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
            await invalid.close()
        }
    }
    func testForbiddenContextDoesNotBlockOtherCategoriesAndOfflineIsReported() async throws {
        let client = try client("forbidden")
        let forbidden = ContextService(client: client, kind: .tenants)
        let model = PaginatedListModel(query: ContextQuery(), fetch: { try await forbidden.page(query: $0, next: $1) })
        await model.reload(query: ContextQuery()); XCTAssertNotNil(model.errorMessage)
        let allowed = try await ContextService(client: client, kind: .clusters).page(query: ContextQuery(), next: nil)
        XCTAssertFalse(allowed.results.isEmpty)
        await client.close()
        let offline = try self.client("offline")
        let failed = ContextService(client: offline, kind: .vrfs)
        let failedModel = PaginatedListModel(query: ContextQuery(), fetch: { try await failed.page(query: $0, next: $1) })
        await failedModel.reload(query: ContextQuery()); XCTAssertNotNil(failedModel.errorMessage)
        await offline.close()
    }
    func testScopeMappingDoesNotConfuseRoleModelsOrUnknownPluginScopes() {
        XCTAssertEqual(ContextKind.scope("virtualization.cluster"), .clusters)
        XCTAssertEqual(ContextKind.scope("dcim.location"), .locations)
        XCTAssertNil(ContextKind.scope("dcim.devicerole")); XCTAssertNil(ContextKind.scope("plugin.custom"))
        XCTAssertFalse(ContextScope(relation: .clusterGroup, id: 81, title: "Group").supports(.tenants))
        XCTAssertFalse(InventoryScope(parent: .siteGroup, id: 51, title: "Group").supports(.devices))
    }
}

private final class ContextReadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        guard request.httpMethod == "GET" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        let scenario = url.host?.components(separatedBy: ".").first ?? "valid"
        if scenario == "offline" { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let reply = ComponentFixture.response(url) ?? InventoryFixture.response(url) ?? IPAMFixture.response(url) ?? (404, "{}")
        var body = reply.1
        if var object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            if scenario == "wrongid" { object["id"] = 999 }
            if scenario == "cycle", object["id"] as? Int == 62 { object["parent"] = ["id": 62, "name": "Cycle"] }
            if scenario == "wrongscope", var rows = object["results"] as? [[String: Any]], !rows.isEmpty {
                rows[0]["site"] = ["id": 102, "name": "Foreign site"]; object["results"] = rows
            }
            if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) { body = text }
        }
        let forbidden = scenario == "forbidden" && url.path.contains("/tenancy/tenants")
        guard let response = HTTPURLResponse(url: url, statusCode: forbidden ? 403 : reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
