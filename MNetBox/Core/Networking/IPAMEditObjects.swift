import Foundation

enum PrefixScope: String, CaseIterable, Identifiable, Sendable {
    case global = "", region = "dcim.region", siteGroup = "dcim.sitegroup", site = "dcim.site", location = "dcim.location"
    var id: String { rawValue }
    var title: String { VLANGroupScope(rawValue: rawValue)?.title ?? "Scope" }
    var path: String { VLANGroupScope(rawValue: rawValue)?.path ?? "" }
}
enum IPAMEditField: String, Identifiable, Sendable {
    case vlan, role, scope, cidr, vrf
    var id: String { rawValue }
    var title: String { L10n.text(self == .vlan ? "VLAN" : self == .vrf ? "VRF" : self == .cidr ? "Address / prefix" : rawValue.capitalized) }
    var moving: Bool { self == .cidr || self == .vrf }
    func supports(_ kind: IPAMKind) -> Bool { moving || kind == .prefixes }
    var path: String { self == .vlan ? "ipam/vlans/" : self == .role ? "ipam/roles/" : "ipam/vrfs/" }
}
enum IPAMEditValue: Sendable {
    case reference(ReferenceSelection?), scope(PrefixScope, ReferenceSelection?), cidr(IPAMCIDR)
    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case let (.reference(a), .reference(b)): a?.id == b?.id
        case let (.scope(a, x), .scope(b, y)): a == b && x?.id == y?.id
        case let (.cidr(a), .cidr(b)): a == b
        default: false
        }
    }
    var display: String {
        switch self {
        case .reference(let value): value.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None")
        case .scope(let type, let value): L10n.text(type.title) + (value.map { " · \($0.title) (#\($0.id))" } ?? "")
        case .cidr(let value): value.text
        }
    }
    func display(for field: IPAMEditField) -> String {
        if field == .vrf, case .reference(nil) = self { return L10n.text("Global") }
        return display
    }
    func validate(field: IPAMEditField, kind: IPAMKind) throws {
        guard field.supports(kind) else { throw APIError.invalidURL }
        switch (field, self) {
        case (.scope, .scope(let type, let value)):
            guard type == .global ? value == nil : (value?.id ?? 0) > 0 else { throw APIError.invalidReference }
        case (.cidr, .cidr(let value)):
            _ = try IPAMCIDR(value.text, network: kind == .prefixes)
            guard value.mask > 0 else { throw APIError.invalidCIDR }
        case (.vlan, .reference(let value)), (.role, .reference(let value)), (.vrf, .reference(let value)):
            guard (value?.id ?? 1) > 0 else { throw APIError.invalidReference }
        default: throw APIError.invalidResponse
        }
    }
}
struct IPAMEditRecord: Decodable, Sendable {
    let object: IPAMObject
    let dependencies: DeletionObject
    let statusValue: String
    let ipRoleValue: String?
    let scopeID: Int?
    let known: Set<String>
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private enum Keys: String, CodingKey { case status, role; case scopeID = "scope_id" }
    init(from decoder: Decoder) throws {
        object = try IPAMObject(from: decoder)
        dependencies = try DeletionObject(from: decoder)
        struct Choice: Decodable { let value: String? }
        let fields = try decoder.container(keyedBy: Keys.self)
        guard let status = try fields.decode(Choice.self, forKey: .status).value, !status.isEmpty else { throw APIError.invalidResponse }
        statusValue = status
        ipRoleValue = object.address == nil ? nil : try fields.decodeIfPresent(Choice.self, forKey: .role)?.value
        scopeID = try decoder.container(keyedBy: Keys.self).decodeIfPresent(Int.self, forKey: .scopeID)
        known = Set(try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue))
    }
    func validate(kind: IPAMKind, id: Int) throws {
        try dependencies.validate(.init(collection: kind == .prefixes ? .prefixes : .ipAddresses, id: id))
        let required = kind == .prefixes ? ["prefix", "vlan", "scope_type", "scope_id", "scope", "children"] : ["address", "dns_name", "assigned_object_type", "assigned_object_id", "assigned_object", "nat_inside", "nat_outside"]
        guard object.id == id, id > 0, Set(required + ["family", "vrf", "tenant", "role", "status", "description", "comments"]).isSubset(of: known),
              [object.vrf, object.tenant, object.vlan].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
        let parsed = try IPAMCIDR(object.title, network: kind == .prefixes)
        guard parsed.mask > 0, object.family?.value == parsed.family else { throw APIError.invalidResponse }
        if kind == .prefixes {
            guard object.scopeType == nil ? scopeID == nil && object.scope == nil : (scopeID ?? 0) > 0 && (object.scope == nil || object.scope?.id == scopeID),
                  (object.role?.id ?? 1) > 0 else { throw APIError.invalidResponse }
        }
    }
    func value(_ field: IPAMEditField, kind: IPAMKind) throws -> IPAMEditValue {
        switch field {
        case .cidr: return .cidr(try IPAMCIDR(object.title, network: kind == .prefixes))
        case .scope:
            guard let type = PrefixScope(rawValue: object.scopeType ?? "") else { throw APIError.unsupportedPrefixScope }
            return .scope(type, scopeID.map { ReferenceSelection(id: $0, title: object.scope?.text ?? "#\($0)") })
        case .vlan, .role, .vrf:
            let ref = field == .vlan ? object.vlan : field == .role ? object.role : object.vrf
            return .reference(ref.flatMap { value in value.id.map { ReferenceSelection(id: $0, title: value.text) } })
        }
    }
    func preserved(comparedTo before: Self, field: IPAMEditField) -> Bool {
        let a = object, b = before.object
        return a.id == b.id && (field == .cidr || a.title == b.title) && (field == .vrf || a.vrf?.id == b.vrf?.id)
            && (field == .vlan || a.vlan?.id == b.vlan?.id) && (field == .role || a.role?.id == b.role?.id)
            && (field == .scope || (a.scopeType == b.scopeType && scopeID == before.scopeID))
            && a.tenant?.id == b.tenant?.id && statusValue == before.statusValue && ipRoleValue == before.ipRoleValue && a.description == b.description && a.comments == b.comments
            && a.dnsName == b.dnsName && a.assignedObjectType == b.assignedObjectType && a.assignedObjectID == b.assignedObjectID
    }
}
struct IPAMEditSnapshot: Sendable {
    let kind: IPAMKind
    let id: Int
    let field: IPAMEditField
    let record: IPAMEditRecord
    let etag: String
}
struct IPAMEditPayload: Encodable {
    let kind: IPAMKind
    let field: IPAMEditField
    let value: IPAMEditValue
    private enum Keys: String, CodingKey { case vlan, role, vrf, prefix, address; case type = "scope_type", id = "scope_id" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch value {
        case .cidr(let cidr): try c.encode(cidr.text, forKey: kind == .prefixes ? .prefix : .address)
        case .scope(let type, let value):
            try c.encode(type == .global ? nil : type.rawValue, forKey: .type); try c.encode(value?.id, forKey: .id)
        case .reference(let value): try c.encode(value?.id, forKey: field == .vrf ? .vrf : field == .vlan ? .vlan : .role)
        }
    }
}

struct IPAMEditPage: Decodable, Sendable { let count: Int; let next: String?; let results: [IPAMEditRecord] }
