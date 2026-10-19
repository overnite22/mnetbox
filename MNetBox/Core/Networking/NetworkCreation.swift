import Foundation

struct VLANCreationPlan: Encodable, Sendable {
    let vid: Int
    let name: String
    let status: String
    let site: ReferenceSelection?
    let group: ReferenceSelection?
    let tenant: ReferenceSelection?
    let role: ReferenceSelection?
    let description: String
    let comments: String
    func validate() throws {
        guard (1...4094).contains(vid) else { throw APIError.invalidVID }
        try EditableTextField.name.validate(name, for: .vlans)
        guard EditableTextField.name.normalized(name) == name else { throw APIError.invalidName }
        try EditableTextField.status.validate(status, for: .vlans)
        try EditableTextField.description.validate(description)
        try EditableTextField.comments.validate(comments)
        guard [site, group, tenant, role].compactMap({ $0 }).allSatisfy({ $0.id > 0 }) else { throw APIError.invalidReference }
    }
    enum CodingKeys: String, CodingKey { case vid, name, status, site, group, tenant, role, description, comments }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vid, forKey: .vid); try c.encode(name, forKey: .name); try c.encode(status, forKey: .status)
        try c.encode(site?.id, forKey: .site); try c.encode(group?.id, forKey: .group)
        try c.encode(tenant?.id, forKey: .tenant); try c.encode(role?.id, forKey: .role)
        try c.encode(description, forKey: .description); try c.encode(comments, forKey: .comments)
    }
    func matches(_ row: VLANBrowseRecord) -> Bool {
        row.id > 0 && row.vid == vid && row.name == name && row.status?.value == status && row.site?.id == site?.id
            && row.group?.id == group?.id && row.tenant?.id == tenant?.id && row.role?.id == role?.id
            && row.description == description && row.comments == comments
            && Set(["site", "group", "tenant", "role", "qinq_role", "qinq_svlan"]).isSubset(of: row.knownFields)
            && row.qinqRole?.value == nil && row.qinqSVLAN == nil
    }
}

struct MACValue: Equatable, Sendable {
    let text: String
    init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact: String
        if value.range(of: "^[0-9A-Fa-f]{12}$", options: .regularExpression) != nil { compact = value }
        else if value.range(of: "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil { compact = value.replacingOccurrences(of: ":", with: "") }
        else if value.range(of: "^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil { compact = value.replacingOccurrences(of: "-", with: "") }
        else if value.range(of: "^([0-9A-Fa-f]{4}\\.){2}[0-9A-Fa-f]{4}$", options: .regularExpression) != nil { compact = value.replacingOccurrences(of: ".", with: "") }
        else { throw APIError.invalidMAC }
        let chars = Array(compact.uppercased())
        text = stride(from: 0, to: 12, by: 2).map { String(chars[$0...($0 + 1)]) }.joined(separator: ":")
    }
}

struct MACCreationPlan: Encodable, Sendable {
    let address: MACValue
    let interface: InterfaceSelection
    let description: String
    let comments: String
    func validate() throws {
        guard interface.id > 0, (interface.parentID ?? 0) > 0 else { throw APIError.invalidReference }
        try EditableTextField.description.validate(description); try EditableTextField.comments.validate(comments)
    }
    enum CodingKeys: String, CodingKey { case address = "mac_address", type = "assigned_object_type", id = "assigned_object_id", description, comments }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(address.text, forKey: .address); try c.encode(interface.kind.rawValue, forKey: .type)
        try c.encode(interface.id, forKey: .id); try c.encode(description, forKey: .description); try c.encode(comments, forKey: .comments)
    }
}
