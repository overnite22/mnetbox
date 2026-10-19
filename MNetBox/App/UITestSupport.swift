#if DEBUG
import Foundation

// Only available in Debug builds. UI tests never read or change real credentials.
@MainActor enum UITestSupport {
    static func connection() -> ConnectionModel? {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-dashboard") || ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-connection") else { return nil }
        return ConnectionModel(store: FixtureStore()) { credential in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FixtureProtocol.self]
            return APIClient(credential: credential, session: URLSession(configuration: configuration))
        }
    }

    private final class FixtureStore: CredentialStore {
        private var hasCredential = !ProcessInfo.processInfo.arguments.contains("--ui-testing-empty-connection")
        func load() throws -> Credential? {
            guard hasCredential else { return nil }
            return Credential(configuration: try NetBoxConfiguration("https://example.test"),
                              token: "test-placeholder", kind: .legacy)
        }
        func save(_ credential: Credential) throws { hasCredential = true }
        func delete() throws { hasCredential = false }
    }

    private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        private static let imageData = NetBoxImageFixture.png
        private static let contextAdministration = ContextAdministrationFixture()
        private static let vlanAdministration = VLANAdministrationFixture()
        private static let imageUploads = ImageUploadFixture()
        private static let ipamAdministration = IPAMAdministrationFixture()
        private static let networkWrites = NetworkWriteFixture()
        private static let cableCreations = CableCreationFixture()
        private static let edits = FixtureDescriptions()
        private static let interfaceCreations = FixtureInterfaceCreations()
        private static let creations = FixtureIPAMCreations()
        override func startLoading() {
            guard let url = request.url else { return }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-cable-creation"), let result = Self.cableCreations.response(request) { deliver(url: url, status: result.0, body: result.1); return }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-port-panel") {
                if let result = PortPanelFixture.response(request) ?? DevicePortsFixture.response(request) { deliver(url: url, status: result.0, body: result.1); return }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-device-ports"), let result = DevicePortsFixture.response(request) { deliver(url: url, status: result.0, body: result.1); return }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-context-administration"), let result = ContextDeletionFixture.response(request) { deliver(url: url, status: result.0, body: result.1); return }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-image-upload") {
                if let data = Self.imageUploads.media(url), let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": url.pathExtension == "png" ? "image/png" : "image/jpeg"]) {
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self); return
                }
                if let result = Self.imageUploads.response(request) { deliver(url: url, status: result.0, body: result.1); return }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-netbox-images") {
                if url.path.hasPrefix("/media/") {
                    if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"]) {
                        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                        client?.urlProtocol(self, didLoad: Self.imageData); client?.urlProtocolDidFinishLoading(self)
                    }
                    return
                }
                if let result = NetBoxImageFixture.response(url) { deliver(url: url, status: result.0, body: result.1); return }
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-context-administration"), let result = Self.contextAdministration.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-vlan-administration"), let result = Self.vlanAdministration.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-cable-trace"), let result = CableTraceFixture.response(url) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-ipam-administration"), let result = Self.ipamAdministration.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-network-writes"), let result = Self.networkWrites.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if let result = FixtureDeletions.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if let result = Self.edits.response(request) {
                deliver(url: url, status: result.0, body: result.1)
                return
            }
            if let result = Self.creations.response(request) {
                deliver(url: url, status: result.0, body: result.1)
                return
            }
            if let result = Self.interfaceCreations.response(request) {
                deliver(url: url, status: result.0, body: result.1); return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-context-forbidden"), url.path.contains("/api/tenancy/tenants") {
                deliver(url: url, status: 403, body: "{}"); return
            }
            if let (status, body) = ComponentFixture.response(url) {
                deliver(url: url, status: status, body: body)
                return
            }
            if let (status, body) = IPAMFixture.response(url) {
                deliver(url: url, status: status, body: body)
                return
            }
            if let (status, body) = InventoryFixture.response(url) {
                deliver(url: url, status: status, body: body)
                return
            }
            let body: String
            var status = 200
            switch url.lastPathComponent {
            case "status": body = "{\"netbox-version\":\"4.7.2\"}"
            case "authentication-check": body = "{\"id\":1,\"username\":\"fixture-user\"}"
            case "sites": body = "{\"count\":2}"
            case "racks": body = "{\"count\":4}"
            case "devices": body = "{\"count\":12}"
            case "virtual-machines": body = "{\"count\":8}"
            case "prefixes":
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-forbidden") {
                    status = 403
                    body = "{}"
                } else { body = "{\"count\":6}" }
            case "ip-addresses": body = "{\"count\":42}"
            default: status = 404; body = "{}"
            }
            deliver(url: url, status: status, body: body)
        }
        private func deliver(url: URL, status: Int, body: String) {
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": "application/json", "ETag": "W/\"fixture-1\""]) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }
}
#endif
