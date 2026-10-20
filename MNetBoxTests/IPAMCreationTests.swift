import XCTest
@testable import MNetBox

@MainActor final class IPAMCreationTests: XCTestCase {
    private func client(_ scenario: String = "success") throws -> APIClient {
        CreationProtocol.reset(scenario)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CreationProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    func testCIDRCanonicalizationIPv4IPv6AndNetworkBoundaries() throws {
        XCTAssertEqual(try IPAMCIDR(" 2001:0DB8:0000::1/064 \n", network: false).text, "2001:db8::1/64")
        for value in ["0.0.0.0/0", "192.0.2.128/25", "192.0.2.1/32", "::/0", "2001:db8::/64", "2001:db8::1/128"] { XCTAssertNoThrow(try IPAMCIDR(value, network: true), value) }
        for value in ["192.0.2.10/24", "192.0.2.127/25", "2001:db8::1/64", "::1/0"] {
            XCTAssertThrowsError(try IPAMCIDR(value, network: true)) { XCTAssertEqual($0 as? APIError, .networkHostBits) }
            XCTAssertNoThrow(try IPAMCIDR(value, network: false))
        }
    }
    func testMalformedCIDRsAndInvalidDraftsCannotBeSubmitted() throws {
        for value in ["", "192.0.2.1", "192.0.2.1/33", "::1/129", "192.0.2.256/24", "192.0.2.1/-1", "::/", "::/64/1", "fe80::1%en0/64", "192.0.2.1\0garbage/24", ":: /64", "192.000.2.1/24"] { XCTAssertThrowsError(try IPAMCIDR(value, network: false), value) }
        var draft = IPAMCreationDraft(kind: .prefixes, cidr: "192.0.2.0/24")
        draft.status = "dhcp"; XCTAssertThrowsError(try draft.plan())
        draft.status = "active"; draft.vrf = ReferenceSelection(id: -1, title: "Bad"); XCTAssertThrowsError(try draft.plan())
        draft.vrf = nil; draft.tenant = ReferenceSelection(id: 0, title: "Bad"); XCTAssertThrowsError(try draft.plan())
        draft.tenant = nil; draft.description = String(repeating: "a", count: 201); XCTAssertThrowsError(try draft.plan())
        draft.description = ""; draft.dnsName = "host.test"; XCTAssertThrowsError(try draft.plan())
    }
    func testAssignedCreationUsesTypedPairAndRejectsPrefixOrMissingParent() throws {
        let selection = InterfaceSelection(kind: .physical, id: 501, title: "eth0", parentID: 301)
        let plan = try IPAMCreationDraft(kind: .ipAddresses, cidr: "203.0.113.90/24", assignment: selection).plan()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        XCTAssertEqual(body["assigned_object_type"] as? String, "dcim.interface")
        XCTAssertEqual(body["assigned_object_id"] as? Int, 501)
        XCTAssertThrowsError(try IPAMCreationDraft(kind: .prefixes, cidr: "203.0.113.0/24", assignment: selection).plan())
        XCTAssertThrowsError(try IPAMCreationDraft(kind: .ipAddresses, cidr: "203.0.113.90/24", assignment: InterfaceSelection(kind: .virtual, id: 801, title: "eth0")).plan())
    }
    func testPhysicalAndVirtualAssignedCreationAndUncertainReply() async throws {
        for scenario in ["assignnew", "assignnewlost", "assignnewwrong"] {
            for kind in [InterfaceKind.physical, .virtual] {
                let api = try client(scenario)
                let selection = InterfaceSelection(kind: kind, id: kind == .physical ? 501 : 801, title: "eth0", parentID: kind == .physical ? 301 : 401)
                let model = IPAMCreateModel(client: api, kind: .ipAddresses, assignment: selection)
                model.draft.cidr = "203.0.113.90/24"
                await model.review(); XCTAssertNotNil(model.reviewed, model.errorMessage ?? "")
                await model.create(); await model.create()
                XCTAssertEqual(CreationProtocol.posts(scenario), 1)
                if scenario == "assignnew" {
                    XCTAssertEqual(model.created?.assignedObjectID, selection.id)
                    XCTAssertEqual(model.created?.assignedObjectType, kind.rawValue)
                } else { XCTAssertNil(model.created); XCTAssertNotNil(model.errorMessage) }
                await api.close()
            }
        }
    }
    func testAssignmentCannotMoveToAnotherParentBeforeCreation() async throws {
        let api = try client("assignnew")
        let selection = InterfaceSelection(kind: .physical, id: 501, title: "eth0", parentID: 999)
        let model = IPAMCreateModel(client: api, kind: .ipAddresses, assignment: selection)
        model.draft.cidr = "203.0.113.90/24"
        await model.review(); XCTAssertNil(model.reviewed); XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(CreationProtocol.posts("assignnew"), 0)
        await api.close()
    }
    func testExactTypedPayloadWithExplicitGlobalAndNoTenant() throws {
        for kind in [IPAMKind.prefixes, .ipAddresses] {
            let plan = try IPAMCreationDraft(kind: kind, cidr: kind == .prefixes ? "203.0.113.0/24" : "203.0.113.10/24").plan()
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
            XCTAssertEqual(Set(fields.keys), Set(kind == .prefixes ? ["prefix", "status", "vrf", "tenant", "description", "comments"] : ["address", "status", "vrf", "tenant", "description", "comments", "dns_name"]))
            XCTAssertTrue(fields["vrf"] is NSNull); XCTAssertTrue(fields["tenant"] is NSNull)
            XCTAssertNil(fields["assigned_object_id"]); XCTAssertNil(fields["scope_id"])
        }
    }
    func testCreationBothFamiliesKindsAndPositiveReferences() async throws {
        let api = try client()
        for kind in [IPAMKind.prefixes, .ipAddresses] {
            for family in [4, 6] {
                let cidr = family == 4 ? (kind == .prefixes ? "203.0.113.0/24" : "203.0.113.42/24") : (kind == .prefixes ? "2001:db8:beef::/64" : "2001:db8:beef::42/64")
                let plan = try IPAMCreationDraft(kind: kind, cidr: cidr, vrf: ReferenceSelection(id: 7, title: "Blue"), tenant: ReferenceSelection(id: 1, title: "Example"), description: "  Mobile \n", comments: "## Notes\n\nMarkdown", dnsName: kind == .prefixes ? "" : " HOST.EXAMPLE.TEST ").plan()
                let object = try await api.createIPAM(plan)
                XCTAssertTrue(plan.matches(object)); XCTAssertEqual(object.tenant?.id, 1)
                XCTAssertEqual(object.description, "Mobile"); XCTAssertEqual(object.comments, "## Notes\n\nMarkdown")
                if kind == .ipAddresses { XCTAssertEqual(object.dnsName, "host.example.test") }
            }
        }
        XCTAssertEqual(CreationProtocol.posts("success"), 4); await api.close()
    }
    func testReviewAndCancelDoNotWriteAndDoubleConfirmIsBlocked() async throws {
        let api = try client()
        let model = IPAMCreateModel(client: api, kind: .prefixes)
        model.draft.cidr = "203.0.113.0/24"
        await model.create(); XCTAssertEqual(CreationProtocol.posts("success"), 0)
        await model.review(); XCTAssertNotNil(model.reviewed); XCTAssertEqual(CreationProtocol.posts("success"), 0)
        model.back(); XCTAssertNil(model.reviewed)
        await model.review(); await model.create(); await model.create()
        XCTAssertNotNil(model.created); XCTAssertTrue(model.attempted); XCTAssertFalse(model.canReview)
        XCTAssertEqual(CreationProtocol.posts("success"), 1); await api.close()
    }
    func testReviewedPlanIsImmutableUntilAnotherReview() async throws {
        let api = try client()
        let model = IPAMCreateModel(client: api, kind: .ipAddresses)
        model.draft.cidr = "203.0.113.10/24"; await model.review()
        model.draft.cidr = "203.0.113.11/24"
        await model.create()
        XCTAssertEqual(model.created?.address, "203.0.113.10/24")
        await api.close()
    }
    func testVisibleDuplicatesAndIncorrectPreflightScopeBlockPOST() async throws {
        for scenario in ["duplicate", "wrongscope", "badcount", "preflightdenied"] {
            let api = try client(scenario)
            let model = IPAMCreateModel(client: api, kind: .ipAddresses)
            model.draft.cidr = "203.0.113.10/24"
            await model.review(); XCTAssertNil(model.reviewed); XCTAssertNotNil(model.errorMessage)
            await model.create(); XCTAssertEqual(CreationProtocol.posts(scenario), 0)
            await api.close()
        }
    }
    func testDeniedValidationLostAndWrongRepliesKeepDraftWithoutRetry() async throws {
        for scenario in ["forbidden", "invalid", "conflict", "lost", "wrongid", "wrongvrf", "wrongaddress", "wrongstatus", "assigned"] {
            let api = try client(scenario)
            let model = IPAMCreateModel(client: api, kind: .ipAddresses)
            model.draft.cidr = "203.0.113.10/24"; model.draft.comments = "Preserve draft"
            await model.review(); await model.create()
            XCTAssertNil(model.created); XCTAssertTrue(model.attempted); XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.draft.comments, "Preserve draft"); XCTAssertFalse(model.canReview)
            XCTAssertFalse(model.errorMessage?.contains("sensitive-placeholder") == true)
            await model.create(); await model.review()
            XCTAssertEqual(CreationProtocol.posts(scenario), 1)
            await api.close()
        }
    }
    func testSyntheticCreationIsVisibleInFreshDetailAndFilteredList() throws {
        let fixture = FixtureIPAMCreations()
        let plan = try IPAMCreationDraft(kind: .prefixes, cidr: "203.0.113.0/24").plan()
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/ipam/prefixes/")))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(plan)
        let response = try XCTUnwrap(fixture.response(request)); XCTAssertEqual(response.0, 201)
        let created = try JSONDecoder().decode(IPAMObject.self, from: Data(response.1.utf8))
        let detail = try XCTUnwrap(fixture.response(URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/ipam/prefixes/\(created.id)/")))))
        XCTAssertTrue(plan.matches(try JSONDecoder().decode(IPAMObject.self, from: Data(detail.1.utf8))))
        let list = try XCTUnwrap(fixture.response(URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/ipam/prefixes/?q=203.0.113.0%2F24&vrf_id=null")))))
        let page = try JSONDecoder().decode(NetBoxPage<IPAMObject>.self, from: Data(list.1.utf8))
        XCTAssertEqual(page.results.map(\.id), [created.id])
    }
}

private final class CreationProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var counts: [String: Int] = [:]
    }
    private static let state = State()
    static func reset(_ scenario: String) { state.lock.lock(); defer { state.lock.unlock() }; state.counts[scenario] = 0 }
    static func posts(_ scenario: String) -> Int { state.lock.lock(); defer { state.lock.unlock() }; return state.counts[scenario] ?? 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let scenario = url.host?.components(separatedBy: ".").first ?? "success"
        if scenario.hasPrefix("assign"), let reply = ComponentFixture.response(url) ?? InventoryFixture.response(url), !parts.path.contains("/ipam/") {
            guard let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self); return
        }
        let prefix = parts.path == "/api/ipam/prefixes/"
        guard prefix || parts.path == "/api/ipam/ip-addresses/" else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        var status = 200
        var body: [String: Any]
        if request.httpMethod == "POST" {
            Self.state.lock.lock(); Self.state.counts[scenario, default: 0] += 1; Self.state.lock.unlock()
            guard request.value(forHTTPHeaderField: "If-Match") == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = requestBody(request),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(payload.keys).subtracting(scenario.hasPrefix("assignnew") ? ["assigned_object_type", "assigned_object_id"] : []) == Set(prefix ? ["prefix", "status", "vrf", "tenant", "description", "comments"] : ["address", "status", "vrf", "tenant", "description", "comments", "dns_name"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            if scenario == "lost" || scenario == "assignnewlost" { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
            status = scenario == "forbidden" ? 403 : scenario == "invalid" ? 400 : scenario == "conflict" ? 409 : 201
            body = payload; body["id"] = scenario == "wrongid" ? 0 : 123
            let primary = payload[prefix ? "prefix" : "address"] as? String ?? ""
            body["family"] = ["value": primary.contains(":") ? 6 : 4]
            body["status"] = ["value": scenario == "wrongstatus" ? "reserved" : payload["status"] as? String ?? ""]
            for key in ["vrf", "tenant"] { body[key] = (payload[key] as? Int).map { ["id": $0] as Any } ?? NSNull() }
            if scenario == "wrongvrf" { body["vrf"] = ["id": 7] }
            if scenario == "wrongaddress" { body["address"] = "203.0.113.11/24" }
            if scenario.hasPrefix("assignnew"), let id = payload["assigned_object_id"] as? Int {
                body["assigned_object"] = ["id": scenario == "assignnewwrong" ? id + 1 : id, "name": "eth0"]
            }
            if scenario == "assigned" { body["assigned_object_id"] = 501; body["assigned_object_type"] = "dcim.interface" }
            if scenario == "invalid" { body = ["custom_fields": ["sensitive-placeholder"]] }
        } else {
            let query = Dictionary((parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard query["limit"] == "1", query["vrf_id"] != nil, let primary = query[prefix ? "prefix" : "address"] else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
            }
            if scenario == "preflightdenied" { status = 403 }
            let record: [String: Any] = ["id": 333, prefix ? "prefix" : "address": prefix ? primary : primary + "/32", "vrf": scenario == "wrongscope" ? ["id": 7] as Any : NSNull()]
            let duplicate = ["duplicate", "wrongscope"].contains(scenario)
            body = ["count": scenario == "badcount" ? -1 : duplicate ? 1 : 0, "next": NSNull(), "previous": NSNull(), "results": duplicate ? [record] : []]
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
