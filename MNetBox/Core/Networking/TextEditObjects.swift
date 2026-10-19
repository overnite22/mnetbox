import Foundation

struct TextEditTarget: Sendable, Equatable {
    enum Collection: String, Sendable, CaseIterable {
        case sites = "dcim/sites/", racks = "dcim/racks/", devices = "dcim/devices/"
        case virtualMachines = "virtualization/virtual-machines/"
        case prefixes = "ipam/prefixes/", ipAddresses = "ipam/ip-addresses/"
        case vlanGroups = "ipam/vlan-groups/"
        case vlans = "ipam/vlans/", macAddresses = "dcim/mac-addresses/"
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
    struct EditStatus: Codable, Sendable { let value: String; let label: String? }
    enum CodingKeys: String, CodingKey { case id, display, name, status, prefix, address, description, comments; case dnsName = "dns_name" }
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
    }
    func value(for field: EditableTextField) -> String? {
        switch field {
        case .description: description
        case .comments: comments
        case .dnsName: dnsName
        case .name: hasName ? (name ?? "") : nil
        case .status: status?.value
        }
    }
    var title: String { display ?? name ?? prefix ?? address ?? "#\(id)" }
}
enum EditableTextField: String, CodingKey, CaseIterable, Identifiable, Sendable {
    case description, comments, dnsName = "dns_name", name, status
    var id: String { rawValue }
    var title: String {
        L10n.text(self == .name ? "Name" : self == .status ? "Status" : self == .dnsName ? "DNS name" : self == .comments ? "Comments" : "Description")
    }
    var editTitle: String {
        L10n.text(self == .name ? "Edit name" : self == .status ? "Edit status" : self == .dnsName ? "Edit DNS name" : self == .comments ? "Edit comments" : "Edit description")
    }
    var savedTitle: String {
        L10n.text(self == .name ? "Name saved" : self == .status ? "Status saved" : self == .dnsName ? "DNS name saved" : self == .comments ? "Comments saved" : "Description saved")
    }
    var limit: Int { self == .name ? 64 : self == .status ? 50 : self == .description ? 200 : self == .dnsName ? 255 : 10000 }
    func supports(_ collection: TextEditTarget.Collection) -> Bool {
        if self == .name, collection == .vlanGroups { return true }
        if self == .name || self == .status { return collection == .devices || collection == .virtualMachines || collection == .vlans }
        return self != .dnsName || collection == .ipAddresses
    }
    func statusChoices(for collection: TextEditTarget.Collection) -> [String] {
        switch collection {
        case .devices: InventoryKind.devices.statuses
        case .virtualMachines: InventoryKind.virtualMachines.statuses
        case .vlans: ["active", "reserved", "deprecated"]
        default: []
        }
    }
    func displayValue(_ value: String) -> String {
        if value.isEmpty { return L10n.text("Empty") }
        return self == .status ? L10n.text(value.capitalized) : value
    }
    func normalized(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return self == .dnsName ? value.lowercased() : value
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
        if self == .status {
            guard let collection, statusChoices(for: collection).contains(value) else { throw APIError.invalidStatus }
        }
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
