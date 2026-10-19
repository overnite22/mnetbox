import Foundation

enum VLANAdminField: String, CaseIterable, Identifiable, Sendable {
    case vid, site, group, slug, tenant, ranges = "vid_ranges", scope
    var id: String { rawValue }
    var title: String { let key = switch self { case .vid: "VLAN ID"; case .site: "Site"; case .group: "VLAN group"; case .slug: "Slug"; case .tenant: "Tenant"; case .ranges: "VLAN ID ranges"; case .scope: "Scope" }; return L10n.text(key) }
    var path: String { switch self { case .site: "dcim/sites/"; case .group: "ipam/vlan-groups/"; case .tenant: "tenancy/tenants/"; default: "" } }
    func supports(_ kind: VLANBrowseKind) -> Bool { kind == .vlans ? [.vid, .site, .group].contains(self) : [.slug, .tenant, .ranges, .scope].contains(self) }
}

enum VLANAdminValue: Sendable {
    case vid(Int), reference(ReferenceSelection?), slug(String), ranges([[Int]]), scope(VLANGroupScope, ReferenceSelection?)
    func validate(field: VLANAdminField, kind: VLANBrowseKind) throws {
        guard field.supports(kind) else { throw APIError.invalidReference }
        switch (field, self) {
        case (.vid, .vid(let value)): guard (1...4094).contains(value) else { throw APIError.invalidVID }
        case (.site, .reference(let value)), (.group, .reference(let value)), (.tenant, .reference(let value)):
            guard (value?.id ?? 1) > 0 else { throw APIError.invalidReference }
        case (.slug, .slug(let value)):
            guard !value.isEmpty, value.utf8.count <= 100, value.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw APIError.invalidName }
        case (.ranges, .ranges(let values)): try VLANGroupCreationPlan.validateRanges(values)
        case (.scope, .scope(let type, let reference)):
            guard type == .global ? reference == nil : (reference?.id ?? 0) > 0 else { throw APIError.invalidReference }
        default: throw APIError.invalidReference
        }
    }
    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.vid(let a), .vid(let b)): a == b
        case (.reference(let a), .reference(let b)): a?.id == b?.id
        case (.slug(let a), .slug(let b)): a == b
        case (.ranges(let a), .ranges(let b)): a == b
        case (.scope(let a, let x), .scope(let b, let y)): a == b && x?.id == y?.id
        default: false
        }
    }
    var display: String {
        switch self {
        case .vid(let value): String(value)
        case .slug(let value): value
        case .reference(let value): value.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None")
        case .ranges(let ranges): ranges.map { "\($0[0])–\($0[1])" }.joined(separator: ", ")
        case .scope(let type, let value): L10n.text(type.title) + (value.map { " · \($0.title) (#\($0.id))" } ?? "")
        }
    }
}

struct VLANAdminPayload: Encodable, Sendable {
    let kind: VLANBrowseKind
    let field: VLANAdminField
    let value: VLANAdminValue
    private enum Keys: String, CodingKey { case vid, site, group, slug, tenant, ranges = "vid_ranges", type = "scope_type", id = "scope_id" }
    func encode(to encoder: Encoder) throws {
        try value.validate(field: field, kind: kind)
        var c = encoder.container(keyedBy: Keys.self)
        switch value {
        case .vid(let n): try c.encode(n, forKey: .vid)
        case .reference(let r): try c.encode(r?.id, forKey: field == .site ? .site : field == .group ? .group : .tenant)
        case .slug(let s): try c.encode(s, forKey: .slug)
        case .ranges(let r): try c.encode(r, forKey: .ranges)
        case .scope(let s, let r): try c.encode(s == .global ? nil : s.rawValue, forKey: .type); try c.encode(r?.id, forKey: .id)
        }
    }
}

struct VLANAdminRecord: Decodable, Sendable {
    let row: VLANBrowseRecord
    let dependency: DeletionObject?
    init(from decoder: Decoder) throws {
        row = try VLANBrowseRecord(from: decoder)
        dependency = row.vid != nil ? try DeletionObject(from: decoder) : nil
    }
    func validate(kind: VLANBrowseKind, id: Int) throws {
        try row.validate(kind: kind)
        let keys: Set<String> = kind == .vlans ? ["vid", "name", "site", "group", "tenant", "role", "status", "description", "comments", "qinq_role", "qinq_svlan", "prefix_count", "tags"] : ["name", "slug", "tenant", "vid_ranges", "scope_type", "scope_id", "scope", "vlan_count", "description", "comments", "tags"]
        guard row.id == id, keys.isSubset(of: row.knownFields) else { throw APIError.invalidResponse }
        if kind == .groups {
            guard let ranges = row.vidRanges, let slug = row.slug, let count = row.vlanCount, count >= 0 else { throw APIError.invalidResponse }
            try VLANGroupCreationPlan.validateRanges(ranges)
            try VLANAdminValue.slug(slug).validate(field: .slug, kind: kind)
            guard (row.scopeType == nil && row.scopeID == nil && row.scope == nil) || (row.scopeType != nil && (row.scopeID ?? 0) > 0 && row.scope?.id == row.scopeID) else { throw APIError.invalidResponse }
        } else { try dependency?.validate(.init(collection: .vlans, id: id)) }
    }
    func value(_ field: VLANAdminField) throws -> VLANAdminValue {
        func selection(_ label: NetBoxLabel?) -> ReferenceSelection? { label.flatMap { value in value.id.map { .init(id: $0, title: value.text) } } }
        switch field {
        case .vid: guard let vid = row.vid else { throw APIError.invalidResponse }; return .vid(vid)
        case .site: return .reference(selection(row.site))
        case .group: return .reference(selection(row.group))
        case .tenant: return .reference(selection(row.tenant))
        case .slug: guard let slug = row.slug else { throw APIError.invalidResponse }; return .slug(slug)
        case .ranges: guard let ranges = row.vidRanges else { throw APIError.invalidResponse }; return .ranges(ranges)
        case .scope:
            guard let type = VLANGroupScope(rawValue: row.scopeType ?? "") else { throw APIError.unsupportedVLANScope }
            return .scope(type, selection(row.scope))
        }
    }
    // Compare modeled metadata, excluding only the selected field and its derived totals.
    func unchanged(from other: Self, except field: VLANAdminField?) throws -> Bool {
        func data(_ record: Self) throws -> Data {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record.row)) as? [String: Any] ?? [:]
            if let field {
                if field == .scope { for key in ["scope_type", "scope_id", "scope"] { object.removeValue(forKey: key) } }
                else { object.removeValue(forKey: field.rawValue) }
                if field == .ranges { for key in ["total_vlan_ids", "utilization"] { object.removeValue(forKey: key) } }
            }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        return try data(self) == data(other)
    }
}

struct VLANAdminSnapshot: Sendable {
    let kind: VLANBrowseKind
    let field: VLANAdminField
    let record: VLANAdminRecord
    let etag: String
    var path: String { kind.path + "\(record.row.id)/" }
}
