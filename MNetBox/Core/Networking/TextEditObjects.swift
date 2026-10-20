import Foundation

struct TextEditTarget: Sendable, Equatable {
    enum Collection: String, Sendable, CaseIterable {
        case sites = "dcim/sites/", racks = "dcim/racks/", devices = "dcim/devices/"
        case virtualMachines = "virtualization/virtual-machines/"
        case prefixes = "ipam/prefixes/", ipAddresses = "ipam/ip-addresses/"
        case vlanGroups = "ipam/vlan-groups/"
        case vlans = "ipam/vlans/", macAddresses = "dcim/mac-addresses/"
        case cables = "dcim/cables/"
    }
    let collection: Collection
    let id: Int
    var path: String { get throws { guard id > 0 else { throw APIError.invalidURL }; return collection.rawValue + "\(id)/" } }
}
struct TextEditObject: Codable, Sendable {
    let id: Int
    let display: String?
    let name: String?
    private let hasName: Bool
    let status: EditStatus?
    let prefix: String?
    let address: String?
    let description: String
    let comments: String?
    let dnsName: String?
    let label: String?
    let cableType: String?
    let color: String?
    struct EditStatus: Codable, Sendable { let value: String; let label: String? }
    enum CodingKeys: String, CodingKey { case id, display, name, status, prefix, address, description, comments, label, color; case dnsName = "dns_name", cableType = "type" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        display = try values.decodeIfPresent(String.self, forKey: .display)
        hasName = values.contains(.name)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        status = try values.decodeIfPresent(EditStatus.self, forKey: .status)
        prefix = try values.decodeIfPresent(String.self, forKey: .prefix)
        address = try values.decodeIfPresent(String.self, forKey: .address)
        description = try values.decode(String.self, forKey: .description)
        comments = try values.decodeIfPresent(String.self, forKey: .comments)
        dnsName = try values.decodeIfPresent(String.self, forKey: .dnsName)
        // Only cables edit these as plain strings; other shapes are ignored, never coerced.
        label = (try? values.decodeIfPresent(String.self, forKey: .label)) ?? nil
        cableType = (try? values.decodeIfPresent(String.self, forKey: .cableType)) ?? nil
        color = (try? values.decodeIfPresent(String.self, forKey: .color)) ?? nil
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(display, forKey: .display)
        if hasName { try values.encode(name, forKey: .name) }
        try values.encodeIfPresent(status, forKey: .status)
        try values.encodeIfPresent(prefix, forKey: .prefix)
        try values.encodeIfPresent(address, forKey: .address)
        try values.encode(description, forKey: .description)
        try values.encodeIfPresent(comments, forKey: .comments)
        try values.encodeIfPresent(dnsName, forKey: .dnsName)
        try values.encodeIfPresent(label, forKey: .label)
        try values.encodeIfPresent(cableType, forKey: .cableType)
        try values.encodeIfPresent(color, forKey: .color)
    }
    func value(for field: EditableTextField) -> String? {
        switch field {
        case .description: description
        case .comments: comments
        case .dnsName: dnsName
        case .name: hasName ? (name ?? "") : nil
        case .status: status?.value
        case .label: label
        case .type: cableType
        case .color: color
        }
    }
    var title: String { display ?? name ?? prefix ?? address ?? "#\(id)" }
}
enum EditableTextField: String, CodingKey, CaseIterable, Identifiable, Sendable {
    case description, comments, dnsName = "dns_name", name, status, label, type, color
    var id: String { rawValue }
    private var key: String {
        switch self {
        case .description: "Description"
        case .comments: "Comments"
        case .dnsName: "DNS name"
        case .name: "Name"
        case .status: "Status"
        case .label: "Label"
        case .type: "Type"
        case .color: "Color"
        }
    }
    var title: String { L10n.text(key) }
    var editTitle: String { L10n.text("Edit " + (self == .dnsName ? "DNS name" : key.lowercased())) }
    var savedTitle: String { L10n.text((self == .dnsName ? "DNS name" : key) + " saved") }
    var limit: Int {
        switch self {
        case .name: 64
        case .status, .type: 50
        case .label: 100
        case .color: 6
        case .description: 200
        case .dnsName: 255
        case .comments: 10000
        }
    }
    /// Fields edited by choosing a server value rather than typing text.
    var isChoice: Bool { self == .status || self == .type || self == .color }
    func supports(_ collection: TextEditTarget.Collection) -> Bool {
        switch self {
        case .name: [.devices, .virtualMachines, .vlans, .vlanGroups].contains(collection)
        case .status: [.devices, .virtualMachines, .vlans, .cables].contains(collection)
        case .label, .type, .color: collection == .cables
        case .dnsName: collection == .ipAddresses
        case .description, .comments: true
        }
    }
    func choices(for collection: TextEditTarget.Collection) -> [String] {
        switch (self, collection) {
        case (.status, .devices): InventoryKind.devices.statuses
        case (.status, .virtualMachines): InventoryKind.virtualMachines.statuses
        case (.status, .vlans): ["active", "reserved", "deprecated"]
        case (.status, .cables): ["connected", "planned", "decommissioning"]
        case (.type, .cables): CableCreationPlan.types
        case (.color, .cables): [""] + CableCreationPlan.colors
        default: []
        }
    }
    func displayValue(_ value: String) -> String {
        switch self {
        case .type: return value.isEmpty ? L10n.text("Unspecified") : value
        case .color: return CableCreationPlan.colorName(value)
        case .status: return value.isEmpty ? L10n.text("Empty") : L10n.text(value.capitalized)
        default: return value.isEmpty ? L10n.text("Empty") : value
        }
    }
    func normalized(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return self == .dnsName || self == .color ? value.lowercased() : value
    }
    func validate(_ value: String, for collection: TextEditTarget.Collection? = nil) throws {
        let limit = collection == .vlanGroups && self == .name ? 100 : limit
        guard value.unicodeScalars.count <= limit else {
            if self == .description { throw APIError.descriptionTooLong }
            throw APIError.textTooLong(limit)
        }
        if self == .name {
            if collection == .vlanGroups, value.isEmpty { throw APIError.requiredName }
            if collection == .virtualMachines, value.isEmpty { throw APIError.requiredName }
            if collection == .vlans, value.isEmpty { throw APIError.requiredVLANName }
            if value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { throw APIError.invalidName }
        }
        if isChoice {
            guard let collection, choices(for: collection).contains(value) else { throw APIError.invalidStatus }
        }
        if self == .label, value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { throw APIError.invalidName }
        // Match NetBox 4.7.2's DNSValidator, including its supported wildcard/underscore syntax.
        if self == .dnsName, !value.isEmpty,
           value.range(of: #"\A([0-9A-Za-z_-]+|\*)(\.[0-9A-Za-z_-]+)*\.?\z"#, options: .regularExpression) == nil {
            throw APIError.invalidDNSName
        }
    }
}
struct TextEditPayload: Encodable {
    let field: EditableTextField
    let value: String
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EditableTextField.self)
        // Devices may be unnamed. VM validation rejects empty names before encoding.
        if field == .name, value.isEmpty { try container.encodeNil(forKey: field) }
        else { try container.encode(value, forKey: field) }
    }
}
struct TextEditSnapshot: Sendable {
    let target: TextEditTarget
    let object: TextEditObject
    let etag: String
    let field: EditableTextField
    init(target: TextEditTarget, object: TextEditObject, etag: String, field: EditableTextField = .description) {
        self.target = target; self.object = object; self.etag = etag; self.field = field
    }
    static func validETag(_ tag: String) -> Bool {
        let value = tag.hasPrefix("W/") ? String(tag.dropFirst(2)) : tag
        return value.count > 2 && value.first == "\"" && value.last == "\""
            && !value.dropFirst().dropLast().contains("\"")
            && !value.contains(",") && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
