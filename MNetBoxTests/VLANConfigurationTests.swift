import XCTest
@testable import MNetBox

@MainActor final class VLANConfigurationTests: XCTestCase {
    private func api(_ scenario: String) throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VLANWriteProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "synthetic-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    private let physical = StructuredEditTarget(collection: .physicalInterfaces, id: 501, parentID: 301)
    private let virtual = StructuredEditTarget(collection: .virtualInterfaces, id: 801, parentID: 401)
    func testPayloadIsAtomicAndExplicitlyClearsFields() throws {
        for plan in [VLANPlan(mode: "", untagged: nil, tagged: []), VLANPlan(mode: "tagged", untagged: ReferenceSelection(id: 22, title: "Paris"), tagged: [ReferenceSelection(id: 21, title: "Global")])] {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["mode", "untagged_vlan", "tagged_vlans"])
            XCTAssertEqual(body["tagged_vlans"] as? [Int], plan.tagged.map(\.id))
            if plan.untagged == nil { XCTAssertTrue(body["untagged_vlan"] is NSNull) }
        }
        let invalid = [VLANPlan(mode: "q-in-q", untagged: nil, tagged: []),
                       VLANPlan(mode: "", untagged: ReferenceSelection(id: 21, title: "Global"), tagged: []),
                       VLANPlan(mode: "access", untagged: nil, tagged: [ReferenceSelection(id: 21, title: "Global")]),
                       VLANPlan(mode: "tagged-all", untagged: nil, tagged: [ReferenceSelection(id: 21, title: "Global")]),
                       VLANPlan(mode: "tagged", untagged: nil, tagged: [ReferenceSelection(id: 21, title: "Global"), ReferenceSelection(id: 21, title: "Duplicate")]),
                       VLANPlan(mode: "access", untagged: ReferenceSelection(id: 0, title: "Invalid"), tagged: [])]
        for plan in invalid { XCTAssertThrowsError(try JSONEncoder().encode(plan)) }
    }
    func testPhysicalSiteAndVMGlobalConfiguration() async throws {
        for (scenario, target, plan) in [
            ("physical", physical, VLANPlan(mode: "tagged", untagged: ReferenceSelection(id: 22, title: "Paris"), tagged: [ReferenceSelection(id: 21, title: "Global")])),
            ("virtual", virtual, VLANPlan(mode: "access", untagged: ReferenceSelection(id: 21, title: "Global"), tagged: []))] {
            let client = try api(scenario)
            let snapshot = try await client.vlanSnapshot(target: target)
            let object = try await client.updateVLAN(snapshot, to: plan)
            XCTAssertTrue(object.plan.matches(plan))
            let requests = VLANWriteProtocol.state.bodies(scenario)
            XCTAssertEqual(requests.count, 1)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first)) as? [String: Any])
            XCTAssertEqual(Set(body.keys), ["mode", "untagged_vlan", "tagged_vlans"])
            await client.close()
        }
    }
    func testForeignSiteAndVMWithoutSiteRejectSiteVLAN() async throws {
        for (scenario, target, vlanID) in [("foreign", physical, 23), ("nosite", virtual, 22)] {
            let client = try api(scenario)
            let snapshot = try await client.vlanSnapshot(target: target)
            do { _ = try await client.updateVLAN(snapshot, to: VLANPlan(mode: "access", untagged: ReferenceSelection(id: vlanID, title: "Invalid site"), tagged: [])); XCTFail("Foreign-site VLAN accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidReference) }
            XCTAssertTrue(VLANWriteProtocol.state.bodies(scenario).isEmpty)
            await client.close()
        }
    }
    func testUnsupportedAndMissingMetadataBlockSnapshot() async throws {
        for (scenario, expected) in [("qinq", APIError.unsupportedVLANConfiguration), ("translation", .unsupportedVLANConfiguration), ("unknown", .unsupportedVLANConfiguration), ("missingvlan", .decoding), ("missingsite", .decoding), ("wrongparent", .invalidResponse), ("notag", .missingETag)] {
            let client = try api(scenario)
            do { _ = try await client.vlanSnapshot(target: physical); XCTFail("Unsafe metadata accepted") }
            catch { XCTAssertEqual(error as? APIError, expected) }
            XCTAssertTrue(VLANWriteProtocol.state.bodies(scenario).isEmpty)
            await client.close()
        }
    }
    func testConflictAndReferenceRaceStopPATCH() async throws {
        for (scenario, expected) in [("etagchange", APIError.conflict), ("sitechange", .conflict), ("vlanchange", .invalidReference)] {
            let client = try api(scenario)
            let snapshot = try await client.vlanSnapshot(target: physical)
            do { _ = try await client.updateVLAN(snapshot, to: VLANPlan(mode: "access", untagged: ReferenceSelection(id: 21, title: "Global"), tagged: [])); XCTFail("Race accepted") }
            catch { XCTAssertEqual(error as? APIError, expected) }
            XCTAssertTrue(VLANWriteProtocol.state.bodies(scenario).isEmpty)
            await client.close()
        }
    }
    func testFailureRetainsDraftAndRequiresReloadWithoutRetry() async throws {
        for scenario in ["lost", "forbidden", "wrongreply", "replyparent"] {
            let client = try api(scenario)
            let model = VLANEditModel(client: client, target: physical)
            await model.load()
            model.draft.mode = "access"; model.draft.untagged = ReferenceSelection(id: 21, title: "Global")
            let proposed = await model.review()
            let reviewed = try XCTUnwrap(proposed)
            await model.save(reviewed)
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.draft.untagged?.id, 21)
            await model.save(reviewed)
            XCTAssertEqual(VLANWriteProtocol.state.bodies(scenario).count, 1)
            await client.close()
        }
    }
    func testModeChangeRetainsSelectionsAndNoOpIsDisabled() async throws {
        let client = try api("draft")
        let model = VLANEditModel(client: client, target: physical)
        await model.load(); XCTAssertFalse(model.canReview)
        model.draft = VLANPlan(mode: "tagged", untagged: ReferenceSelection(id: 22, title: "Paris"), tagged: [ReferenceSelection(id: 21, title: "Global")])
        XCTAssertTrue(model.canReview)
        model.draft.mode = "access"
        XCTAssertEqual(model.draft.tagged.map(\.id), [21]); XCTAssertFalse(model.canReview)
        model.draft.tagged = []; XCTAssertTrue(model.canReview)
        XCTAssertTrue(VLANWriteProtocol.state.bodies("draft").isEmpty)
        await client.close()
    }
    func testSelectorScopeAndPaginationCannotEscape() throws {
        let query = VLANPickerQuery(siteID: 101, search: "server")
        let required = query.items.filter { $0.name != "limit" }
        XCTAssertNoThrow(try CollectionLinks.validate("https://example.test/api/ipam/vlans/?site_id=101&ordering=id&q=server&offset=50", path: "ipam/vlans/", required: required))
        for next in ["https://example.test/api/ipam/vlans/?site_id=102&ordering=id&q=server", "https://example.test/api/ipam/vlans/?site_id=null&ordering=id&q=server", "https://example.test/api/ipam/vlans/?site_id=101&ordering=id", "https://evil.test/api/ipam/vlans/?site_id=101&ordering=id&q=server"] {
            // CollectionLinks checks path/filters; RequestBuilder independently checks the HTTPS origin.
            if next.contains("evil.test") { XCTAssertThrowsError(try NetBoxConfiguration("https://example.test").validatedURL(next)) }
            else { XCTAssertThrowsError(try CollectionLinks.validate(next, path: "ipam/vlans/", required: required)) }
        }
        XCTAssertEqual(VLANPickerQuery(siteID: nil).items.first?.value, "null")
    }
}
private final class VLANWriteState: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [String: [Data]] = [:]
    private var reads: [String: Int] = [:]
    func record(_ scenario: String, body: Data) { lock.lock(); defer { lock.unlock() }; writes[scenario, default: []].append(body) }
    func bodies(_ scenario: String) -> [Data] { lock.lock(); defer { lock.unlock() }; return writes[scenario, default: []] }
    func read(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; reads[key, default: 0] += 1; return reads[key, default: 0] }
}
private final class VLANWriteProtocol: URLProtocol, @unchecked Sendable {
    static let state = VLANWriteState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = (url.host ?? "").replacingOccurrences(of: ".test", with: "")
        let read = Self.state.read(scenario + url.path)
        var result = ComponentFixture.response(url) ?? InventoryFixture.response(url) ?? (404, "{}")
        var tag = "W/\"fixture-1\""
        if request.httpMethod == "PATCH" {
            guard let body = requestBody(request) else { return }
            Self.state.record(scenario, body: body)
            if scenario == "lost" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
            result = scenario == "forbidden" ? (403, "{}") : FixtureDescriptions().response(request) ?? (400, "{}")
        }
        if var row = (try? JSONSerialization.jsonObject(with: Data(result.1.utf8))) as? [String: Any] {
            if url.path == "/api/dcim/interfaces/501" {
                if scenario == "qinq" { row["qinq_svlan"] = ["id": 21, "name": "QinQ"] }
                if scenario == "translation" { row["vlan_translation_policy"] = ["id": 1, "name": "Translation"] }
                if scenario == "unknown" { row["mode"] = ["value": "future-mode", "label": "Future"] }
                if scenario == "missingvlan" { row.removeValue(forKey: "tagged_vlans") }
                if scenario == "wrongparent" || (scenario == "replyparent" && request.httpMethod == "PATCH") { row["device"] = ["id": 999, "name": "Other"] }
                if scenario == "etagchange", read > 1 { tag = "W/\"fixture-2\"" }
                if scenario == "wrongreply", request.httpMethod == "PATCH" { row["untagged_vlan"] = NSNull() }
            }
            if url.path == "/api/dcim/devices/301" {
                if scenario == "missingsite" { row.removeValue(forKey: "site") }
                if scenario == "sitechange", read > 1 { row["site"] = ["id": 102, "name": "Other"] }
            }
            if scenario == "vlanchange", url.path == "/api/ipam/vlans/21" { row["site"] = ["id": 102, "name": "Other"] }
            if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { result = (result.0, text) }
        }
        var headers = ["Content-Type": "application/json", "ETag": tag]
        if scenario == "notag" { headers.removeValue(forKey: "ETag") }
        guard let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: nil, headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
