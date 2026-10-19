import XCTest
@testable import MNetBox

@MainActor final class AssignmentGuardTests: XCTestCase {
    private func api(_ scenario: String) throws -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssignmentGuardProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"), token: "synthetic-placeholder", kind: .bearer), session: URLSession(configuration: configuration))
    }
    func testPrimaryAndOOBBlockDetachAndParentMoveBeforePATCH() async throws {
        for (scenario, expected) in [("primary", APIError.assignmentPrimaryBlocked), ("oob", .assignmentOOBBlocked), ("missing", .decoding)] {
            let client = try api(scenario)
            let target = StructuredEditTarget(collection: .ipAddresses, id: 11)
            let snapshot = try await client.structuredSnapshot(target: target, field: .assignment)
            for proposal in [StructuredEditValue.assignment(nil), .assignment(InterfaceSelection(kind: .virtual, id: 801, title: "eth0", parentID: 401))] {
                do { _ = try await client.updateStructured(snapshot, to: proposal); XCTFail("Blocked dependency was accepted") }
                catch { XCTAssertEqual(error as? APIError, expected) }
            }
            XCTAssertEqual(AssignmentGuardProtocol.patches.count(scenario), 0)
            await client.close()
        }
    }
    func testVMPrimaryIPv6BlocksDetach() async throws {
        let client = try api("vmprimary")
        let snapshot = try await client.structuredSnapshot(target: StructuredEditTarget(collection: .ipAddresses, id: 12), field: .assignment)
        do { _ = try await client.updateStructured(snapshot, to: .assignment(nil)); XCTFail("VM primary IPv6 detached") }
        catch { XCTAssertEqual(error as? APIError, .assignmentPrimaryBlocked) }
        XCTAssertEqual(AssignmentGuardProtocol.patches.count("vmprimary"), 0)
        await client.close()
    }
    func testSameParentInterfaceChangeRetainsPrimaryDesignation() async throws {
        let client = try api("primarysame")
        let target = StructuredEditTarget(collection: .ipAddresses, id: 11)
        let snapshot = try await client.structuredSnapshot(target: target, field: .assignment)
        let proposal = StructuredEditValue.assignment(InterfaceSelection(kind: .physical, id: 503, title: "eth0.100", parentID: 301))
        let reply = try await client.updateStructured(snapshot, to: proposal)
        XCTAssertTrue(reply.object.value(.assignment)?.matches(proposal) == true)
        XCTAssertEqual(AssignmentGuardProtocol.patches.count("primarysame"), 1)
        await client.close()
    }
    func testFreeDetachUsesNullPairAndPreservesOtherFields() async throws {
        let client = try api("free")
        let target = StructuredEditTarget(collection: .ipAddresses, id: 11)
        let snapshot = try await client.structuredSnapshot(target: target, field: .assignment)
        let reply = try await client.updateStructured(snapshot, to: .assignment(nil))
        XCTAssertTrue(reply.object.value(.assignment)?.matches(.assignment(nil)) == true)
        XCTAssertEqual(reply.object.title, "192.0.2.10/24")
        XCTAssertEqual(AssignmentGuardProtocol.patches.count("free"), 1)
        await client.close()
    }
    func testServerRaceIsClassifiedWithoutExposingResponseText() async throws {
        for (scenario, expected) in [("raceprimary", APIError.assignmentPrimaryBlocked), ("raceoob", .assignmentOOBBlocked), ("raceother", .assignmentRejected)] {
            let client = try api(scenario)
            let snapshot = try await client.structuredSnapshot(target: StructuredEditTarget(collection: .ipAddresses, id: 11), field: .assignment)
            do { _ = try await client.updateStructured(snapshot, to: .assignment(nil)); XCTFail("400 accepted") }
            catch {
                XCTAssertEqual(error as? APIError, expected)
                XCTAssertFalse(readErrorMessage(error).contains("private-response-marker"))
            }
            XCTAssertEqual(AssignmentGuardProtocol.patches.count(scenario), 1)
            await client.close()
        }
    }
}
private final class AssignmentPatchCounts: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    func add(_ scenario: String) { lock.lock(); defer { lock.unlock() }; values[scenario, default: 0] += 1 }
    func count(_ scenario: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[scenario, default: 0] }
}
private final class AssignmentGuardProtocol: URLProtocol, @unchecked Sendable {
    static let patches = AssignmentPatchCounts()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = (url.host ?? "").replacingOccurrences(of: ".test", with: "")
        var result = ComponentFixture.response(url) ?? IPAMFixture.response(url) ?? InventoryFixture.response(url) ?? (404, "{}")
        if request.httpMethod == "GET", url.path == "/api/dcim/devices/301", var row = (try? JSONSerialization.jsonObject(with: Data(result.1.utf8))) as? [String: Any] {
            row["primary_ip4"] = scenario == "primary" ? ["id": 11, "address": "192.0.2.10/24"] as Any : NSNull()
            row["oob_ip"] = scenario == "oob" ? ["id": 11, "address": "192.0.2.10/24"] as Any : NSNull()
            if scenario == "missing" { row.removeValue(forKey: "primary_ip6") }
            if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { result = (200, text) }
        }
        if request.httpMethod == "PATCH" {
            Self.patches.add(scenario)
            if scenario.hasPrefix("race") {
                let reason = scenario == "raceprimary" ? "Cannot reassign IP address while it is designated as the primary IP for the parent object" : scenario == "raceoob" ? "Cannot reassign IP address while it is designated as the OOB IP for the parent object" : "custom rule private-response-marker"
                if let data = try? JSONSerialization.data(withJSONObject: ["non_field_errors": [reason]]), let text = String(data: data, encoding: .utf8) { result = (400, text) }
            } else { result = FixtureDescriptions().response(request) ?? (400, "{}") }
        }
        guard let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: nil, headerFields: ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
