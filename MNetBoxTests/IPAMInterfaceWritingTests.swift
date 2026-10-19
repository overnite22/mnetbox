import XCTest
@testable import MNetBox

@MainActor final class IPAMInterfaceWritingTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InterfaceWriteProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: config))
    }
    func testCreationWhitelistsAndValidation() throws {
        for kind in [InterfaceKind.physical, .virtual] {
            let plan = try InterfaceCreationDraft(kind: kind, parentID: 301, name: " eth9 ", mtu: "9000").plan()
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), kind == .physical ? ["device", "name", "enabled", "mtu", "description", "type"] : ["virtual_machine", "name", "enabled", "mtu", "description"])
            XCTAssertEqual(object["name"] as? String, "eth9")
            XCTAssertEqual(object["mtu"] as? Int, 9000)
        }
        for name in ["", " \n", "a\nb", String(repeating: "x", count: 65)] {
            XCTAssertThrowsError(try InterfaceCreationDraft(kind: .virtual, parentID: 401, name: name).plan())
        }
        for mtu in ["0", "65537", "-1", "1.5", "1e3", "１２"] {
            XCTAssertThrowsError(try InterfaceCreationDraft(kind: .physical, parentID: 301, name: "eth9", mtu: mtu).plan())
        }
        XCTAssertThrowsError(try InterfaceCreationDraft(kind: .physical, parentID: 0, name: "eth9").plan())
        XCTAssertThrowsError(try InterfaceCreationDraft(kind: .physical, parentID: 301, name: "eth9", type: "unverified").plan())
    }
    func testAtomicAssignmentPayloadAndStatusConfinement() throws {
        for selection in [InterfaceSelection(kind: .virtual, id: 801, title: "eth0", parentID: 401), nil] {
            let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(StructuredEditPayload(field: .assignment, value: .assignment(selection)))) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["assigned_object_type", "assigned_object_id"])
            if let selection {
                XCTAssertEqual(object["assigned_object_type"] as? String, selection.kind.rawValue)
                XCTAssertEqual(object["assigned_object_id"] as? Int, 801)
            } else { XCTAssertTrue(object.values.allSatisfy { $0 is NSNull }) }
        }
        XCTAssertThrowsError(try StructuredEditValue.status("dhcp").validate(field: .status, target: StructuredEditTarget(collection: .prefixes, id: 1)))
        XCTAssertNoThrow(try StructuredEditValue.status("dhcp").validate(field: .status, target: StructuredEditTarget(collection: .ipAddresses, id: 11)))
        XCTAssertThrowsError(try StructuredEditValue.assignment(nil).validate(field: .assignment, target: StructuredEditTarget(collection: .prefixes, id: 1)))
    }
    func testStatusTenantAndDetachPreserveAddressVRF() async throws {
        let client = try api()
        for (field, value) in [(StructuredEditField.status, StructuredEditValue.status("reserved")), (.tenant, .reference(nil)), (.assignment, .assignment(nil))] {
            let snapshot = try await client.structuredSnapshot(target: StructuredEditTarget(collection: .ipAddresses, id: 11), field: field)
            let reply = try await client.updateStructured(snapshot, to: value)
            XCTAssertTrue(reply.object.value(field)?.matches(value) == true)
            XCTAssertEqual(reply.object.title, "192.0.2.10/24")
        }
        await client.close()
    }
    func testAssignmentAndPrimaryRejectWrongParentFamilyAndUnknownReference() async throws {
        let client = try api()
        let device = StructuredEditTarget(collection: .devices, id: 301)
        try await client.checkStructuredReference(.reference(ReferenceSelection(id: 11, title: "IP")), target: device, field: .primaryIP4)
        try await client.checkStructuredReference(.assignment(InterfaceSelection(kind: .virtual, id: 801, title: "eth0", parentID: 401)), target: StructuredEditTarget(collection: .ipAddresses, id: 11), field: .assignment)
        for (field, value, target) in [
            (StructuredEditField.primaryIP4, StructuredEditValue.reference(ReferenceSelection(id: 12, title: "IPv6")), device),
            (.primaryIP4, .reference(ReferenceSelection(id: 11, title: "wrong device")), StructuredEditTarget(collection: .devices, id: 303)),
            (.assignment, .assignment(InterfaceSelection(kind: .physical, id: 501, title: "wrong parent", parentID: 303)), StructuredEditTarget(collection: .ipAddresses, id: 11)),
            (.assignment, .assignment(InterfaceSelection(kind: .physical, id: 501, title: "missing parent")), StructuredEditTarget(collection: .ipAddresses, id: 11))] {
            do { try await client.checkStructuredReference(value, target: target, field: field); XCTFail("Invalid reference accepted") }
            catch { XCTAssertEqual(error as? APIError, .invalidReference) }
        }
        await client.close()
    }
    func testAssignVirtualInterfaceAndPrefixContainerStatus() async throws {
        let client = try api()
        let snapshot = try await client.structuredSnapshot(target: StructuredEditTarget(collection: .ipAddresses, id: 11), field: .assignment)
        let value = StructuredEditValue.assignment(InterfaceSelection(kind: .virtual, id: 801, title: "eth0", parentID: 401))
        let reply = try await client.updateStructured(snapshot, to: value)
        XCTAssertTrue(reply.object.value(.assignment)?.matches(value) == true)
        let prefix = try await client.structuredSnapshot(target: StructuredEditTarget(collection: .prefixes, id: 1), field: .status)
        let updated = try await client.updateStructured(prefix, to: .status("container"))
        XCTAssertTrue(updated.object.value(.status)?.matches(.status("container")) == true)
        await client.close()
    }
    func testPrimarySnapshotPatchAndClearing() async throws {
        let client = try api()
        let target = StructuredEditTarget(collection: .virtualMachines, id: 401)
        let snapshot = try await client.structuredSnapshot(target: target, field: .primaryIP6)
        let reply = try await client.updateStructured(snapshot, to: .reference(nil))
        XCTAssertTrue(reply.object.value(.primaryIP6)?.matches(.reference(nil)) == true)
        let device = StructuredEditTarget(collection: .devices, id: 301)
        let initial = try await client.structuredSnapshot(target: device, field: .primaryIP4)
        let same = try await client.updateStructured(initial, to: .reference(ReferenceSelection(id: 11, title: "IPv4")))
        XCTAssertTrue(same.object.value(.primaryIP4)?.matches(.reference(ReferenceSelection(id: 11, title: "IP"))) == true)
        await client.close()
    }
    func testCreatePhysicalAndVMAndDuplicateRefusal() async throws {
        let client = try api()
        for kind in [InterfaceKind.physical, .virtual] {
            let plan = try InterfaceCreationDraft(kind: kind, parentID: kind == .physical ? 301 : 401, name: "eth9", mtu: "9000").plan()
            let object = try await client.createInterface(plan)
            XCTAssertEqual(object.name, "eth9"); XCTAssertEqual(object.mtu, 9000)
            XCTAssertEqual(InterfaceService(client: client, kind: kind).parent(object)?.id, plan.parentID)
        }
        do { try await client.checkInterfaceCreation(InterfaceCreationDraft(kind: .physical, parentID: 301, name: "eth0").plan()); XCTFail("Duplicate accepted") }
        catch { XCTAssertEqual(error as? APIError, .duplicateInterface) }
        await client.close()
    }
    func testCreationUncertainReplyAndMismatchedParentStopFurtherAttempts() async throws {
        for scenario in ["lost", "wrongreply"] {
            let client = try api(scenario)
            let model = InterfaceCreateModel(client: client, kind: .virtual, parentID: 401)
            model.draft.name = "eth9"
            await model.review(); XCTAssertNotNil(model.reviewed)
            await model.create()
            XCTAssertTrue(model.attempted); XCTAssertNil(model.created); XCTAssertNotNil(model.errorMessage)
            XCTAssertFalse(model.canReview)
            let attempts = InterfaceWriteProtocol.counter.count(scenario)
            await model.create(); XCTAssertEqual(InterfaceWriteProtocol.counter.count(scenario), attempts)
            XCTAssertEqual(model.draft.name, "eth9")
            await client.close()
        }
    }
}
private final class InterfaceWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func increment(_ host: String) { lock.lock(); defer { lock.unlock() }; values[host, default: 0] += 1 }
    func count(_ scenario: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[scenario + ".test", default: 0] }
}
private final class InterfaceWriteProtocol: URLProtocol, @unchecked Sendable {
    static let counter = InterfaceWriteCounter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        var result: (Int, String)?
        if request.httpMethod == "POST" {
            Self.counter.increment(url.host ?? "")
            if url.host == "lost.test" { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
            result = FixtureInterfaceCreations().response(request)
            if url.host == "wrongreply.test", let reply = result, var row = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] {
                row["virtual_machine"] = ["id": 999, "name": "Other"]
                if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { result = (201, text) }
            }
        } else if request.httpMethod == "PATCH" { result = FixtureDescriptions().response(request) }
        else { result = ComponentFixture.response(url) ?? IPAMFixture.response(url) ?? InventoryFixture.response(url) }
        if request.httpMethod == "GET", url.path == "/api/dcim/devices/301", let original = result,
           var row = (try? JSONSerialization.jsonObject(with: Data(original.1.utf8))) as? [String: Any] {
            row["primary_ip4"] = NSNull(); row["oob_ip"] = NSNull()
            if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { result = (200, text) }
        }
        let reply = result ?? (404, "{}")
        guard let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: nil, headerFields: ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
