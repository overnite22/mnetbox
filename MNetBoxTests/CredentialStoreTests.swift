import XCTest
@testable import MNetBox

@MainActor final class CredentialStoreTests: XCTestCase {
    final class MemoryStore: CredentialStore {
        var value: Credential?
        var failSave = false
        func load() throws -> Credential? { value }
        func save(_ credential: Credential) throws {
            if failSave { throw APIError.keychain(-1) }
            value = credential
        }
        func delete() throws { value = nil }
    }
    func makeClient(_ credential: Credential) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return APIClient(credential: credential, session: URLSession(configuration: configuration))
    }
    func waitForConnection(_ model: ConnectionModel) async {
        for _ in 0..<100 {
            if model.state != .connecting { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Connection timed out")
    }
    func testConnectRestoreDisconnect() async throws {
        let store = MemoryStore()
        let model = ConnectionModel(store: store, makeClient: makeClient)
        model.connect(url: "https://example.test", token: "test-placeholder", kind: .legacy)
        await waitForConnection(model)
        XCTAssertEqual(model.state, .connected)
        XCTAssertNotNil(store.value)
        let restored = ConnectionModel(store: store, makeClient: makeClient)
        restored.restore()
        await waitForConnection(restored)
        XCTAssertEqual(restored.state, .connected)
        restored.disconnect()
        XCTAssertNil(store.value)
        XCTAssertNil(restored.client)
        XCTAssertEqual(restored.state, .disconnected)
    }
    func testSaveFailureDoesNotAuthenticate() async {
        let store = MemoryStore()
        store.failSave = true
        let model = ConnectionModel(store: store, makeClient: makeClient)
        model.connect(url: "https://example.test", token: "test-placeholder", kind: .legacy)
        await waitForConnection(model)
        XCTAssertEqual(model.state, .disconnected)
        XCTAssertNil(model.client)
        XCTAssertNotNil(model.errorMessage)
    }
    func testDisconnectDuringValidationCannotPersistToken() async {
        let store = MemoryStore()
        let model = ConnectionModel(store: store, makeClient: makeClient)
        model.connect(url: "https://example.test", token: "test-placeholder", kind: .legacy)
        model.disconnect()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(store.value)
        XCTAssertEqual(model.state, .disconnected)
    }
    func testKeychainRoundTripAndReplacement() throws {
        let store = KeychainCredentialStore(service: "io.github.overnite22.MNetBox.tests." + UUID().uuidString)
        defer { try? store.delete() }
        XCTAssertNil(try store.load())
        let config = try NetBoxConfiguration("https://example.test")
        try store.save(Credential(configuration: config, token: "test-one", kind: .legacy))
        XCTAssertEqual(try store.load()?.token, "test-one")
        try store.save(Credential(configuration: config, token: "test-two", kind: .bearer))
        XCTAssertEqual(try store.load()?.token, "test-two")
        try store.delete()
        XCTAssertNil(try store.load())
    }
}
