import XCTest
@testable import MNetBox

@MainActor final class IPAMAdministrationTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AdministrationProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario)-\(UUID().uuidString).test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testPrefixRelationPayloadsWhitelistIDsAndAtomicScopeClear() throws {
        for (field, value, keys) in [(IPAMEditField.vlan, IPAMEditValue.reference(.init(id: 22, title: "VLAN")), Set(["vlan"])), (.role, .reference(nil), Set(["role"])), (.scope, .scope(.global, nil), Set(["scope_type", "scope_id"]))] {
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(IPAMEditPayload(kind: .prefixes, field: field, value: value))) as? [String: Any])
            XCTAssertEqual(Set(body.keys), keys)
            if field == .scope { XCTAssertTrue(body["scope_type"] is NSNull); XCTAssertTrue(body["scope_id"] is NSNull) }
        }
        for text in ["0.0.0.0/0", "::/0"] {
            for kind in [IPAMKind.prefixes, .ipAddresses] {
                XCTAssertThrowsError(try IPAMEditValue.cidr(IPAMCIDR(text, network: kind == .prefixes)).validate(field: .cidr, kind: kind))
                XCTAssertThrowsError(try IPAMCreationDraft(kind: kind, cidr: text).plan())
            }
        }
        XCTAssertThrowsError(try IPAMEditValue.scope(.site, nil).validate(field: .scope, kind: .prefixes))
        XCTAssertThrowsError(try IPAMEditValue.scope(.global, .init(id: 101, title: "Site")).validate(field: .scope, kind: .prefixes))
        XCTAssertThrowsError(try IPAMEditValue.reference(.init(id: 0, title: "Invalid")).validate(field: .vlan, kind: .prefixes))
        XCTAssertThrowsError(try IPAMEditValue.reference(nil).validate(field: .vlan, kind: .ipAddresses))
    }
    func testAllPrefixScopesAndVLANRoleChangesPreserveCIDRVRF() async throws {
        let api = try api()
        for (type, id) in [(PrefixScope.region, 41), (.siteGroup, 51), (.site, 101), (.location, 61)] {
            let snapshot = try await api.ipamEditSnapshot(kind: .prefixes, id: 1, field: .scope)
            let updated = try await api.updateIPAM(snapshot, value: .scope(type, .init(id: id, title: "Scope")))
            XCTAssertEqual(updated.record.object.scopeType, type.rawValue); XCTAssertEqual(updated.record.scopeID, id)
            XCTAssertEqual(updated.record.object.prefix, "192.0.2.0/24"); XCTAssertNil(updated.record.object.vrf)
        }
        let scope = try await api.ipamEditSnapshot(kind: .prefixes, id: 1, field: .scope)
        let cleared = try await api.updateIPAM(scope, value: .scope(.global, nil)); XCTAssertNil(cleared.record.object.scopeType); XCTAssertNil(cleared.record.scopeID)
        for (field, id) in [(IPAMEditField.vlan, 22), (.role, 2)] {
            let before = try await api.ipamEditSnapshot(kind: .prefixes, id: 1, field: field)
            let after = try await api.updateIPAM(before, value: .reference(.init(id: id, title: "Reference")))
            XCTAssertTrue(try after.record.value(field, kind: .prefixes).matches(.reference(.init(id: id, title: "Reference"))))
            XCTAssertEqual(after.record.object.prefix, before.record.object.prefix)
            let null = try await api.updateIPAM(after, value: .reference(nil)); XCTAssertTrue(try null.record.value(field, kind: .prefixes).matches(.reference(nil)))
        }
        await api.close()
    }
    func testMissingReferencesBlockReview() async throws {
        let api = try api()
        for field in [IPAMEditField.vlan, .role, .scope] {
            let snapshot = try await api.ipamEditSnapshot(kind: .prefixes, id: 1, field: field)
            let value: IPAMEditValue = field == .scope ? .scope(.site, .init(id: 9999, title: "Absent")) : .reference(.init(id: 9999, title: "Absent"))
            do { try await api.checkIPAMEdit(snapshot, value: value); XCTFail("Missing reference") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        }
        await api.close()
    }
    func testAddressAndVRFOneFieldPayloadsAndSameHostMaskEdit() async throws {
        let api = try api()
        for (kind, id, text) in [(IPAMKind.prefixes, 9005, "203.0.113.0/27"), (.ipAddresses, 9006, "203.0.113.99/32"), (.prefixes, 9007, "2001:db8:abce::/64"), (.ipAddresses, 9008, "2001:db8:ffff::100/128")] {
            let snapshot = try await api.ipamEditSnapshot(kind: kind, id: id, field: .cidr)
            let value = IPAMEditValue.cidr(try IPAMCIDR(text, network: kind == .prefixes))
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(IPAMEditPayload(kind: kind, field: .cidr, value: value))) as? [String: Any])
            XCTAssertEqual(Set(body.keys), [kind == .prefixes ? "prefix" : "address"])
            let updated = try await api.updateIPAM(snapshot, value: value); XCTAssertEqual(updated.record.object.title, text)
            let vrf = try await api.ipamEditSnapshot(kind: kind, id: id, field: .vrf)
            let moved = try await api.updateIPAM(vrf, value: .reference(.init(id: 7, title: "Blue")))
            XCTAssertEqual(moved.record.object.vrf?.id, 7); XCTAssertEqual(moved.record.object.title, text)
            let cleared = try await api.updateIPAM(moved, value: .reference(nil)); XCTAssertNil(cleared.record.object.vrf)
        }
        await api.close()
    }
    func testAssignmentPrimaryContainedObjectsAndDestinationBlockMoves() async throws {
        let api = try api()
        for (kind, id) in [(IPAMKind.prefixes, 1), (.ipAddresses, 11), (.ipAddresses, 12)] {
            let snapshot = try await api.ipamEditSnapshot(kind: kind, id: id, field: .vrf)
            do { try await api.checkIPAMEdit(snapshot, value: .reference(.init(id: 7, title: "Blue"))); XCTFail("Dependencies") } catch { XCTAssertEqual(error as? APIError, .ipamMoveBlocked) }
        }
        let prefix = try await api.ipamEditSnapshot(kind: .prefixes, id: 9005, field: .cidr)
        do { try await api.checkIPAMEdit(prefix, value: .cidr(try IPAMCIDR("192.0.2.0/23", network: true))); XCTFail("Destination has children") } catch { XCTAssertEqual(error as? APIError, .ipamMoveBlocked) }
        let ip = try await api.ipamEditSnapshot(kind: .ipAddresses, id: 9006, field: .cidr)
        do { try await api.checkIPAMEdit(ip, value: .cidr(try IPAMCIDR("192.0.2.10/32", network: false))); XCTFail("Duplicate host ignoring mask") } catch { XCTAssertEqual(error as? APIError, .duplicateIPAM) }
        do { try await api.checkIPAMEdit(ip, value: .cidr(try IPAMCIDR("2001:db8::99/64", network: false))); XCTFail("Family") } catch { XCTAssertEqual(error as? APIError, .invalidCIDR) }
        await api.close()
    }
    func testDeniedConflictLostAndWrongRepliesRetainDraftAndRequireReload() async throws {
        for scenario in ["denied", "conflict", "lost", "wrongreply"] {
            let api = try api(scenario), model = IPAMEditModel(client: api, kind: .ipAddresses, id: 9006, field: .cidr)
            await model.load(); model.cidr = "203.0.113.100/24"; await model.review(); XCTAssertNotNil(model.reviewed)
            await model.save(); XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertNotNil(model.errorMessage)
            await model.save(); XCTAssertFalse(model.canReview); XCTAssertEqual(model.cidr, "203.0.113.100/24")
            await api.close()
        }
    }
    func testFreshDependencyAppearingAfterPreviewBlocksMovement() async throws {
        let api = try api("dependencyrace"), model = IPAMEditModel(client: api, kind: .ipAddresses, id: 9006, field: .cidr)
        await model.load(); model.cidr = "203.0.113.100/24"; await model.review(); XCTAssertNotNil(model.reviewed)
        await model.save(); XCTAssertFalse(model.saved); XCTAssertEqual(model.errorMessage, APIError.ipamMoveBlocked.localizedDescription)
        await api.close()
    }
    func testMissingAndUnsupportedScopeMetadataFailsClosed() throws {
        var row = IPAMFixture.recordsForCreation(.prefixes)[0]
        for key in ["scope_id", "vrf", "vlan", "role", "children"] {
            var invalid = row; invalid.removeValue(forKey: key)
            do { let value = try JSONDecoder().decode(IPAMEditRecord.self, from: JSONSerialization.data(withJSONObject: invalid)); try value.validate(kind: .prefixes, id: 1); XCTFail("Missing field") } catch {}
        }
        row["scope_type"] = "plugin.scope"
        let unknown = try JSONDecoder().decode(IPAMEditRecord.self, from: JSONSerialization.data(withJSONObject: row))
        try unknown.validate(kind: .prefixes, id: 1)
        XCTAssertThrowsError(try unknown.value(.scope, kind: .prefixes))
    }
    func testCablePagesScopesFiltersAndMalformedNext() async throws {
        let api = try api(), service = CableService(client: api, deviceID: 301)
        let first = try await service.page(query: .init(search: "Synthetic", status: "connected"), next: nil)
        XCTAssertEqual(first.count, 3); XCTAssertEqual(first.results.map(\.id), [701, 702])
        let second = try await service.page(query: .init(search: "Synthetic", status: "connected"), next: XCTUnwrap(first.next))
        XCTAssertEqual(second.results.map(\.id), [704])
        let empty = try await service.page(query: .init(unterminated: true), next: nil); XCTAssertEqual(empty.results.map(\.id), [702])
        do { _ = try await service.page(query: .init(status: "connected"), next: "https://example.test/api/dcim/cables/?device_id=302&status=connected&ordering=id"); XCTFail("Changed scope") } catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        await api.close()
    }
    func testCableAllTerminationsUnknownTypesAndIdentityValidation() throws {
        let body = try JSONSerialization.data(withJSONObject: CableBrowseFixture.rows[0])
        let row = try JSONDecoder().decode(CableObject.self, from: body); try row.validate()
        XCTAssertEqual(row.aTerminations?.count, 1); XCTAssertEqual(row.bTerminations?.count, 2); XCTAssertEqual(row.bTerminations?.last?.objectType, "dcim.frontport")
        var wrong = CableBrowseFixture.rows[0]; wrong["a_terminations"] = [["object_type": "dcim.interface", "object_id": 501, "object": ["id": 999]]]
        XCTAssertThrowsError(try JSONDecoder().decode(CableObject.self, from: JSONSerialization.data(withJSONObject: wrong)).validate())
        wrong.removeValue(forKey: "a_terminations")
        XCTAssertThrowsError(try JSONDecoder().decode(CableObject.self, from: JSONSerialization.data(withJSONObject: wrong)).validate())
    }
}

