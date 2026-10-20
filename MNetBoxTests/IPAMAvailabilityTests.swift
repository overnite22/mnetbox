import XCTest
@testable import MNetBox

final class IPAMAvailabilityTests: XCTestCase {
    private func cidr(_ text: String, network: Bool = true) throws -> IPAMCIDR { try IPAMCIDR(text, network: network) }
    private func label(_ id: Int?) -> NetBoxLabel? {
        guard let id else { return nil }
        return try? JSONDecoder().decode(NetBoxLabel.self, from: JSONSerialization.data(withJSONObject: ["id": id, "name": "VRF \(id)"]))
    }

    func testContainmentRespectsFamilyAndMask() throws {
        let parent = try cidr("198.51.100.0/24")
        XCTAssertTrue(IPAMAvailability.contains(parent, try cidr("198.51.100.42/24", network: false)))
        XCTAssertTrue(IPAMAvailability.contains(parent, try cidr("198.51.100.128/25")))
        XCTAssertFalse(IPAMAvailability.contains(parent, try cidr("198.51.101.0/24")))
        XCTAssertFalse(IPAMAvailability.contains(parent, try cidr("198.51.0.0/16")))
        XCTAssertFalse(IPAMAvailability.contains(try cidr("2001:db8::/32"), try cidr("198.51.100.0/24")))
    }
    func testFirstIPMustStayInParentAndVRF() throws {
        let parent = try cidr("198.51.100.0/24")
        let ok = [IPAMAvailability.AvailableIP(address: "198.51.100.5/24", vrf: label(9))]
        XCTAssertEqual(try IPAMAvailability.firstIP(ok, parent: parent, vrfID: 9)?.text, "198.51.100.5/24")
        XCTAssertNil(try IPAMAvailability.firstIP([], parent: parent, vrfID: 9))
        XCTAssertThrowsError(try IPAMAvailability.firstIP(ok, parent: parent, vrfID: nil))
        let outside = [IPAMAvailability.AvailableIP(address: "203.0.113.5/24", vrf: nil)]
        XCTAssertThrowsError(try IPAMAvailability.firstIP(outside, parent: parent, vrfID: nil))
    }
    func testFirstPrefixPicksFirstBlockLargeEnough() throws {
        let parent = try cidr("198.18.0.0/16")
        let blocks = [IPAMAvailability.AvailablePrefix(prefix: "198.18.1.0/24", vrf: nil), .init(prefix: "198.18.4.0/22", vrf: nil)]
        XCTAssertEqual(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 26)?.text, "198.18.1.0/26")
        XCTAssertEqual(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 23)?.text, "198.18.4.0/23")
        XCTAssertNil(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 21))
        XCTAssertThrowsError(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 16))
        XCTAssertThrowsError(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 33))
        XCTAssertThrowsError(try IPAMAvailability.firstPrefix([.init(prefix: "198.19.0.0/24", vrf: nil)], parent: parent, vrfID: nil, length: 24))
    }
    func testIPv6PrefixSuggestion() throws {
        let parent = try cidr("2001:db8::/48")
        let blocks = [IPAMAvailability.AvailablePrefix(prefix: "2001:db8:0:100::/56", vrf: nil)]
        XCTAssertEqual(try IPAMAvailability.firstPrefix(blocks, parent: parent, vrfID: nil, length: 64)?.text, "2001:db8:0:100::/64")
    }
    func testClientUsesNativeReadOnlyEndpoints() async throws {
        AvailabilityProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AvailabilityProtocol.self]
        let api = APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://example.test"), token: "test-placeholder", kind: .legacy), session: URLSession(configuration: configuration))
        let ip = try await api.nextAvailableIP(prefixID: 5, parent: try cidr("198.51.100.0/24"), vrfID: nil)
        let prefix = try await api.nextAvailablePrefix(prefixID: 5, parent: try cidr("198.51.100.0/24"), vrfID: nil, length: 28)
        XCTAssertEqual(ip?.text, "198.51.100.1/24"); XCTAssertEqual(prefix?.text, "198.51.100.64/28")
        let requests = AvailabilityProtocol.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertEqual(requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path }, "/api/ipam/prefixes/5/available-ips/")
        XCTAssertEqual(requests.first?.url?.query, "limit=1")
        XCTAssertEqual(requests.last?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path }, "/api/ipam/prefixes/5/available-prefixes/")
    }
}

private final class AvailabilityProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
    static func reset() { lock.lock(); stored = []; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock(); Self.stored.append(request); Self.lock.unlock()
        let body: Any = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? "").hasSuffix("available-ips/")
            ? [["family": 4, "address": "198.51.100.1/24", "vrf": NSNull()]]
            : [["family": 4, "prefix": "198.51.100.64/26", "vrf": NSNull()]]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
