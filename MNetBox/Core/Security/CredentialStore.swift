import Foundation
import Security

@MainActor protocol CredentialStore {
    func load() throws -> Credential?
    func save(_ credential: Credential) throws
    func delete() throws
}

@MainActor final class KeychainCredentialStore: CredentialStore {
    private let service: String
    init(service: String = "io.github.overnite22.MNetBox.connection") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "connection"]
    }
    func load() throws -> Credential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw APIError.keychain(status) }
        guard let data = result as? Data else { throw APIError.invalidResponse }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    func save(_ credential: Credential) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credential),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.keychain(status) }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain(status) }
    }
}