private final class AdministrationProtocol: URLProtocol, @unchecked Sendable {
    private static let store = AdministrationStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let mutation = request.httpMethod == "PATCH"
        if mutation, url.host?.hasPrefix("denied-") == true { deliver(url, 403, "{}"); return }
        if mutation, url.host?.hasPrefix("conflict-") == true { deliver(url, 412, "{}"); return }
        guard let reply = Self.store.response(request) else { deliver(url, 404, "{}"); return }
        if mutation, url.host?.hasPrefix("lost-") == true { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        var body = reply.1
        if mutation, url.host?.hasPrefix("wrongreply-") == true, var row = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            row["vrf"] = ["id": 999, "name": "Wrong VRF"]
            if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { body = text }
        }
        deliver(url, reply.0, body)
    }
    private func deliver(_ url: URL, _ status: Int, _ body: String) {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class AdministrationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var fixtures: [String: IPAMAdministrationFixture] = [:]
    private var calls: [String: Int] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let host = url.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        let fixture = fixtures[host] ?? IPAMAdministrationFixture(); fixtures[host] = fixture
        if host.hasPrefix("dependencyrace-"), url.path.contains("/ipam/ip-addresses/9006") {
            calls[host, default: 0] += 1
            if calls[host, default: 0] >= 4, let reply = fixture.response(request), var row = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] {
                row["nat_inside"] = ["id": 11, "address": "192.0.2.10/24"]
                if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { return (200, text) }
            }
        }
        if ["ip-ranges", "fhrp-groups"].contains(url.lastPathComponent) { return (200, "{\"count\":0,\"next\":null,\"results\":[]}") }
        return fixture.response(request) ?? ComponentFixture.response(url) ?? InventoryFixture.response(url)
    }
}
