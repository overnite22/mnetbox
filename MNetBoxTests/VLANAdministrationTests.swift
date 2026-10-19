import XCTest
@testable import MNetBox

@MainActor final class VLANAdministrationTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [VLANAdminProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario)-\(UUID().uuidString).test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testTypedPayloadWhitelistAndInputBounds() throws {
        for (kind, field, value, keys) in [(VLANBrowseKind.vlans, VLANAdminField.vid, VLANAdminValue.vid(4094), Set(["vid"])), (.vlans, .site, .reference(nil), Set(["site"])), (.vlans, .group, .reference(.init(id: 31, title: "Group")), Set(["group"])), (.groups, .slug, .slug("mobile-group_1"), Set(["slug"])), (.groups, .tenant, .reference(nil), Set(["tenant"])), (.groups, .ranges, .ranges([[1, 100], [200, 299]]), Set(["vid_ranges"])), (.groups, .scope, .scope(.global, nil), Set(["scope_type", "scope_id"]))] {
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(VLANAdminPayload(kind: kind, field: field, value: value))) as? [String: Any])
            XCTAssertEqual(Set(body.keys), keys)
            if field == .scope { XCTAssertTrue(body["scope_type"] is NSNull); XCTAssertTrue(body["scope_id"] is NSNull) }
        }
        for n in [0, 4095, Int.max] { XCTAssertThrowsError(try VLANAdminValue.vid(n).validate(field: .vid, kind: .vlans)) }
        for text in ["", "with spaces", "é", String(repeating: "a", count: 101)] { XCTAssertThrowsError(try VLANAdminValue.slug(text).validate(field: .slug, kind: .groups)) }
        for ranges in [[], [[1, 100], [100, 200]], [[400, 399]], [[0, 1]]] { XCTAssertThrowsError(try VLANAdminValue.ranges(ranges).validate(field: .ranges, kind: .groups)) }
        XCTAssertThrowsError(try VLANAdminValue.scope(.site, nil).validate(field: .scope, kind: .groups))
        XCTAssertThrowsError(try VLANAdminValue.reference(.init(id: 0, title: "Invalid")).validate(field: .site, kind: .vlans))
        XCTAssertThrowsError(try VLANAdminValue.vid(100).validate(field: .vid, kind: .groups))
    }
    func testEmptyVLANGroupDeletionAndExactConfirmationWithoutRetry() async throws {
        let api = try api(), target = DeletionTarget(collection: .vlanGroups, id: 9021)
        XCTAssertThrowsError(try DeletionTarget(collection: .vlanGroups, id: 0).path)
        let model = DeletionModel(client: api, target: target)
        await model.load(); XCTAssertNotNil(model.snapshot); XCTAssertFalse(model.canDelete)
        model.confirmation = "09021"; XCTAssertFalse(model.canDelete)
        model.confirmation = "9021"; XCTAssertTrue(model.canDelete)
        await model.delete(); XCTAssertTrue(model.deleted); XCTAssertTrue(model.attempted)
        await model.delete(); XCTAssertTrue(model.deleted)
        do { _ = try await api.deletionSnapshot(target); XCTFail("Deleted object still exists") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        await api.close()
    }
    func testOccupiedVLANGroupDeletionBlockedIncludingPagedMembers() async throws {
        let api = try api()
        for id in [31, 9022] {
            let snapshot = try await api.deletionSnapshot(.init(collection: .vlanGroups, id: id))
            XCTAssertTrue(snapshot.blockers.contains("VLANs"))
            do { try await api.deleteObject(snapshot); XCTFail("Occupied group deleted") } catch { XCTAssertEqual(error as? APIError, .deletionBlocked) }
        }
        await api.close()
    }
    func testGroupDeletionMissingMetadataETagAndWrongMembershipFailClosed() async throws {
        for scenario in ["missingfield", "missingetag", "wrongmember", "wrongnext"] {
            let api = try api(scenario)
            do { _ = try await api.deletionSnapshot(.init(collection: .vlanGroups, id: 31)); XCTFail("Unsafe review") } catch {}
            await api.close()
        }
    }
    func testGroupDeletionDeniedConflictLostAndMalformedReplyRetainOneAttempt() async throws {
        for scenario in ["denied", "conflict", "lost", "wrongreply"] {
            let api = try api(scenario), model = DeletionModel(client: api, target: .init(collection: .vlanGroups, id: 9021))
            await model.load(); model.confirmation = "9021"; XCTAssertTrue(model.canDelete)
            await model.delete(); XCTAssertFalse(model.deleted); XCTAssertTrue(model.attempted); XCTAssertNotNil(model.errorMessage)
            await model.delete(); XCTAssertFalse(model.deleted); XCTAssertFalse(model.canDelete)
            await model.checkCurrent(); XCTAssertNotNil(model.errorMessage)
            await api.close()
        }
    }
    func testGroupDeletionNewMemberAfterReviewBlocksDelete() async throws {
        let api = try api("grouprace"), model = DeletionModel(client: api, target: .init(collection: .vlanGroups, id: 9021))
        await model.load(); model.confirmation = "9021"; XCTAssertTrue(model.canDelete)
        await model.delete(); XCTAssertFalse(model.deleted); XCTAssertNotNil(model.errorMessage)
        await api.close()
    }
    func testVIDSiteGroupMovesAndClearsPreserveObjectIdentity() async throws {
        let api = try api()
        for (field, value) in [(VLANAdminField.vid, VLANAdminValue.vid(251)), (.site, .reference(.init(id: 101, title: "Paris"))), (.group, .reference(.init(id: 31, title: "Group"))), (.group, .reference(nil)), (.site, .reference(nil))] {
            let snapshot = try await api.vlanAdminSnapshot(kind: .vlans, id: 9020, field: field)
            let updated = try await api.updateVLANAdministration(snapshot, value: value)
            XCTAssertEqual(updated.record.row.id, 9020); XCTAssertEqual(updated.record.row.name, "Editable VLAN")
            XCTAssertTrue(try updated.record.value(field).matches(value))
        }
        await api.close()
    }
    func testGroupSlugTenantRangesAndAllEightScopes() async throws {
        let api = try api()
        for (field, value) in [(VLANAdminField.slug, VLANAdminValue.slug("renamed-slug")), (.tenant, .reference(.init(id: 1, title: "Tenant"))), (.tenant, .reference(nil)), (.ranges, .ranges([[10, 20], [100, 200]]))] {
            let snapshot = try await api.vlanAdminSnapshot(kind: .groups, id: 9021, field: field)
            let updated = try await api.updateVLANAdministration(snapshot, value: value)
            XCTAssertTrue(try updated.record.value(field).matches(value)); XCTAssertEqual(updated.record.row.name, "Editable group")
        }
        for (scope, id) in [(VLANGroupScope.region, 41), (.siteGroup, 51), (.site, 101), (.location, 61), (.rackGroup, 71), (.rack, 201), (.clusterGroup, 81), (.cluster, 9), (.global, 0)] {
            let snapshot = try await api.vlanAdminSnapshot(kind: .groups, id: 9021, field: .scope)
            let value = VLANAdminValue.scope(scope, id == 0 ? nil : .init(id: id, title: "Scope"))
            let updated = try await api.updateVLANAdministration(snapshot, value: value)
            XCTAssertEqual(updated.record.row.scopeType, scope == .global ? nil : scope.rawValue); XCTAssertEqual(updated.record.row.scopeID, id == 0 ? nil : id)
        }
        await api.close()
    }
    func testDependenciesDuplicateVIDAndIncompatibleSiteBlockVLANChanges() async throws {
        let api = try api()
        let occupied = try await api.vlanAdminSnapshot(kind: .vlans, id: 1, field: .vid)
        do { try await api.checkVLANAdministration(occupied, value: .vid(101)); XCTFail("Dependencies") } catch { XCTAssertEqual(error as? APIError, .vlanIdentityBlocked) }
        let empty = try await api.vlanAdminSnapshot(kind: .vlans, id: 9020, field: .vid)
        do { try await api.checkVLANAdministration(empty, value: .vid(100)); XCTFail("Duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateVLAN) }
        let group = try await api.vlanAdminSnapshot(kind: .vlans, id: 9020, field: .group)
        let grouped = try await api.updateVLANAdministration(group, value: .reference(.init(id: 31, title: "Paris group")))
        let site = try await api.vlanAdminSnapshot(kind: .vlans, id: grouped.record.row.id, field: .site)
        do { try await api.checkVLANAdministration(site, value: .reference(.init(id: 102, title: "Other"))); XCTFail("Incompatible site") } catch { XCTAssertEqual(error as? APIError, .invalidReference) }
        let vid = try await api.vlanAdminSnapshot(kind: .vlans, id: 9020, field: .vid)
        do { try await api.checkVLANAdministration(vid, value: .vid(350)); XCTFail("Outside ranges") } catch { XCTAssertEqual(error as? APIError, .invalidVID) }
        await api.close()
    }
    func testGroupMembersPreventShrinkingRangesAndScopeMoves() async throws {
        let api = try api()
        let ranges = try await api.vlanAdminSnapshot(kind: .groups, id: 31, field: .ranges)
        do { try await api.checkVLANAdministration(ranges, value: .ranges([[1, 199]])); XCTFail("Excluded member") } catch { XCTAssertEqual(error as? APIError, .groupMembersBlocked) }
        let valid = try await api.updateVLANAdministration(ranges, value: .ranges([[1, 4094]])); XCTAssertEqual(valid.record.row.vidRanges, [[1, 4094]])
        let paged = try await api.vlanAdminSnapshot(kind: .groups, id: 9022, field: .ranges)
        do { try await api.checkVLANAdministration(paged, value: .ranges([[1, 3999]])); XCTFail("Third-page member excluded") } catch { XCTAssertEqual(error as? APIError, .groupMembersBlocked) }
        _ = try await api.updateVLANAdministration(paged, value: .ranges([[1, 4000]]))
        let scope = try await api.vlanAdminSnapshot(kind: .groups, id: 31, field: .scope)
        do { try await api.checkVLANAdministration(scope, value: .scope(.global, nil)); XCTFail("Nonempty") } catch { XCTAssertEqual(error as? APIError, .groupMembersBlocked) }
        await api.close()
    }
    func testGroupUniquenessExcludesOnlyExactIDAndCurrentScope() async throws {
        let api = try api()
        let group = try await api.vlanAdminSnapshot(kind: .groups, id: 9021, field: .slug)
        do { try await api.checkVLANAdministration(group, value: .slug("group-34")); XCTFail("Global duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateVLANGroup) }
        // The same slug in another exact scope is legal.
        let updated = try await api.updateVLANAdministration(group, value: .slug("group-31")); XCTAssertEqual(updated.record.row.slug, "group-31")
        let scope = try await api.vlanAdminSnapshot(kind: .groups, id: 9021, field: .scope)
        do { try await api.checkVLANAdministration(scope, value: .scope(.site, .init(id: 101, title: "Paris"))); XCTFail("Destination slug collision") } catch { XCTAssertEqual(error as? APIError, .duplicateVLANGroup) }
        await api.close()
    }
    func testDeniedConflictUncertainAndAlteredRepliesKeepDraftWithoutRetry() async throws {
        for scenario in ["denied", "conflict", "lost", "wrongreply"] {
            let api = try api(scenario), model = VLANAdminModel(client: api, kind: .vlans, id: 9020, field: .vid)
            await model.load(); model.text = "251"; await model.review(); XCTAssertNotNil(model.reviewed)
            await model.save(); XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertNotNil(model.errorMessage)
            await model.save(); XCTAssertFalse(model.canReview); XCTAssertEqual(model.text, "251")
            await api.close()
        }
    }
    func testDependencyRaceAfterReviewBlocksPATCH() async throws {
        let api = try api("dependencyrace"), model = VLANAdminModel(client: api, kind: .vlans, id: 9020, field: .vid)
        await model.load(); model.text = "251"; await model.review(); XCTAssertNotNil(model.reviewed)
        await model.save(); XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertEqual(model.errorMessage, APIError.vlanIdentityBlocked.localizedDescription)
        await api.close()
    }
    func testMissingMetadataETagReferencesAndUnknownScopesFailClosed() async throws {
        for scenario in ["missingfield", "missingetag", "unknownscope"] {
            let api = try api(scenario)
            do { _ = try await api.vlanAdminSnapshot(kind: .groups, id: 9021, field: .scope); XCTFail("Incomplete contract") } catch {}
            await api.close()
        }
        let api = try api(), snapshot = try await api.vlanAdminSnapshot(kind: .vlans, id: 9020, field: .group)
        do { try await api.checkVLANAdministration(snapshot, value: .reference(.init(id: 9999, title: "Missing"))); XCTFail("Absent reference") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        await api.close()
    }
    func testPaginationContextMismatchAndMemberCountMismatchBlockReview() async throws {
        for scenario in ["wrongnext", "wrongmember"] {
            let api = try api(scenario)
            let snapshot = try await api.vlanAdminSnapshot(kind: .groups, id: 31, field: .ranges)
            do { try await api.checkVLANAdministration(snapshot, value: .ranges([[1, 4094]])); XCTFail("Malformed context") } catch {}
            await api.close()
        }
    }
}

private final class VLANAdminProtocol: URLProtocol, @unchecked Sendable {
    private static let store = VLANAdminStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let mutation = request.httpMethod == "PATCH" || request.httpMethod == "DELETE", host = url.host ?? ""
        if mutation, host.hasPrefix("denied-") { deliver(url, 403, "{}"); return }
        if mutation, host.hasPrefix("conflict-") { deliver(url, 412, "{}"); return }
        guard let reply = Self.store.response(request) else { deliver(url, 404, "{}"); return }
        if mutation, host.hasPrefix("lost-") { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        var body = mutation && host.hasPrefix("wrongreply-") && request.httpMethod == "DELETE" ? "{}" : reply.1
        if var row = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            if mutation, host.hasPrefix("wrongreply-") { row["description"] = "Unexpected side effect" }
            if host.hasPrefix("missingfield-") { row.removeValue(forKey: "scope_id") }
            if host.hasPrefix("unknownscope-") { row["scope_type"] = "plugin.scope"; row["scope_id"] = 77; row["scope"] = ["id": 77, "name": "Unknown"] }
            if url.lastPathComponent == "vlans", host.hasPrefix("wrongmember-") { row["count"] = 0; row["results"] = []; row["next"] = NSNull() }
            if url.lastPathComponent == "vlans", host.hasPrefix("wrongnext-") { row["next"] = "https://\(host)/api/ipam/vlans/?group_id=32&ordering=id&limit=50" }
            body = (try? JSONSerialization.data(withJSONObject: row)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        deliver(url, reply.0, body)
    }
    private func deliver(_ url: URL, _ status: Int, _ body: String) {
        let headers = url.host?.hasPrefix("missingetag-") == true ? ["Content-Type": "application/json"] : ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class VLANAdminStore: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: VLANAdministrationFixture] = [:]
    private var calls: [String: Int] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let host = url.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        let fixture = fixtures[host] ?? VLANAdministrationFixture(); fixtures[host] = fixture
        if host.hasPrefix("grouprace-"), url.lastPathComponent == "vlans", URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "group_id" }) == true {
            calls[host, default: 0] += 1
            if calls[host, default: 0] >= 2 { return (200, "{\"count\":1,\"next\":null,\"results\":[{\"id\":9030,\"vid\":10,\"name\":\"New member\",\"group\":{\"id\":9021,\"name\":\"Editable group\"}}]}") }
        }
        if host.hasPrefix("dependencyrace-"), url.lastPathComponent == "interfaces" && url.path.contains("/dcim/"), URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "vlan_id" && $0.value == "9020" }) == true {
            calls[host, default: 0] += 1
            if calls[host, default: 0] >= 2 { return (200, "{\"count\":1,\"next\":null,\"results\":[{\"id\":501}]}") }
        }
        return fixture.response(request) ?? ComponentFixture.response(url) ?? InventoryFixture.response(url)
    }
}
