import XCTest
@testable import MNetBox

@MainActor final class StructuredEditingTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StructuredProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    private func target(_ collection: StructuredEditTarget.Collection) -> StructuredEditTarget {
        StructuredEditTarget(collection: collection, id: 101, parentID: collection.isInterface ? 301 : nil)
    }
    func testTypedPayloadsAndCollectionConfinement() throws {
        for collection in StructuredEditTarget.Collection.allCases {
            let target = target(collection)
            XCTAssertEqual(try target.path, collection.rawValue + "101/")
            for field in StructuredEditField.allCases { if collection.isInterface { XCTAssertEqual(field.supports(collection), field == .primaryMAC || field == .enabled || field == .mtu || field.isText || (field == .type && collection == .physicalInterfaces)) }
                else if collection.isIPAM { XCTAssertEqual(field.supports(collection), field == .tenant || field == .status || (field == .assignment && collection == .ipAddresses)) }
                else if collection == .vlans { XCTAssertEqual(field.supports(collection), field == .tenant || field == .role) }
                else if collection == .macAddresses { XCTAssertEqual(field.supports(collection), field == .assignment) }
                else { XCTAssertEqual(field.supports(collection), field.isReference && field != .primaryMAC) } }
        }
        for (field, value) in [(StructuredEditField.enabled, StructuredEditValue.enabled(false)), (.mtu, .mtu(9000)), (.mtu, .mtu(nil)), (.tenant, .reference(ReferenceSelection(id: 7, title: "Tenant"))), (.platform, .reference(nil))] {
            let data = try JSONEncoder().encode(StructuredEditPayload(field: field, value: value))
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(object.keys), [field.rawValue])
            switch value {
            case .text, .interfaceType, .status, .assignment: XCTFail("Unexpected value")
            case .enabled: XCTAssertEqual((object["enabled"] as? NSNumber)?.objCType.pointee, 99) // JSON boolean, not a string or integer.
            case .mtu(let mtu): if let mtu { XCTAssertEqual(object["mtu"] as? Int, mtu) } else { XCTAssertTrue(object["mtu"] is NSNull) }
            case .reference(let ref): if let ref { XCTAssertEqual(object[field.rawValue] as? Int, ref.id) } else { XCTAssertTrue(object[field.rawValue] is NSNull) }
            }
        }
        XCTAssertThrowsError(try StructuredEditValue.reference(nil).validate(field: .role, target: target(.devices)))
        XCTAssertNoThrow(try StructuredEditValue.reference(nil).validate(field: .role, target: target(.virtualMachines)))
        XCTAssertThrowsError(try StructuredEditValue.reference(ReferenceSelection(id: 0, title: "Invalid")).validate(field: .tenant, target: target(.devices)))
        XCTAssertThrowsError(try StructuredEditTarget(collection: .physicalInterfaces, id: 1).path)
    }
    func testInterfaceNameDescriptionAndTypeValidation() throws {
        let model = StructuredEditModel(client: try api(), target: target(.physicalInterfaces), field: .name)
        for text in ["eth9", " bond0 ", String(repeating: "é", count: 64)] { model.text = text; XCTAssertNoThrow(try model.proposal()) }
        for text in ["", "  ", "eth\n9", "eth\t9", String(repeating: "a", count: 65)] { model.text = text; XCTAssertThrowsError(try model.proposal()) }
        XCTAssertThrowsError(try StructuredEditValue.interfaceType("arbitrary").validate(field: .type, target: target(.physicalInterfaces)))
        XCTAssertThrowsError(try StructuredEditValue.interfaceType("virtual").validate(field: .type, target: target(.virtualInterfaces)))
        XCTAssertThrowsError(try StructuredEditValue.text("eth9").validate(field: .name, target: target(.devices)))
        XCTAssertNoThrow(try StructuredEditValue.text("").validate(field: .description, target: target(.virtualInterfaces)))
        XCTAssertThrowsError(try StructuredEditValue.text(String(repeating: "é", count: 201)).validate(field: .description, target: target(.physicalInterfaces)))
    }
    func testInterfaceTextAndTypeOnlyPatchSelectedField() async throws {
        for collection in [StructuredEditTarget.Collection.physicalInterfaces, .virtualInterfaces] {
            let api = try api()
            let changes: [(StructuredEditField, StructuredEditValue)] = [(.name, .text("bond9")), (.description, .text("Mobile description")), (.description, .text(""))] + (collection == .physicalInterfaces ? [(.type, .interfaceType("10gbase-x-sfpp"))] : [])
            for (field, value) in changes {
                let snapshot = try await api.structuredSnapshot(target: target(collection), field: field)
                let updated = try await api.updateStructured(snapshot, to: value)
                XCTAssertTrue(updated.object.value(field)?.matches(value) == true)
                XCTAssertTrue(updated.object.value(.enabled)?.matches(.enabled(true)) == true)
                XCTAssertTrue(updated.object.value(.mtu)?.matches(.mtu(1500)) == true)
                XCTAssertEqual(updated.object.parentDevice?.id, 301)
            }
            await api.close()
        }
    }
    func testUnknownCurrentPhysicalTypeRemainsReadableWithoutBeingWritable() async throws {
        let api = try api("customtype")
        let model = StructuredEditModel(client: api, target: target(.physicalInterfaces), field: .type)
        await model.load()
        XCTAssertEqual(model.interfaceType, "future-type")
        XCTAssertNil(model.errorMessage); XCTAssertNil(model.validationMessage)
        XCTAssertFalse(model.canReview)
        model.interfaceType = "1000base-t"
        XCTAssertTrue(model.canReview)
        let proposal = await model.review()
        let reviewed = try XCTUnwrap(proposal)
        await model.save(reviewed); XCTAssertTrue(model.saved)
        await api.close()
    }
    func testInterfaceNameConflictAndUncertainReplyKeepDraftAndRequireReload() async throws {
        for scenario in ["conflict", "lost", "forbidden", "changedparent"] {
            let api = try api(scenario)
            let model = StructuredEditModel(client: api, target: target(.physicalInterfaces), field: .name)
            await model.load(); model.text = "eth9"
            let proposal = await model.review()
        let reviewed = try XCTUnwrap(proposal)
            await model.save(reviewed)
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertEqual(model.text, "eth9")
            XCTAssertFalse(model.canReview)
            await model.save(reviewed); XCTAssertFalse(model.saved)
            await api.close()
        }
    }
    func testMTUBoundsAndStrictNumericDraft() throws {
        let model = StructuredEditModel(client: try api(), target: target(.physicalInterfaces), field: .mtu)
        for text in ["", "1", "65536", " 9000 ", "01500"] { model.mtu = text; XCTAssertNoThrow(try model.proposal()) }
        for text in ["0", "65537", "-1", "+1500", "1.5", "1e3", "１２３", "1500 x", String(repeating: "9", count: 50)] {
            model.mtu = text; XCTAssertThrowsError(try model.proposal())
        }
    }
    func testFreshSnapshotSingleFieldPatchAndParentPreservation() async throws {
        let api = try api()
        for collection in StructuredEditTarget.Collection.allCases.filter({ $0 != .macAddresses }) {
            let field: StructuredEditField = collection.isInterface ? .enabled : .tenant
            let snapshot = try await api.structuredSnapshot(target: target(collection), field: field)
            XCTAssertEqual(snapshot.etag, "W/\"revision-1\"")
            let value: StructuredEditValue = collection.isInterface ? .enabled(false) : .reference(ReferenceSelection(id: 7, title: "Tenant"))
            let updated = try await api.updateStructured(snapshot, to: value)
            XCTAssertTrue(updated.object.value(field)?.matches(value) == true)
        }
        let snapshot = try await api.structuredSnapshot(target: target(.virtualInterfaces), field: .mtu)
        let cleared = try await api.updateStructured(snapshot, to: .mtu(nil))
        XCTAssertTrue(cleared.object.value(.mtu)?.matches(.mtu(nil)) == true)
        await api.close()
    }
    func testMissingFieldsWrongParentsWrongRepliesAndMissingETagFailClosed() async throws {
        for scenario in ["missingfield", "wrongparent", "missingetag"] {
            let api = try api(scenario)
            do { _ = try await api.structuredSnapshot(target: target(.physicalInterfaces), field: .mtu); XCTFail("Invalid snapshot") }
            catch { XCTAssertEqual(error as? APIError, scenario == "missingetag" ? .missingETag : .invalidResponse) }
            await api.close()
        }
        for scenario in ["wrongreply", "wrongvalue", "changedparent"] {
            let api = try api(scenario)
            let snapshot = try await api.structuredSnapshot(target: target(.physicalInterfaces), field: .enabled)
            do { _ = try await api.updateStructured(snapshot, to: .enabled(false)); XCTFail("Invalid reply") }
            catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
            await api.close()
        }
    }
    func testVMRoleCompatibilityAndReferenceIdentityAreCheckedBeforePATCH() async throws {
        for scenario in ["notvmrole", "wrongref"] {
            let api = try api(scenario)
            let snapshot = try await api.structuredSnapshot(target: target(.virtualMachines), field: .role)
            do { _ = try await api.updateStructured(snapshot, to: .reference(ReferenceSelection(id: 7, title: "Role"))); XCTFail("Invalid role") }
            catch { XCTAssertEqual(error as? APIError, .invalidReference) }
            await api.close()
        }
        let api = try api()
        let model = StructuredEditModel(client: api, target: target(.virtualMachines), field: .role)
        await model.load(); model.reference = ReferenceSelection(id: 7, title: "Role")
        let value = await model.review(); XCTAssertNotNil(value)
        if let value { await model.save(value) }
        XCTAssertTrue(model.saved); await api.close()
    }
    func testNoopConflictDeniedUncertainAndDraftRetention() async throws {
        for scenario in ["conflict", "forbidden", "lost"] {
            let api = try api(scenario)
            let model = StructuredEditModel(client: api, target: target(.physicalInterfaces), field: .mtu)
            await model.load(); XCTAssertFalse(model.canReview)
            model.mtu = "09000"
            let reviewed = await model.review(); XCTAssertNotNil(reviewed)
            if let reviewed { await model.save(reviewed); await model.save(reviewed) }
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload)
            XCTAssertEqual(model.mtu, "09000"); XCTAssertFalse(model.canReview)
            await model.load(); XCTAssertEqual(model.mtu, "09000"); XCTAssertTrue(model.canReview)
            await api.close()
        }
        XCTAssertTrue(StructuredEditValue.reference(ReferenceSelection(id: 7, title: "Old label")).matches(.reference(ReferenceSelection(id: 7, title: "Renamed"))))
    }
    func testFixturesPreserveInterfaceTopologyAndInventoryTextAcrossEditors() throws {
        let fixture = FixtureDescriptions()
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/dcim/interfaces/501/")))
        request.httpMethod = "PATCH"; request.setValue("W/\"fixture-1\"", forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(StructuredEditPayload(field: .mtu, value: .mtu(9000)))
        let reply = try XCTUnwrap(fixture.response(request)); XCTAssertEqual(reply.0, 200)
        let interface = try JSONDecoder().decode(InterfaceObject.self, from: Data(reply.1.utf8))
        XCTAssertEqual(interface.mtu, 9000); XCTAssertEqual(interface.cable?.id, 701); XCTAssertEqual(interface.device?.id, 301)
        XCTAssertEqual(interface.linkPeers?.first?.id, 601)
        request.url = URL(string: "https://example.test/api/dcim/devices/301/")
        request.httpBody = try JSONEncoder().encode(StructuredEditPayload(field: .tenant, value: .reference(ReferenceSelection(id: 1, title: "Tenant"))))
        XCTAssertEqual(fixture.response(request)?.0, 200)
        request.httpBody = try JSONEncoder().encode(TextEditPayload(field: .description, value: "Changed"))
        let textReply = try XCTUnwrap(fixture.response(request))
        let device = try JSONDecoder().decode(InventoryObject.self, from: Data(textReply.1.utf8))
        XCTAssertEqual(device.tenant?.id, 1); XCTAssertEqual(device.description, "Changed"); XCTAssertEqual(device.rack?.id, 201)
    }
}

