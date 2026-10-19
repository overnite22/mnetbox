#if DEBUG
import XCTest
@testable import MNetBox

@MainActor final class VLANBrowseTests: XCTestCase {
    private func client(_ scenario: String = "valid") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VLANBrowseProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "synthetic-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    private func record(_ dictionary: [String: Any]) throws -> VLANBrowseRecord {
        try JSONDecoder().decode(VLANBrowseRecord.self, from: JSONSerialization.data(withJSONObject: dictionary))
    }
    func testPaginationKeepsObjectIdentityWhenVIDIsReused() async throws {
        let client = try client()
        let service = VLANBrowseService(client: client, kind: .vlans)
        let model = PaginatedListModel(query: VLANBrowseQuery(), fetch: { try await service.page(query: $0, next: $1) })
        await model.reload(query: VLANBrowseQuery())
        while model.next != nil { await model.loadMore() }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.objects.map(\.id), [1, 21, 22, 24, 23])
        XCTAssertEqual(model.objects.filter { $0.vid == 200 }.map { $0.group?.id }, [31, 33])
        await client.close()
    }
    func testFixedGroupAndSiteOverrideDraftAndRemainOnNextPage() async throws {
        let client = try client()
        let site = VLANBrowseService(client: client, kind: .vlans, fixedSite: .init(id: 101, title: "Paris"))
        let page = try await site.page(query: VLANBrowseQuery(site: .init(id: 102, title: "Other")), next: nil)
        XCTAssertEqual(page.results.map(\.id), [22])
        let group = VLANBrowseService(client: client, kind: .vlans, fixedGroup: .init(id: 33, title: "Cluster"))
        let grouped = try await group.page(query: VLANBrowseQuery(), next: nil)
        XCTAssertEqual(grouped.results.map(\.id), [24])
        let ungrouped = VLANBrowseQuery(group: .init(id: 0, title: "Ungrouped"))
        XCTAssertThrowsError(try CollectionLinks.validate("https://valid.test/api/ipam/vlans/?ordering=vid,id&group_id=31", path: "ipam/vlans/", required: ungrouped.items(kind: .vlans).filter { $0.name != "limit" }))
        await client.close()
    }
    func testNoDirectSiteIsNotGlobalGroupScopeAndMissingIsNotNull() throws {
        let cluster = try record(VLANBrowseFixture.vlanRecords.first { $0["id"] as? Int == 24 } ?? [:])
        XCTAssertTrue(VLANBrowseQuery(site: .init(id: 0, title: "None")).matches(cluster))
        XCTAssertFalse(VLANBrowseQuery(group: .init(id: 0, title: "None")).matches(cluster))
        let missing = try record(["id": 25, "vid": 200, "name": "Incomplete"])
        XCTAssertFalse(VLANBrowseQuery(site: .init(id: 0, title: "None")).matches(missing))
        XCTAssertFalse(VLANBrowseQuery(group: .init(id: 0, title: "None")).matches(missing))
    }
    func testScopesRangesAndNumericUtilizationAreReadable() async throws {
        let client = try client()
        let service = VLANBrowseService(client: client, kind: .groups)
        let site = try await service.detail(id: 31)
        XCTAssertEqual(site.linkedScope?.0, .sites); XCTAssertEqual(site.linkedScope?.1, 101)
        XCTAssertEqual(site.vidRanges, [[100, 299], [400, 499]])
        XCTAssertEqual(site.utilization?.text, "0.3333")
        let rack = try await service.detail(id: 32); XCTAssertEqual(rack.linkedScope?.0, .racks)
        let cluster = try await service.detail(id: 33)
        XCTAssertNil(cluster.linkedScope); XCTAssertTrue(cluster.scopeText.contains("virtualization.cluster"))
        let global = try await service.detail(id: 34); XCTAssertEqual(global.scopeText, L10n.text("Global"))
        var unknown = VLANBrowseFixture.groupRecords[0]
        unknown["utilization"] = 1.25
        XCTAssertEqual(try record(unknown).utilization?.text, "1.25")
        unknown["scope_type"] = "plugin.custom"
        let custom = try record(unknown); XCTAssertNil(custom.linkedScope); XCTAssertTrue(custom.scopeText.contains("plugin.custom"))
        unknown["vid_ranges"] = [[300, 100]]; XCTAssertThrowsError(try record(unknown).validate(kind: .groups))
        unknown["vid_ranges"] = [[1]]; XCTAssertThrowsError(try record(unknown).validate(kind: .groups))
        await client.close()
    }
    func testVLANPrefixAndInterfaceContextsAreExplicitAndConfined() async throws {
        let client = try client()
        let prefix = try await IPAMService(client: client, kind: .prefixes, context: .vlan(id: 1, title: "Documentation")).page(query: IPAMQuery(), next: nil)
        XCTAssertEqual(prefix.count, 7); XCTAssertTrue(prefix.results.allSatisfy { $0.vlan?.id == 1 })
        for (kind, id) in [(InterfaceKind.physical, 503), (.virtual, 803)] {
            let service = InterfaceService(client: client, kind: kind, vlanID: 1)
            let page = try await service.page(query: InterfaceQuery(), next: nil)
            XCTAssertEqual(page.results.map(\.id), [id])
            XCTAssertEqual(page.results.first?.relatedVLANs.map(\.id), [1])
            do { _ = try await service.page(query: InterfaceQuery(), next: "https://valid.test/api/" + kind.path + "?vlan_id=21"); XCTFail("Changed VLAN context accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        }
        XCTAssertThrowsError(try IPAMContext.vlan(id: 1, title: "Test").items(kind: .ipAddresses))
        XCTAssertThrowsError(try IPAMContext.vlan(id: 0, title: "Test").items(kind: .prefixes))
        await client.close()
    }
    func testMismatchedFilteredRowsAndDetailsAreRejected() async throws {
        for scenario in ["wrongsite", "missing", "wrongid"] {
            let client = try client(scenario)
            let service = VLANBrowseService(client: client, kind: .vlans)
            do {
                if scenario == "wrongid" { _ = try await service.detail(id: 22) }
                else { _ = try await service.page(query: VLANBrowseQuery(site: .init(id: 101, title: "Paris")), next: nil) }
                XCTFail("Invalid relation accepted")
            } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
            await client.close()
        }
    }
    func testPermissionAndOfflineErrorsRemainVisibleWithoutWriting() async throws {
        for scenario in ["forbidden", "offline"] {
            let client = try client(scenario)
            let service = VLANBrowseService(client: client, kind: .vlans)
            let model = PaginatedListModel(query: VLANBrowseQuery(), fetch: { try await service.page(query: $0, next: $1) })
            await model.reload(query: VLANBrowseQuery())
            XCTAssertNotNil(model.errorMessage); XCTAssertFalse(model.hasLoaded); XCTAssertTrue(model.objects.isEmpty)
            await client.close()
        }
    }
    func testInvalidQueriesAreRejectedAndUnknownChoiceLabelsSurvive() throws {
        XCTAssertThrowsError(try VLANBrowseQuery(site: .init(id: -1, title: "Bad")).items(kind: .vlans))
        XCTAssertThrowsError(try VLANBrowseQuery(group: .init(id: 31, title: "Bad")).items(kind: .groups))
        var row = VLANBrowseFixture.vlanRecords[0]
        row["status"] = ["value": "custom", "label": "Custom workflow"]
        let decoded = try record(row); try decoded.validate(kind: .vlans)
        XCTAssertEqual(decoded.status?.text, "Custom workflow")
        XCTAssertTrue(VLANBrowseQuery(status: "custom").matches(decoded))
        XCTAssertFalse(VLANBrowseQuery(status: "active").matches(decoded))
        row["vid"] = 4095; XCTAssertThrowsError(try record(row).validate(kind: .vlans))
    }
}

private final class VLANBrowseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        guard request.httpMethod == "GET" else { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return }
        let scenario = url.host?.components(separatedBy: ".").first ?? "valid"
        if scenario == "offline" { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        let reply = ComponentFixture.response(url) ?? IPAMFixture.response(url) ?? (404, "{}")
        var body = reply.1
        if var object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            if scenario == "wrongid" { object["id"] = 99 }
            if scenario == "wrongsite" || scenario == "missing", var rows = object["results"] as? [[String: Any]], !rows.isEmpty {
                if scenario == "missing" { rows[0].removeValue(forKey: "site") }
                else { rows[0]["site"] = ["id": 102, "name": "Other"] }
                object["results"] = rows
            }
            if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) { body = text }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: scenario == "forbidden" ? 403 : reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
