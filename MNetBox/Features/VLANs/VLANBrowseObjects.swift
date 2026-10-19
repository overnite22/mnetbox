import Foundation

enum VLANBrowseKind: String, CaseIterable, Sendable {
    case vlans, groups
    var path: String { self == .vlans ? "ipam/vlans/" : "ipam/vlan-groups/" }
    var title: String { L10n.text(self == .vlans ? "VLANs" : "VLAN groups") }
    var singular: String { L10n.text(self == .vlans ? "VLAN" : "VLAN group") }
}

struct VLANBrowseChoice: Codable, Sendable {
    let value: String?
    let label: String?
    var text: String { label ?? value ?? "—" }
}

// Reads tolerate unknown choices and group scope types. Filtered nullable relations
// must be explicitly present, so an omitted relation never becomes a global match.
struct VLANBrowseRecord: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let slug: String?
    let vid: Int?
    let site: NetBoxLabel?
    let group: NetBoxLabel?
    let tenant: NetBoxLabel?
    let role: NetBoxLabel?
    let status: VLANBrowseChoice?
    let description: String?
    let comments: String?
    let tags: [NetBoxLabel]?
    let qinqRole: VLANBrowseChoice?
    let qinqSVLAN: NetBoxLabel?
    let scopeType: String?
    let scopeID: Int?
    let scope: NetBoxLabel?
    let vidRanges: [[Int]]?
    let vlanCount: Int?
    let prefixCount: Int?
    let totalVLANIDs: Int?
    let utilization: NetBoxQuantity?
    var knownFields: Set<String> = []
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, slug, vid, site, group, tenant, role, status, description, comments, tags, scope, utilization
        case qinqRole = "qinq_role", qinqSVLAN = "qinq_svlan", scopeType = "scope_type", scopeID = "scope_id"
        case vidRanges = "vid_ranges", vlanCount = "vlan_count", prefixCount = "prefix_count", totalVLANIDs = "total_vlan_ids"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        vid = try c.decodeIfPresent(Int.self, forKey: .vid)
        site = try c.decodeIfPresent(NetBoxLabel.self, forKey: .site); group = try c.decodeIfPresent(NetBoxLabel.self, forKey: .group)
        tenant = try c.decodeIfPresent(NetBoxLabel.self, forKey: .tenant); role = try c.decodeIfPresent(NetBoxLabel.self, forKey: .role)
        status = try c.decodeIfPresent(VLANBrowseChoice.self, forKey: .status)
        description = try c.decodeIfPresent(String.self, forKey: .description); comments = try c.decodeIfPresent(String.self, forKey: .comments)
        tags = try c.decodeIfPresent([NetBoxLabel].self, forKey: .tags)
        qinqRole = try c.decodeIfPresent(VLANBrowseChoice.self, forKey: .qinqRole); qinqSVLAN = try c.decodeIfPresent(NetBoxLabel.self, forKey: .qinqSVLAN)
        scopeType = try c.decodeIfPresent(String.self, forKey: .scopeType); scopeID = try c.decodeIfPresent(Int.self, forKey: .scopeID)
        scope = try c.decodeIfPresent(NetBoxLabel.self, forKey: .scope)
        vidRanges = try c.decodeIfPresent([[Int]].self, forKey: .vidRanges)
        vlanCount = try c.decodeIfPresent(Int.self, forKey: .vlanCount); prefixCount = try c.decodeIfPresent(Int.self, forKey: .prefixCount)
        totalVLANIDs = try c.decodeIfPresent(Int.self, forKey: .totalVLANIDs); utilization = try c.decodeIfPresent(NetBoxQuantity.self, forKey: .utilization)
        knownFields = Set(CodingKeys.allCases.filter { c.contains($0) }.map(\.rawValue))
    }
    func validate(kind: VLANBrowseKind) throws {
        guard id > 0, !name.isEmpty,
              [site, group, tenant, role, qinqSVLAN].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }),
              [vlanCount, prefixCount, totalVLANIDs].compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else { throw APIError.invalidResponse }
        if kind == .vlans {
            guard let vid, (1...4094).contains(vid) else { throw APIError.invalidResponse }
        } else if let ranges = vidRanges {
            guard ranges.allSatisfy({ $0.count == 2 && (1...4094).contains($0[0]) && ($0[0]...4094).contains($0[1]) }) else { throw APIError.invalidResponse }
        }
    }
    var title: String { vid.map { "\($0) · \(name)" } ?? name }
    var scopeText: String {
        if scopeType == nil, scopeID == nil, scope == nil, knownFields.contains("scope_type"), knownFields.contains("scope_id") { return L10n.text("Global") }
        return [scope?.text, scopeType, scopeID.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    var linkedScope: (InventoryKind, Int)? {
        guard let scopeID, scopeID > 0, scope?.id == scopeID else { return nil }
        if scopeType == "dcim.site" { return (.sites, scopeID) }
        if scopeType == "dcim.rack" { return (.racks, scopeID) }
        return nil
    }
}

struct VLANBrowseQuery: Equatable, Sendable {
    var search = ""
    var status = ""
    // ID 0 explicitly selects no direct site / no VLAN group, not all objects.
    var site: ReferenceSelection?
    var group: ReferenceSelection?
    var tenant: ReferenceSelection?
    var role: ReferenceSelection?
    func items(kind: VLANBrowseKind) throws -> [URLQueryItem] {
        guard (site?.id ?? 0) >= 0, (group?.id ?? 0) >= 0, (tenant?.id ?? 1) > 0, (role?.id ?? 1) > 0,
              kind == .vlans || (site == nil && group == nil && role == nil && status.isEmpty) else { throw APIError.invalidURL }
        var items: [URLQueryItem] = [.init(name: "limit", value: "50"), .init(name: "ordering", value: kind == .vlans ? "vid,id" : "name,id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(.init(name: "q", value: text)) }
        if !status.isEmpty { items.append(.init(name: "status", value: status)) }
        for (key, value) in [("site_id", site), ("group_id", group), ("tenant_id", tenant), ("role_id", role)] {
            if let value { items.append(.init(name: key, value: value.id == 0 ? "null" : String(value.id))) }
        }
        return items
    }
    func matches(_ record: VLANBrowseRecord) -> Bool {
        if !status.isEmpty, record.status?.value != status { return false }
        for (key, selected, actual) in [("site", site, record.site), ("group", group, record.group), ("tenant", tenant, record.tenant), ("role", role, record.role)] {
            if let selected {
                guard record.knownFields.contains(key), selected.id == 0 ? actual == nil : actual?.id == selected.id else { return false }
            }
        }
        return true
    }
}

struct VLANBrowseService: Sendable {
    let client: APIClient
    let kind: VLANBrowseKind
    var fixedGroup: ReferenceSelection? = nil
    var fixedSite: ReferenceSelection? = nil
    var fixedTenant: ReferenceSelection? = nil
    var fixedRole: ReferenceSelection? = nil
    func effective(_ query: VLANBrowseQuery) -> VLANBrowseQuery {
        var result = query
        if let fixedGroup { result.group = fixedGroup }
        if let fixedSite { result.site = fixedSite }
        if let fixedTenant { result.tenant = fixedTenant }
        if let fixedRole { result.role = fixedRole }
        return result
    }
    func page(query: VLANBrowseQuery, next: String?) async throws -> NetBoxPage<VLANBrowseRecord> {
        guard (fixedGroup?.id ?? 1) > 0, (fixedSite?.id ?? 1) > 0, (fixedTenant?.id ?? 1) > 0, (fixedRole?.id ?? 1) > 0 else { throw APIError.invalidURL }
        let scoped = effective(query)
        let items = try scoped.items(kind: kind)
        try CollectionLinks.validate(next, path: kind.path, required: items.filter { $0.name != "limit" })
        let page: NetBoxPage<VLANBrowseRecord> = try await client.get(next ?? kind.path, query: next == nil ? items : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count else { throw APIError.invalidResponse }
        for row in page.results { try row.validate(kind: kind); guard scoped.matches(row) else { throw APIError.invalidResponse } }
        return page
    }
    func detail(id: Int) async throws -> VLANBrowseRecord {
        guard id > 0 else { throw APIError.invalidURL }
        let row: VLANBrowseRecord = try await client.get(kind.path + "\(id)/")
        try row.validate(kind: kind)
        guard row.id == id else { throw APIError.invalidResponse }
        return row
    }
}