private final class StructuredProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = url.host?.components(separatedBy: ".").first ?? "success"
        let patch = request.httpMethod == "PATCH"
        let ref = url.path.contains("/tenancy/tenants/") || url.path.contains("/dcim/device-roles/") || url.path.contains("/dcim/platforms/")
        var body: [String: Any] = ref ? ["id": scenario == "wrongref" ? 9 : 7, "name": "Reference", "vm_role": scenario != "notvmrole"] :
            ["id": 101, "name": "Object", "device": ["id": scenario == "wrongparent" ? 999 : 301, "name": "Parent"], "virtual_machine": ["id": 301, "name": "VM"], "enabled": true, "mtu": 1500, "description": "Initial description", "type": ["value": scenario == "customtype" ? "future-type" : "1000base-t"], "tenant": NSNull(), "role": NSNull(), "platform": NSNull()]
        if url.path.contains("/dcim/devices/101/") { body["role"] = ["id": 1, "name": "Role"] }
        if scenario == "missingfield" { body.removeValue(forKey: "mtu") }
        var status = 200
        if patch {
            guard request.value(forHTTPHeaderField: "If-Match") == "W/\"revision-1\"", request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let data = requestBody(request), let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], payload.count == 1,
                  let entry = payload.first, StructuredEditField(rawValue: entry.key) != nil else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            if scenario == "lost" { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
            status = scenario == "conflict" ? 412 : scenario == "forbidden" ? 403 : 200
            if ["tenant", "role", "platform"].contains(entry.key), let id = entry.value as? Int { body[entry.key] = ["id": id, "name": "Reference"] }
            else if entry.key == "type" { body[entry.key] = ["value": entry.value] }
            else { body[entry.key] = entry.value }
            if scenario == "wrongreply" { body["id"] = 999 }
            if scenario == "wrongvalue" { body["enabled"] = true }
            if scenario == "changedparent" { body["device"] = ["id": 999, "name": "Other"] }
        }
        var headers = ["Content-Type": "application/json"]
        if scenario != "missingetag" { headers["ETag"] = "W/\"revision-1\"" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers), let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
