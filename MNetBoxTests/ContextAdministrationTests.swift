import XCTest
@testable import MNetBox

@MainActor final class ContextAdministrationTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ContextAdminProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario)-\(UUID().uuidString).test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    private func plan(_ kind: ContextKind, name: String = "Mobile context", slug: String = "mobile-context", rd: String = "64512:99", group: ReferenceSelection? = nil) -> ContextCreationPlan {
        .init(kind: kind, name: name, slug: slug, rd: rd, unique: true, tenant: kind == .vrfs ? .init(id: 1, title: "Tenant") : nil, group: group, weight: 50, description: "Synthetic new context", comments: "Notes")
    }
    func testCreationWhitelistsAndPortableFieldBounds() throws {
        for (kind, keys) in [(ContextKind.vrfs, Set(["name", "rd", "enforce_unique", "tenant", "description", "comments"])), (.tenants, Set(["name", "slug", "group", "description", "comments"])), (.roles, Set(["name", "slug", "weight", "description", "comments"]))] {
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan(kind))) as? [String: Any]); XCTAssertEqual(Set(body.keys), keys)
        }
        XCTAssertThrowsError(try plan(.clusters).validate())
        XCTAssertThrowsError(try plan(.vrfs, name: String(repeating: "x", count: 101)).validate())
        XCTAssertThrowsError(try plan(.tenants, slug: "invalid slug").validate())
        XCTAssertThrowsError(try plan(.vrfs, rd: String(repeating: "1", count: 22)).validate())
        XCTAssertThrowsError(try ContextEditValue.number(32768).validate(field: .weight, kind: .roles))
        XCTAssertThrowsError(try ContextEditValue.reference(.init(id: 0, title: "Bad")).validate(field: .group, kind: .tenants))
        XCTAssertThrowsError(try ContextEditValue.text("").validate(field: .name, kind: .vrfs))
    }
    func testCreationForAllThreeKindsVerifiesReferencesAndReply() async throws {
        let api = try api()
        for kind in [ContextKind.vrfs, .tenants, .roles] {
            let proposal = plan(kind, group: kind == .tenants ? .init(id: 51, title: "Customers") : nil)
            let created = try await api.createContext(proposal); XCTAssertGreaterThan(created.row.id, 0); XCTAssertTrue(proposal.matches(created))
        }
        let nullable = try await api.createContext(plan(.vrfs, name: "VRF without RD", rd: "")); XCTAssertNil(nullable.row.rd)
        await api.close()
    }
    func testEveryMetadataEditPreservesRoutingAndObjectIdentity() async throws {
        let api = try api()
        for (kind, id, field, value) in [(ContextKind.vrfs, 7, ContextEditField.name, ContextEditValue.text("Renamed VRF")), (.vrfs, 7, .description, .text("New description")), (.vrfs, 7, .comments, .text("First\nSecond")), (.vrfs, 7, .tenant, .reference(nil)), (.tenants, 1, .slug, .text("renamed-tenant")), (.tenants, 1, .group, .reference(.init(id: 51, title: "Customers"))), (.tenants, 1, .group, .reference(nil)), (.roles, 1, .name, .text("LAN edited")), (.roles, 1, .weight, .number(0))] {
            let before = try await api.contextEditSnapshot(kind: kind, id: id, field: field)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(ContextEditPayload(kind: kind, field: field, value: value))) as? [String: Any]); XCTAssertEqual(Set(body.keys), [field.rawValue])
            let updated = try await api.updateContext(before, value: value)
            XCTAssertTrue(try updated.record.value(field).matches(value)); XCTAssertEqual(updated.record.row.id, id)
            XCTAssertEqual(updated.record.row.rd, before.record.row.rd); XCTAssertEqual(updated.record.row.enforceUnique, before.record.row.enforceUnique)
        }
        await api.close()
    }
    func testDuplicateNamesSlugsAndRDRespectTenantGroupIdentity() async throws {
        let api = try api()
        for p in [plan(.vrfs, name: "Blue", rd: "64512:99"), plan(.vrfs, name: "Unique name", rd: "64512:7"), plan(.roles, name: "LAN"), plan(.tenants, name: "Example tenant")] {
            do { try await api.checkContextCreation(p); XCTFail("Duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateContext) }
        }
        // Same tenant name in another group is allowed.
        _ = try await api.createContext(plan(.tenants, name: "Example tenant", group: .init(id: 51, title: "Customers")))
        let tenant = try await api.contextEditSnapshot(kind: .tenants, id: 1, field: .group)
        do { try await api.checkContextEdit(tenant, value: .reference(.init(id: 51, title: "Customers"))); XCTFail("Destination duplicate") } catch { XCTAssertEqual(error as? APIError, .duplicateContext) }
        await api.close()
    }
    func testMissingFreshReferenceBlocksCreationAndEdit() async throws {
        let api = try api()
        do { _ = try await api.createContext(plan(.tenants, group: .init(id: 9999, title: "Missing"))); XCTFail("Missing") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        let snapshot = try await api.contextEditSnapshot(kind: .vrfs, id: 7, field: .tenant)
        do { try await api.checkContextEdit(snapshot, value: .reference(.init(id: 9999, title: "Missing"))); XCTFail("Missing") } catch { if case APIError.http(404, _) = error {} else { XCTFail("Expected 404") } }
        await api.close()
    }
    func testDeniedConflictLostAndWrongRepliesRetainEditDraft() async throws {
        for scenario in ["denied", "conflict", "lost", "wrongreply"] {
            let api = try api(scenario), model = ContextEditModel(client: api, kind: .vrfs, id: 7, field: .name)
            await model.load(); model.text = "New VRF name"; await model.review(); XCTAssertNotNil(model.reviewed)
            await model.save(); XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertEqual(model.text, "New VRF name")
            await model.save(); XCTAssertFalse(model.canReview); await api.close()
        }
    }
    func testCreationUncertaintyNeverAutomaticallyRetriesAndSavedObjectCanBeChecked() async throws {
        for scenario in ["denied", "lost", "wrongreply"] {
            let api = try api(scenario), model = ContextCreateModel(client: api, kind: .tenants)
            model.name = "Created tenant"; model.slug = "created-tenant"; await model.review(); XCTAssertNotNil(model.reviewed)
            await model.save(); XCTAssertTrue(model.attempted); XCTAssertNil(model.created); XCTAssertNotNil(model.errorMessage)
            await model.save(); XCTAssertFalse(model.canReview); XCTAssertEqual(model.name, "Created tenant")
            if scenario == "lost" { let page = try await ContextService(client: api, kind: .tenants).page(query: .init(search: "Created tenant"), next: nil); XCTAssertEqual(page.count, 1) }
            await api.close()
        }
    }
    func testUnusedVRFAndRoleDeletionAndNoAutomaticRetry() async throws {
        for (collection, id) in [(DeletionTarget.Collection.vrfs, 9), (.ipamRoles, 1)] {
            let api = try api(), model = DeletionModel(client: api, target: .init(collection: collection, id: id))
            await model.load(); XCTAssertNotNil(model.snapshot); XCTAssertTrue(model.snapshot?.blockers.isEmpty == true)
            model.confirmation = String(id); await model.delete(); XCTAssertTrue(model.deleted)
            await model.delete(); await api.close()
        }
    }
    func testContextDeletionDeniedConflictLostAndMissingETag() async throws {
        for scenario in ["denied", "conflict", "lost", "missingetag"] {
            let api = try api(scenario), model = DeletionModel(client: api, target: .init(collection: .ipamRoles, id: 1))
            await model.load()
            if scenario == "missingetag" { XCTAssertNil(model.snapshot); XCTAssertNotNil(model.errorMessage) }
            else { model.confirmation = "1"; await model.delete(); XCTAssertTrue(model.attempted); XCTAssertFalse(model.deleted); XCTAssertNotNil(model.errorMessage); await model.delete() }
            await api.close()
        }
    }
    func testRoleASNDependenciesWrongFilterAndRaceBlockDeletion() async throws {
        for scenario in ["dependent", "wrongdependency", "missingdependency", "racedependency"] {
            let api = try api(scenario), model = DeletionModel(client: api, target: .init(collection: .ipamRoles, id: 1))
            await model.load()
            if scenario == "wrongdependency" || scenario == "missingdependency" { XCTAssertNil(model.snapshot); XCTAssertNotNil(model.errorMessage) }
            else if scenario == "dependent" { XCTAssertEqual(model.snapshot?.blockers, ["ipam/asns/"]); XCTAssertFalse(model.canDelete) }
            else { XCTAssertTrue(model.snapshot?.blockers.isEmpty == true); model.confirmation = "1"; await model.delete(); XCTAssertFalse(model.deleted); XCTAssertNotNil(model.errorMessage) }
            let row = try await ContextService(client: api, kind: .roles).detail(id: 1); XCTAssertEqual(row.id, 1)
            await api.close()
        }
    }
    func testVRFWithRouteTargetsCannotBeDeleted() async throws {
        let api = try api(), model = DeletionModel(client: api, target: .init(collection: .vrfs, id: 7))
        await model.load(); XCTAssertEqual(model.snapshot?.blockers, ["Route targets"])
        model.confirmation = "7"; await model.delete(); XCTAssertFalse(model.attempted)
        await api.close()
    }
    func testMissingOrNonzeroAnnotatedCountBlocksRoleDeletion() async throws {
        for scenario in ["missingcount", "hiddenasn"] {
            let api = try api(scenario), model = DeletionModel(client: api, target: .init(collection: .ipamRoles, id: 1))
            await model.load()
            if scenario == "missingcount" { XCTAssertNil(model.snapshot); XCTAssertNotNil(model.errorMessage) }
            else { XCTAssertEqual(model.snapshot?.blockers, ["ipam/asns/"]) }
            model.confirmation = "1"; await model.delete(); XCTAssertFalse(model.attempted)
            await api.close()
        }
    }
    func testMissingMetadataETagAndFilteredWrongRowsFailClosed() async throws {
        for scenario in ["missingfield", "missingetag"] {
            let api = try api(scenario)
            do { _ = try await api.contextEditSnapshot(kind: .vrfs, id: 7, field: .name); XCTFail("Missing contract") } catch {}
            await api.close()
        }
        let api = try api("wrongfilter")
        do { try await api.checkContextCreation(plan(.vrfs)); XCTFail("Wrong filter") } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        await api.close()
    }
}

private final class ContextAdminProtocol: URLProtocol, @unchecked Sendable {
    private static let store = ContextAdminStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }; let host = url.host ?? "", mutation = request.httpMethod != "GET"
        if mutation && host.hasPrefix("denied-") { deliver(url, 403, "{}"); return }
        if mutation && host.hasPrefix("conflict-") { deliver(url, 412, "{}"); return }
        guard let reply = Self.store.response(request) else { deliver(url, 404, "{}"); return }
        if mutation && host.hasPrefix("lost-") { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        var body = reply.1
        if var row = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] {
            if mutation && host.hasPrefix("wrongreply-") { row["comments"] = "Wrong reply" }
            if host.hasPrefix("missingfield-") { row.removeValue(forKey: "enforce_unique") }
            if row["weight"] != nil, host.hasPrefix("missingcount-") { row.removeValue(forKey: "asn_count") }
            if row["weight"] != nil, host.hasPrefix("hiddenasn-") { row["asn_count"] = 1 }
            if host.hasPrefix("wrongfilter-") { row["count"] = 1; row["next"] = NSNull(); row["results"] = ContextFixture.records(.vrfs).prefix(1).map { original in var row = original; row["rd"] = "64512:7"; row["enforce_unique"] = true; row["import_targets"] = []; row["export_targets"] = []; return row } }
            body = (try? JSONSerialization.data(withJSONObject: row)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }
        deliver(url, reply.0, body)
    }
    private func deliver(_ url: URL, _ status: Int, _ body: String) {
        let headers = url.host?.hasPrefix("missingetag-") == true ? ["Content-Type": "application/json"] : ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class ContextAdminStore: @unchecked Sendable {
    private let lock = NSLock(); private var fixtures: [String: ContextAdministrationFixture] = [:]
    private var dependencyReads: [String: Int] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let host = url.host else { return nil }; lock.lock(); defer { lock.unlock() }
        let fixture = fixtures[host] ?? ContextAdministrationFixture(); fixtures[host] = fixture
        if let empty = ContextDeletionFixture.response(request) {
            dependencyReads[host, default: 0] += 1
            if url.path.contains("/asns"), host.hasPrefix("dependent-") || host.hasPrefix("wrongdependency-") || host.hasPrefix("missingdependency-") || (host.hasPrefix("racedependency-") && dependencyReads[host, default: 0] > 4) {
                let role: Any = host.hasPrefix("wrongdependency-") ? ["id": 999] : ["id": 1]
                var row: [String: Any] = ["id": 55, "role": role]
                if host.hasPrefix("missingdependency-") { row.removeValue(forKey: "role") }
                let page: [String: Any] = ["count": 1, "next": NSNull(), "results": [row]]
                return (200, String(decoding: (try? JSONSerialization.data(withJSONObject: page)) ?? Data(), as: UTF8.self))
            }
            return empty
        }
        return fixture.response(request) ?? ComponentFixture.response(url) ?? InventoryFixture.response(url)
    }
}
