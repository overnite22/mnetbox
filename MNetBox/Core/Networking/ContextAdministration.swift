import Foundation

extension ContextKind {
    var writable: Bool { [.vrfs, .tenants, .roles].contains(self) }
}
enum ContextEditField: String, CodingKey, CaseIterable, Identifiable, Sendable {
    case name, slug, tenant, group, weight, description, comments
    var id: String { rawValue }
    var title: String { let text = switch self { case .name: "Name"; case .slug: "Slug"; case .tenant: "Tenant"; case .group: "Tenant group"; case .weight: "Weight"; case .description: "Description"; case .comments: "Comments" }; return L10n.text(text) }
    var path: String { self == .tenant ? "tenancy/tenants/" : "tenancy/tenant-groups/" }
    func supports(_ kind: ContextKind) -> Bool { kind.writable && ([.name, .description, .comments].contains(self) || (self == .tenant && kind == .vrfs) || (self == .group && kind == .tenants) || (self == .slug && kind != .vrfs) || (self == .weight && kind == .roles)) }
}
enum ContextEditValue: Sendable {
    case text(String), reference(ReferenceSelection?), number(Int)
    func validate(field: ContextEditField, kind: ContextKind) throws {
        guard field.supports(kind) else { throw APIError.invalidReference }
        switch (field, self) {
        case (.name, .text(let text)):
            guard !text.isEmpty, text == text.trimmingCharacters(in: .whitespacesAndNewlines), text.unicodeScalars.count <= 100, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidName }
        case (.slug, .text(let text)): try VLANAdminValue.slug(text).validate(field: .slug, kind: .groups)
        case (.description, .text(let text)): try EditableTextField.description.validate(text)
        case (.comments, .text(let text)): try EditableTextField.comments.validate(text)
        case (.tenant, .reference(let ref)), (.group, .reference(let ref)): guard (ref?.id ?? 1) > 0 else { throw APIError.invalidReference }
        case (.weight, .number(let n)): guard (0...32767).contains(n) else { throw APIError.invalidWeight }
        default: throw APIError.invalidReference
        }
    }
    func matches(_ other: Self) -> Bool { switch (self, other) { case (.text(let a), .text(let b)): a == b; case (.reference(let a), .reference(let b)): a?.id == b?.id; case (.number(let a), .number(let b)): a == b; default: false } }
    var display: String { switch self { case .text(let s): s.isEmpty ? L10n.text("Empty") : s; case .reference(let r): r.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None"); case .number(let n): String(n) } }
}
struct ContextEditPayload: Encodable, Sendable {
    let kind: ContextKind; let field: ContextEditField; let value: ContextEditValue
    func encode(to encoder: Encoder) throws {
        try value.validate(field: field, kind: kind)
        var c = encoder.container(keyedBy: ContextEditField.self)
        switch value { case .text(let text): try c.encode(text, forKey: field); case .reference(let ref): try c.encode(ref?.id, forKey: field); case .number(let n): try c.encode(n, forKey: field) }
    }
}
struct ContextCreationPlan: Encodable, Sendable {
    let kind: ContextKind
    let name: String; let slug: String; let rd: String; let unique: Bool
    let tenant: ReferenceSelection?; let group: ReferenceSelection?; let weight: Int
    let description: String; let comments: String
    func validate() throws {
        try ContextEditValue.text(name).validate(field: .name, kind: kind)
        try ContextEditValue.text(description).validate(field: .description, kind: kind)
        try ContextEditValue.text(comments).validate(field: .comments, kind: kind)
        if kind != .vrfs { try ContextEditValue.text(slug).validate(field: .slug, kind: kind) }
        if kind == .roles { try ContextEditValue.number(weight).validate(field: .weight, kind: kind) }
        guard rd.unicodeScalars.count <= 21, !rd.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), rd == rd.trimmingCharacters(in: .whitespacesAndNewlines),
              (tenant?.id ?? 1) > 0, (group?.id ?? 1) > 0,
              (kind == .vrfs || tenant == nil), (kind == .tenants || group == nil) else { throw APIError.invalidReference }
    }
    enum Keys: String, CodingKey { case name, slug, rd, unique = "enforce_unique", tenant, group, weight, description, comments }
    func encode(to encoder: Encoder) throws {
        try validate(); var c = encoder.container(keyedBy: Keys.self)
        try c.encode(name, forKey: .name); try c.encode(description, forKey: .description); try c.encode(comments, forKey: .comments)
        if kind == .vrfs { try c.encode(rd.isEmpty ? nil : rd, forKey: .rd); try c.encode(unique, forKey: .unique); try c.encode(tenant?.id, forKey: .tenant) }
        else { try c.encode(slug, forKey: .slug); if kind == .tenants { try c.encode(group?.id, forKey: .group) } else { try c.encode(weight, forKey: .weight) } }
    }
    func matches(_ record: ContextAdminRecord) -> Bool {
        let row = record.row
        guard row.name == name, row.description == description, row.comments == comments else { return false }
        switch kind {
        case .vrfs: return row.rd == (rd.isEmpty ? nil : rd) && row.enforceUnique == unique && row.tenant?.id == tenant?.id && row.importTargets?.isEmpty == true && row.exportTargets?.isEmpty == true
        case .tenants: return row.slug == slug && row.group?.id == group?.id
        case .roles: return row.slug == slug && row.weight == weight
        default: return false
        }
    }
}
struct ContextAdminRecord: Decodable, Sendable {
    let row: ContextRecord; let fields: Set<String>
    private struct Key: CodingKey { let stringValue: String; var intValue: Int? { nil }; init(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    init(from decoder: Decoder) throws {
        row = try ContextRecord(from: decoder); let c = try decoder.container(keyedBy: Key.self); fields = Set(c.allKeys.map(\.stringValue))
    }
    func validate(_ kind: ContextKind, id: Int? = nil) throws {
        try row.validate()
        var required: Set<String> = ["id", "name", "description", "comments", "tags"]
        switch kind { case .vrfs: required.formUnion(["rd", "tenant", "enforce_unique", "import_targets", "export_targets"]); case .tenants: required.formUnion(["slug", "group"]); case .roles: required.formUnion(["slug", "weight"]); default: throw APIError.invalidReference }
        guard required.isSubset(of: fields), id == nil || row.id == id, row.description != nil, row.comments != nil, row.tags != nil else { throw APIError.invalidResponse }
        try ContextEditValue.text(row.name).validate(field: .name, kind: kind)
        if kind != .vrfs { guard let slug = row.slug else { throw APIError.invalidResponse }; try ContextEditValue.text(slug).validate(field: .slug, kind: kind) }
        if kind == .roles { guard let n = row.weight else { throw APIError.invalidResponse }; try ContextEditValue.number(n).validate(field: .weight, kind: kind) }
        if kind == .vrfs { guard row.enforceUnique != nil, let imports = row.importTargets, let exports = row.exportTargets, (imports + exports).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse } }
    }
    func value(_ field: ContextEditField) throws -> ContextEditValue {
        func ref(_ label: NetBoxLabel?) -> ContextEditValue { .reference(label.flatMap { r in r.id.map { .init(id: $0, title: r.text) } }) }
        switch field { case .name: return .text(row.name); case .slug: guard let s = row.slug else { throw APIError.invalidResponse }; return .text(s); case .description: return .text(row.description ?? ""); case .comments: return .text(row.comments ?? ""); case .tenant: return ref(row.tenant); case .group: return ref(row.group); case .weight: guard let n = row.weight else { throw APIError.invalidResponse }; return .number(n) }
    }
    func unchanged(from other: Self, except field: ContextEditField? = nil) throws -> Bool {
        func signature(_ row: ContextRecord) throws -> Data {
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any] ?? [:]
            if let field { object.removeValue(forKey: field.rawValue); object.removeValue(forKey: "display") }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        return try signature(row) == signature(other.row)
    }
}
struct ContextAdminPage: Decodable, Sendable { let count: Int; let next: String?; let results: [ContextAdminRecord] }
struct ContextEditSnapshot: Sendable { let kind: ContextKind; let field: ContextEditField; let record: ContextAdminRecord; let etag: String; var path: String { kind.path + "\(record.row.id)/" } }
