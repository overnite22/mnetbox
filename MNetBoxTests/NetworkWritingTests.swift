import XCTest
@testable import MNetBox

@MainActor final class NetworkWritingTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NetworkProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario)-\(UUID().uuidString).test"), token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    private func vlan(vid: Int = 250, group: Int? = 31, site: Int? = 101, name: String = "Mobile VLAN") -> VLANCreationPlan {
        VLANCreationPlan(vid: vid, name: name, status: "active", site: site.map { .init(id: $0, title: "Site") }, group: group.map { .init(id: $0, title: "Group") }, tenant: nil, role: .init(id: 1, title: "LAN"), description: "Mobile", comments: "Documentation")
    }
    private func interface(_ kind: InterfaceKind = .physical) -> InterfaceSelection { .init(kind: kind, id: kind == .physical ? 501 : 801, title: "Interface", parentID: kind == .physical ? 301 : 401) }
    private func mac(_ kind: InterfaceKind = .physical) throws -> MACCreationPlan { MACCreationPlan(address: try MACValue("0200.0000.0099"), interface: interface(kind), description: "Mobile MAC", comments: "") }
    private func group(scope: VLANGroupScope = .global, id: Int? = nil, name: String = "Mobile group", slug: String = "mobile-group") -> VLANGroupCreationPlan {
        .init(name: name, slug: slug, scope: scope, reference: id.map { .init(id: $0, title: "Scope") }, ranges: [[1, 100], [200, 299]], tenant: nil, description: "Mobile", comments: "")
    }
    func testGroupRangesBoundsOverlapAndPayloadWhitelist() throws {
        XCTAssertEqual(try VLANGroupCreationPlan.parseRanges("300-399,1-100,200"), [[1, 100], [200, 200], [300, 399]])
        for value in ["", "0", "4095", "4-3", "1-100,100-200", "1,,2", "-1", "１", "1-2-3"] { XCTAssertThrowsError(try VLANGroupCreationPlan.parseRanges(value)) }
        for plan in [group(scope: .site), group(id: 101), group(name: ""), group(name: String(repeating: "é", count: 101)), group(slug: "bad slug")] { XCTAssertThrowsError(try plan.validate()) }
        try group(name: String(repeating: "é", count: 100)).validate()
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(group())) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["name", "slug", "scope_type", "scope_id", "vid_ranges", "tenant", "description", "comments"])
        XCTAssertTrue(body["scope_type"] is NSNull); XCTAssertTrue(body["scope_id"] is NSNull)
    }
    func testGroupCreationScopeDuplicatesAndSingleFieldEditing() async throws {
        let api = try api()
        let row = try await api.createVLANGroup(group(scope: .site, id: 101))
        XCTAssertEqual(row.scopeID, 101); XCTAssertEqual(row.vidRanges, [[1, 100], [200, 299]])
        do { _ = try await api.createVLANGroup(group(scope: .site, id: 101)); XCTFail("Same-scope duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateVLANGroup) }
        let global = try await api.createVLANGroup(group())
        XCTAssertNil(global.scopeID)
        let snapshot = try await api.textSnapshot(for: .init(collection: .vlanGroups, id: row.id), field: .name)
        _ = try await api.updateText(snapshot, to: String(repeating: "é", count: 100))
        let edited = try await VLANBrowseService(client: api, kind: .groups).detail(id: row.id)
        XCTAssertEqual(edited.name.count, 100); XCTAssertEqual(edited.slug, row.slug); XCTAssertEqual(edited.scopeID, 101); XCTAssertEqual(edited.vidRanges, row.vidRanges)
        await api.close()
    }
    func testEverySupportedGroupScopeResolvesTheExactReference() async throws {
        let api = try api()
        for (scope, id) in [(VLANGroupScope.region, 41), (.siteGroup, 51), (.site, 101), (.location, 61), (.rackGroup, 71), (.rack, 201), (.clusterGroup, 81), (.cluster, 9)] {
            let row = try await api.createVLANGroup(group(scope: scope, id: id))
            XCTAssertEqual(row.scopeType, scope.rawValue); XCTAssertEqual(row.scopeID, id); XCTAssertEqual(row.scope?.id, id)
        }
        do { _ = try await api.createVLANGroup(group(scope: .site, id: 9999)); XCTFail("Missing reference") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        await api.close()
    }
    func testGroupCreationDeniedLostAndWrongReplyNeverRetry() async throws {
        for scenario in ["denied", "lost", "wrongreply"] {
            let api = try api(scenario); let model = VLANGroupCreateModel(client: api)
            model.name = "Mobile group"; model.slug = "mobile-group"
            await model.review(); XCTAssertNotNil(model.reviewed)
            await model.create(); XCTAssertTrue(model.attempted); XCTAssertNil(model.createdID); XCTAssertNotNil(model.errorMessage)
            await model.create(); XCTAssertFalse(model.canReview); XCTAssertEqual(model.name, "Mobile group")
            let page = try await VLANBrowseService(client: api, kind: .groups).page(query: .init(search: "Mobile"), next: nil)
            XCTAssertEqual(page.count, scenario == "denied" ? 0 : 1)
            await api.close()
        }
    }
    func testNetworkDeletionBlocksReferencesAndAllowsOnlyUnusedObjects() async throws {
        let api = try api()
        for target in [DeletionTarget(collection: .macAddresses, id: 11), .init(collection: .macAddresses, id: 12), .init(collection: .vlans, id: 1)] {
            let snapshot = try await api.deletionSnapshot(target)
            XCTAssertFalse(snapshot.blockers.isEmpty)
            do { try await api.deleteObject(snapshot); XCTFail("Dependency") } catch { XCTAssertEqual(error as? APIError, .deletionBlocked) }
        }
        let row = try await api.createVLAN(vlan(vid: 250, group: nil, site: nil))
        for target in [DeletionTarget(collection: .vlans, id: row.id), .init(collection: .macAddresses, id: 14)] {
            let model = DeletionModel(client: api, target: target); await model.load()
            XCTAssertEqual(model.snapshot?.blockers, [])
            model.confirmation = "0"; XCTAssertFalse(model.canDelete)
            model.confirmation = String(target.id); await model.delete(); XCTAssertTrue(model.deleted)
            await model.delete()
            do { _ = try await api.deletionSnapshot(target); XCTFail("Deleted") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        }
        await api.close()
    }
    func testNetworkDeletionUncertaintyAndPermissionNeverRetry() async throws {
        for scenario in ["denied", "lost", "conflict"] {
            let api = try api(scenario); let model = DeletionModel(client: api, target: .init(collection: .macAddresses, id: 14))
            await model.load(); model.confirmation = "14"; await model.delete()
            XCTAssertFalse(model.deleted); XCTAssertTrue(model.attempted); XCTAssertNotNil(model.errorMessage)
            await model.delete(); XCTAssertFalse(model.canDelete)
            await model.checkCurrent(); XCTAssertNotNil(model.errorMessage)
            await api.close()
        }
    }
    func testFreshPrimaryDependencyAppearingAfterReviewPreventsMACDelete() async throws {
        let api = try api("dependencyrace")
        let model = DeletionModel(client: api, target: .init(collection: .macAddresses, id: 14))
        await model.load(); XCTAssertEqual(model.snapshot?.blockers, [])
        model.confirmation = "14"; await model.delete()
        XCTAssertFalse(model.deleted); XCTAssertEqual(model.errorMessage, APIError.deletionBlocked.localizedDescription)
        let row = try await MACService(client: api).detail(id: 14); XCTAssertEqual(row.id, 14)
        await api.close()
    }
    func testFreshPrefixDependencyAppearingAfterReviewPreventsVLANDelete() async throws {
        let api = try api("vlandependencyrace")
        let row = try await api.createVLAN(vlan(vid: 250, group: nil, site: nil))
        let model = DeletionModel(client: api, target: .init(collection: .vlans, id: row.id))
        await model.load(); XCTAssertEqual(model.snapshot?.blockers, [])
        model.confirmation = String(row.id); await model.delete()
        XCTAssertFalse(model.deleted); XCTAssertEqual(model.errorMessage, APIError.deletionBlocked.localizedDescription)
        let current = try await VLANBrowseService(client: api, kind: .vlans).detail(id: row.id); XCTAssertEqual(current.id, row.id)
        await api.close()
    }
    func testNetworkDeletionRequiresCompleteDependencyMetadata() throws {
        var row = VLANBrowseFixture.vlanRecords[0]
        for key in ["prefix_count", "qinq_role", "l2vpn_termination", "site", "group"] {
            var missing = row; missing.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(DeletionObject.self, from: JSONSerialization.data(withJSONObject: missing)))
        }
        row["prefix_count"] = -1
        XCTAssertThrowsError(try JSONDecoder().decode(DeletionObject.self, from: JSONSerialization.data(withJSONObject: row)))
    }
    func testMACNormalizationAndInvalidFormats() throws {
        for value in ["02:00:00:00:00:99", "02-00-00-00-00-99", "0200.0000.0099", "020000000099", " 02:00:00:00:00:99 "] { XCTAssertEqual(try MACValue(value).text, "02:00:00:00:00:99") }
        for value in ["", "02:00:00:00:00", "02:00:00:00:00:99:00", "02-00:00:00:00:99", "0200 0000 0099", "zz:00:00:00:00:99"] { XCTAssertThrowsError(try MACValue(value)) }
    }
    func testCreationPayloadWhitelistsAndBounds() throws {
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(vlan())) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["vid", "name", "status", "site", "group", "tenant", "role", "description", "comments"])
        XCTAssertTrue(object["tenant"] is NSNull); XCTAssertEqual(object["group"] as? Int, 31)
        for vid in [0, 4095] { XCTAssertThrowsError(try vlan(vid: vid).validate()) }
        for name in ["", "bad\nname", String(repeating: "é", count: 65)] { XCTAssertThrowsError(try vlan(name: name).validate()) }
        let macPayload = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(mac())) as? [String: Any])
        XCTAssertEqual(Set(macPayload.keys), ["mac_address", "assigned_object_type", "assigned_object_id", "description", "comments"])
        XCTAssertEqual(macPayload["assigned_object_id"] as? Int, 501)
    }
    func testVLANGroupRangesSiteAndVisibleDuplicatesBlockBeforePOST() async throws {
        let api = try api()
        for plan in [vlan(vid: 300), vlan(site: 102), vlan(vid: 200), vlan(name: "Paris servers")] {
            do { _ = try await api.createVLAN(plan); XCTFail("Rejected plan should not POST") } catch { XCTAssertTrue([APIError.invalidVID, .invalidReference, .duplicateVLAN].contains(error as? APIError ?? .transport)) }
        }
        await api.close()
    }
    func testVLANCreationRechecksAndMatchesFullReply() async throws {
        let api = try api()
        let model = NetworkCreateModel(client: api); model.vid = "0250"; model.name = " Mobile VLAN "; model.site = .init(id: 101, title: "Site"); model.group = .init(id: 31, title: "Group")
        await model.review(); XCTAssertNotNil(model.reviewed)
        await model.create(); XCTAssertNotNil(model.createdID); XCTAssertTrue(model.attempted)
        let id = try XCTUnwrap(model.createdID)
        let row = try await VLANBrowseService(client: api, kind: .vlans).detail(id: id)
        XCTAssertEqual(row.vid, 250); XCTAssertEqual(row.name, "Mobile VLAN"); XCTAssertEqual(row.group?.id, 31)
        await model.create(); XCTAssertEqual(model.createdID, id)
        await api.close()
    }
    func testVLANTextAndIPAMRoleEditsRetainVIDAndGroup() async throws {
        let api = try api()
        let snapshot = try await api.textSnapshot(for: .init(collection: .vlans, id: 22), field: .name)
        _ = try await api.updateText(snapshot, to: "Renamed VLAN")
        let role = try await api.structuredSnapshot(target: .init(collection: .vlans, id: 22), field: .role)
        _ = try await api.updateStructured(role, to: .reference(.init(id: 2, title: "WAN")))
        let row = try await VLANBrowseService(client: api, kind: .vlans).detail(id: 22)
        XCTAssertEqual(row.name, "Renamed VLAN"); XCTAssertEqual(row.role?.id, 2); XCTAssertEqual(row.group?.id, 31); XCTAssertEqual(row.vid, 200)
        await api.close()
    }
    func testMACCreationOnPhysicalAndVMInterfacesDoesNotSetPrimary() async throws {
        for kind in [InterfaceKind.physical, .virtual] {
            let api = try api(); let row = try await api.createMAC(mac(kind))
            XCTAssertFalse(row.isPrimary); XCTAssertEqual(row.assignment?.0, kind); XCTAssertEqual(row.assignment?.1, interface(kind).id)
            let original = try await MACService(client: api).detail(id: kind == .physical ? 11 : 13)
            XCTAssertTrue(original.isPrimary)
            do { _ = try await api.createMAC(mac(kind)); XCTFail("Duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateMAC) }
            await api.close()
        }
    }
    func testPrimaryMACSelectionRequiresExactAssignmentAndSupportsClearing() async throws {
        let api = try api(); let target = StructuredEditTarget(collection: .physicalInterfaces, id: 501, parentID: 301)
        let snapshot = try await api.structuredSnapshot(target: target, field: .primaryMAC)
        for id in [13, 14] {
            do { _ = try await api.updateStructured(snapshot, to: .reference(.init(id: id, title: "Other"))); XCTFail("Wrong assignment") } catch { XCTAssertEqual(error as? APIError, .invalidReference) }
        }
        _ = try await api.updateStructured(snapshot, to: .reference(.init(id: 12, title: "Secondary")))
        let selected = try await MACService(client: api).detail(id: 12); XCTAssertTrue(selected.isPrimary)
        let fresh = try await api.structuredSnapshot(target: target, field: .primaryMAC)
        _ = try await api.updateStructured(fresh, to: .reference(nil))
        let cleared = try await MACService(client: api).detail(id: 12); XCTAssertFalse(cleared.isPrimary)
        await api.close()
    }
    func testMACPrimaryBlocksDetachAndMoveUntilExplicitClearing() async throws {
        let api = try api(); let target = StructuredEditTarget(collection: .macAddresses, id: 11)
        let snapshot = try await api.structuredSnapshot(target: target, field: .assignment)
        for selected in [nil, interface(.virtual)] {
            do { _ = try await api.updateStructured(snapshot, to: .assignment(selected)); XCTFail("Primary constraint") } catch { XCTAssertEqual(error as? APIError, .primaryMACBlocked) }
        }
        let interfaceSnapshot = try await api.structuredSnapshot(target: .init(collection: .physicalInterfaces, id: 501, parentID: 301), field: .primaryMAC)
        _ = try await api.updateStructured(interfaceSnapshot, to: .reference(nil))
        _ = try await api.updateStructured(snapshot, to: .assignment(interface(.virtual)))
        let moved = try await MACService(client: api).detail(id: 11)
        XCTAssertEqual(moved.assignment?.0, .virtual); XCTAssertEqual(moved.assignment?.1, 801); XCTAssertFalse(moved.isPrimary)
        let fresh = try await api.structuredSnapshot(target: target, field: .assignment)
        _ = try await api.updateStructured(fresh, to: .assignment(nil))
        let detached = try await MACService(client: api).detail(id: 11); XCTAssertNil(detached.assignment)
        await api.close()
    }
    func testMACPagesPreserveScopeSearchAndReuseAddressIDs() async throws {
        let api = try api(); let service = MACService(client: api, interface: interface())
        let page = try await service.page(search: "02:", next: nil)
        XCTAssertEqual(page.results.map(\.id), [11, 12])
        do { _ = try await service.page(search: "02:", next: "https://example.test/api/dcim/mac-addresses/?interface_id=801&ordering=mac_address,id&q=02:"); XCTFail("Scope escape") } catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        let all = try await MACService(client: api).page(search: "00:02", next: nil)
        XCTAssertEqual(all.results.map(\.id), [12, 14])
        await api.close()
    }
    func testCreationDeniedLostAndMismatchedResponsesNeverRetry() async throws {
        for scenario in ["denied", "lost", "wrongreply"] {
            let api = try api(scenario); let model = NetworkCreateModel(client: api, interface: interface())
            model.address = "020000000099"
            await model.review(); XCTAssertNotNil(model.reviewed)
            await model.create(); XCTAssertTrue(model.attempted); XCTAssertNil(model.createdID); XCTAssertNotNil(model.errorMessage)
            await model.create(); XCTAssertEqual(model.address, "020000000099"); XCTAssertFalse(model.canReview)
            let rows = try await MACService(client: api, interface: interface()).page(search: "00:99", next: nil)
            XCTAssertEqual(rows.count, scenario == "denied" ? 0 : 1)
            await api.close()
        }
    }
    func testMACAssignmentConflictAndPrimaryRaceRetainDraft() async throws {
        for scenario in ["conflict", "primaryrace"] {
            let api = try api(scenario)
            let model = StructuredEditModel(client: api, target: .init(collection: .macAddresses, id: 12), field: .assignment)
            await model.load(); model.assignment = nil
            let proposal = await model.review(); let reviewed = try XCTUnwrap(proposal)
            await model.save(reviewed)
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertFalse(model.canReview)
            XCTAssertEqual(model.errorMessage, (scenario == "conflict" ? APIError.conflict : .primaryMACBlocked).localizedDescription)
            let current = try await MACService(client: api).detail(id: 12); XCTAssertEqual(current.assignment?.1, 501)
            await api.close()
        }
    }
    func testMACUnknownAssignmentAndMissingMetadataAreNotEditable() throws {
        let body = "{\"id\":1,\"mac_address\":\"02:00:00:00:00:01\",\"assigned_object_type\":\"plugin.port\",\"assigned_object_id\":2,\"is_primary\":false,\"description\":\"\",\"comments\":\"\"}"
        let row = try JSONDecoder().decode(MACRecord.self, from: Data(body.utf8)); XCTAssertNil(row.assignment)
        let object = try JSONDecoder().decode(StructuredEditObject.self, from: Data(body.utf8)); XCTAssertNil(object.value(.assignment))
        XCTAssertThrowsError(try JSONDecoder().decode(MACRecord.self, from: Data(body.replacingOccurrences(of: "\"is_primary\":false,", with: "").utf8)))
    }
}

private final class NetworkProtocol: URLProtocol, @unchecked Sendable {
    private static let store = NetworkProtocolStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let mutation = request.httpMethod == "POST" || request.httpMethod == "PATCH" || request.httpMethod == "DELETE"
        if mutation, url.host?.hasPrefix("conflict-") == true { deliver(url, 412, "{}"); return }
        if mutation, url.host?.hasPrefix("primaryrace-") == true { deliver(url, 400, "{\"non_field_errors\":[\"Cannot unassign MAC Address while it is designated as the primary MAC for an object\"]}"); return }
        if mutation, url.host?.hasPrefix("denied-") == true { deliver(url, 403, "{}"); return }
        guard let reply = Self.store.response(request) else { deliver(url, 404, "{}"); return }
        if mutation, url.host?.hasPrefix("lost-") == true { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        var body = reply.1
        if mutation, url.host?.hasPrefix("wrongreply-") == true, var object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            if url.path.contains("vlan-groups") { object["name"] = "Wrong reply" }
            object["assigned_object_id"] = 999; object["assigned_object"] = ["id": 999, "name": "Wrong"]
            if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) { body = text }
        }
        deliver(url, reply.0, body)
    }
    private func deliver(_ url: URL, _ status: Int, _ body: String) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class NetworkProtocolStore: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: NetworkWriteFixture] = [:]
    private var primaryChecks: [String: Int] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let host = url.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        if host.hasPrefix("vlandependencyrace-"), URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/api/ipam/prefixes/", url.query?.contains("vlan_id=") == true {
            primaryChecks[host, default: 0] += 1
            if primaryChecks[host, default: 0] > 1 { return (200, "{\"count\":1,\"next\":null,\"results\":[{\"id\":1}]}") }
        }
        if host.hasPrefix("dependencyrace-"), URLComponents(url: url, resolvingAgainstBaseURL: false)?.path == "/api/dcim/interfaces/", url.query?.contains("primary_mac_address_id=14") == true {
            primaryChecks[host, default: 0] += 1
            if primaryChecks[host, default: 0] > 1 { return (200, "{\"count\":1,\"next\":null,\"results\":[{\"id\":501}]}") }
        }
        let fixture = fixtures[host] ?? NetworkWriteFixture(); fixtures[host] = fixture
        return fixture.response(request) ?? ComponentFixture.response(url) ?? InventoryFixture.response(url) ?? IPAMFixture.response(url)
    }
}
