import Foundation

enum ContextKind: String, CaseIterable, Sendable {
    case vrfs, tenants, roles, clusters, locations, regions, siteGroups, rackGroups, clusterGroups
    var path: String {
        switch self {
        case .vrfs: "ipam/vrfs/"
        case .tenants: "tenancy/tenants/"
        case .roles: "ipam/roles/"
        case .clusters: "virtualization/clusters/"
        case .clusterGroups: "virtualization/cluster-groups/"
        case .locations: "dcim/locations/"
        case .regions: "dcim/regions/"
        case .siteGroups: "dcim/site-groups/"
        case .rackGroups: "dcim/rack-groups/"
        }
    }
    var title: String {
        L10n.text([.vrfs: "VRFs", .tenants: "Tenants", .roles: "IPAM roles", .clusters: "Clusters", .locations: "Locations", .regions: "Regions", .siteGroups: "Site groups", .rackGroups: "Rack groups", .clusterGroups: "Cluster groups"][self] ?? "")
    }
    var symbol: String {
        switch self {
        case .vrfs: "point.3.connected.trianglepath.dotted"
        case .tenants: "person.2.fill"
        case .roles: "tag.fill"
        case .clusters, .clusterGroups: "square.3.layers.3d"
        case .locations: "mappin.and.ellipse"
        case .regions: "globe.europe.africa.fill"
        case .siteGroups, .rackGroups: "folder.fill"
        }
    }
    var hierarchical: Bool { [.locations, .regions, .siteGroups].contains(self) }
    static func scope(_ type: String?) -> ContextKind? {
        switch type {
        case "dcim.region": .regions
        case "dcim.sitegroup": .siteGroups
        case "dcim.location": .locations
        case "dcim.rackgroup": .rackGroups
        case "virtualization.clustergroup": .clusterGroups
        case "virtualization.cluster": .clusters
        default: nil
        }
    }
}

struct ContextRecord: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let display: String?
    let slug: String?
    let weight: Int?
    let prefixCount: Int?
    let ipCount: Int?
    let vlanCount: Int?
    let deviceCount: Int?
    let vmCount: Int?
    let rd: String?
    let enforceUnique: Bool?
    let tenant: NetBoxLabel?
    let group: NetBoxLabel?
    let parent: NetBoxLabel?
    let site: NetBoxLabel?
    let type: NetBoxLabel?
    let status: NetBoxLabel?
    let scopeType: String?
    let scopeID: Int?
    let scope: NetBoxLabel?
    let description: String?
    let comments: String?
    let tags: [NetBoxLabel]?
    let importTargets: [NetBoxLabel]?
    let exportTargets: [NetBoxLabel]?
    let allocatedVCPUs: NetBoxQuantity?
    let allocatedMemory: Int?
    let allocatedDisk: Int?
    var title: String { display ?? name }
    enum CodingKeys: String, CodingKey {
        case slug, weight
        case prefixCount = "prefix_count", ipCount = "ipaddress_count", vlanCount = "vlan_count", deviceCount = "device_count", vmCount = "virtualmachine_count"
        case id, name, display, rd, tenant, group, parent, site, type, status, scope, description, comments, tags
        case enforceUnique = "enforce_unique", scopeType = "scope_type", scopeID = "scope_id"
        case importTargets = "import_targets", exportTargets = "export_targets"
        case allocatedVCPUs = "allocated_vcpus", allocatedMemory = "allocated_memory", allocatedDisk = "allocated_disk"
    }
    func validate() throws {
        guard id > 0, !name.isEmpty,
              [tenant, group, parent, site].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }),
              [allocatedMemory, allocatedDisk].compactMap({ $0 }).allSatisfy({ $0 >= 0 }) else { throw APIError.invalidResponse }
    }
    var scopeText: String { [scope?.text, scopeType, scopeID.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ") }
}

struct ContextQuery: Equatable, Sendable {
    var search = ""
    var items: [URLQueryItem] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return [.init(name: "limit", value: "50"), .init(name: "ordering", value: "name,id")] + (text.isEmpty ? [] : [.init(name: "q", value: text)])
    }
}

struct ContextScope: Sendable {
    enum Relation: Sendable { case site, tenant, clusterGroup }
    let relation: Relation
    let id: Int
    let title: String
    var key: String { relation == .clusterGroup ? "group_id" : relation == .site ? "site_id" : "tenant_id" }
    func supports(_ kind: ContextKind) -> Bool {
        switch relation {
        case .site: kind == .locations
        case .tenant: [.vrfs, .clusters, .locations].contains(kind)
        case .clusterGroup: kind == .clusters
        }
    }
    func matches(_ row: ContextRecord) -> Bool {
        (relation == .site ? row.site : relation == .tenant ? row.tenant : row.group)?.id == id
    }
}

struct ContextService: Sendable {
    let client: APIClient
    let kind: ContextKind
    var scope: ContextScope? = nil
    func page(query: ContextQuery, next: String?) async throws -> NetBoxPage<ContextRecord> {
        if let scope { guard scope.id > 0, scope.supports(kind) else { throw APIError.invalidURL } }
        let items = query.items + (scope.map { [.init(name: $0.key, value: String($0.id))] } ?? [])
        try CollectionLinks.validate(next, path: kind.path, required: items.filter { $0.name != "limit" })
        let page: NetBoxPage<ContextRecord> = try await client.get(next ?? kind.path, query: next == nil ? items : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count else { throw APIError.invalidResponse }
        for row in page.results { try row.validate(); guard scope?.matches(row) ?? true else { throw APIError.invalidResponse } }
        return page
    }
    func detail(id: Int) async throws -> ContextRecord {
        guard id > 0 else { throw APIError.invalidURL }
        let row: ContextRecord = try await client.get(kind.path + "\(id)/")
        try row.validate()
        guard row.id == id else { throw APIError.invalidResponse }
        return row
    }
    // Tree filters include descendants. Resolve their actual ancestry, with bounded
    // GETs and cycle checks, rather than treating every child as a direct match.
    func contains(_ candidate: Int, under root: Int) async throws -> Bool {
        guard kind.hierarchical, candidate > 0, root > 0 else { throw APIError.invalidURL }
        var current = candidate
        var seen: Set<Int> = []
        for _ in 0..<64 {
            if current == root { return true }
            guard seen.insert(current).inserted else { throw APIError.invalidResponse }
            let row = try await detail(id: current)
            guard let parent = row.parent?.id else { return false }
            current = parent
        }
        throw APIError.invalidResponse
    }
}
