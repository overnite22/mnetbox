import Foundation

struct InterfaceCreationDraft: Sendable {
    let kind: InterfaceKind
    let parentID: Int
    var name = ""
    var type = "virtual"
    var enabled = true
    var mtu = ""
    var description = ""
    static let types = InterfaceTypeOptions.values
    static func normalizedName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw APIError.requiredInterfaceName }
        guard name.unicodeScalars.count <= 64 else { throw APIError.textTooLong(64) }
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidName }
        return name
    }
    func plan() throws -> InterfaceCreationPlan {
        guard parentID > 0 else { throw APIError.invalidReference }
        let name = try Self.normalizedName(name)
        guard Self.types.contains(type) else { throw APIError.invalidResponse }
        let text = mtu.trimmingCharacters(in: .whitespacesAndNewlines)
        var number: Int?
        if !text.isEmpty {
            guard text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text), (1...65536).contains(value) else { throw APIError.invalidMTU }
            number = value
        }
        let description = EditableTextField.description.normalized(description)
        try EditableTextField.description.validate(description)
        return InterfaceCreationPlan(kind: kind, parentID: parentID, name: name, type: type, enabled: enabled, mtu: number, description: description)
    }
}
struct InterfaceCreationPlan: Encodable, Sendable {
    let kind: InterfaceKind
    let parentID: Int
    let name: String
    let type: String
    let enabled: Bool
    let mtu: Int?
    let description: String
    enum Keys: String, CodingKey { case device, name, type, enabled, mtu, description; case vm = "virtual_machine" }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: Keys.self)
        try fields.encode(parentID, forKey: kind == .physical ? .device : .vm)
        try fields.encode(name, forKey: .name)
        if kind == .physical { try fields.encode(type, forKey: .type) }
        try fields.encode(enabled, forKey: .enabled)
        try fields.encode(mtu, forKey: .mtu)
        try fields.encode(description, forKey: .description)
    }
    func validated() throws -> Self {
        try InterfaceCreationDraft(kind: kind, parentID: parentID, name: name, type: type, enabled: enabled, mtu: mtu.map(String.init) ?? "", description: description).plan()
    }
}
struct InterfaceCreationReply: Decodable, Sendable {
    let object: InterfaceObject
    let type: String?
    private struct Choice: Decodable { let value: String }
    private enum Keys: String, CodingKey { case type }
    init(from decoder: Decoder) throws {
        object = try InterfaceObject(from: decoder)
        type = try decoder.container(keyedBy: Keys.self).decodeIfPresent(Choice.self, forKey: .type)?.value
    }
}

// Pinned common choices shared by creation and editing. Other current types remain readable.
enum InterfaceTypeOptions {
    static let values = ["virtual", "1000base-t", "10gbase-x-sfpp", "lag", "other"]
    static func title(_ value: String) -> String {
        switch value {
        case "virtual": L10n.text("Virtual")
        case "1000base-t": "1000BASE-T (1 GbE)"
        case "10gbase-x-sfpp": "10GBASE-X SFP+ (10 GbE)"
        case "lag": L10n.text("Link aggregation")
        case "other": L10n.text("Other")
        default: value
        }
    }
}
