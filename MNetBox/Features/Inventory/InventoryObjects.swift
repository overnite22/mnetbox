import Foundation

enum InventoryKind: String, CaseIterable, Sendable, Hashable {
    case sites, racks, devices, virtualMachines
    var symbol: String {
        switch self {
        case .sites: "building.2.fill"
        case .racks: "cabinet.fill"
        case .devices: "server.rack"
        case .virtualMachines: "desktopcomputer"
        }
    }
    var title: String {
        switch self {
        case .sites: L10n.text("Sites")
        case .racks: L10n.text("Racks")
        case .devices: L10n.text("Devices")
        case .virtualMachines: L10n.text("Virtual machines")
        }
    }
    var singular: String {
        switch self {
        case .sites: L10n.text("Site")
        case .racks: L10n.text("Rack")
        case .devices: L10n.text("Device")
        case .virtualMachines: L10n.text("Virtual machine")
        }
    }
    var path: String {
        self == .virtualMachines ? "virtualization/virtual-machines/" : "dcim/\(rawValue)/"
    }
    var statuses: [String] {
        switch self {
        case .sites: ["active", "planned", "staging", "decommissioning", "retired"]
        case .racks: ["active", "available", "reserved", "planned", "deprecated"]
        case .devices: ["active", "offline", "planned", "staged", "failed", "inventory", "decommissioning"]
        case .virtualMachines: ["active", "offline", "planned", "staged", "failed", "decommissioning", "paused"]
        }
    }
}

struct InventoryQuery: Equatable, Sendable {
    var search = ""
    var status = ""
    var items: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "ordering", value: "id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(URLQueryItem(name: "q", value: text)) }
        if !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        return items
    }
}

struct InventoryObject: Codable, Sendable, Identifiable {
    let id: Int
    let name: String?
    let display: String?
    let status: NetBoxLabel?
    let tenant: NetBoxLabel?
    let site: NetBoxLabel?
    let location: NetBoxLabel?
    let region: NetBoxLabel?
    let group: NetBoxLabel?
    let role: NetBoxLabel?
    let rack: NetBoxLabel?
    let deviceType: NetBoxLabel?
    let platform: NetBoxLabel?
    let cluster: NetBoxLabel?
    let device: NetBoxLabel?
    let primaryIP4: NetBoxLabel?
    let primaryIP6: NetBoxLabel?
    let face: NetBoxLabel?
    let position: NetBoxQuantity?
    let height: NetBoxQuantity?
    let vcpus: NetBoxQuantity?
    let memory: NetBoxQuantity?
    let disk: NetBoxQuantity?
    let serial: String?
    let assetTag: String?
    let facility: String?
    let physicalAddress: String?
    let timeZone: String?
    let description: String?
    let comments: String?
    let tags: [NetBoxLabel]?

    var title: String {
        if let name, !name.isEmpty { return name }
        if let display, !display.isEmpty { return display }
        return L10n.identifier("Object #%ld", id)
    }
    var subtitle: String { site?.text ?? cluster?.text ?? region?.text ?? "" }
    enum CodingKeys: String, CodingKey {
        case id, name, display, status, tenant, site, location, region, group, role, rack, platform, cluster, device
        case face, position, vcpus, memory, disk, serial, facility, description, comments, tags
        case deviceType = "device_type", primaryIP4 = "primary_ip4", primaryIP6 = "primary_ip6"
        case height = "u_height", assetTag = "asset_tag", physicalAddress = "physical_address", timeZone = "time_zone"
    }
}

struct InventoryService: Sendable {
    let client: APIClient
    let kind: InventoryKind
    var scope: InventoryScope? = nil
    func page(query: InventoryQuery, next: String?) async throws -> NetBoxPage<InventoryObject> {
        if let scope {
            guard scope.id > 0, scope.supports(kind) else { throw APIError.invalidURL }
        }
        let items = query.items + (scope.map { [URLQueryItem(name: $0.key, value: String($0.id))] } ?? [])
        try CollectionLinks.validate(next, path: kind.path, required: items.filter { $0.name != "limit" })
        let page: NetBoxPage<InventoryObject> = try await client.get(next ?? kind.path, query: next == nil ? items : [])
        guard page.count >= 0, page.results.allSatisfy({ $0.id > 0 }) else { throw APIError.invalidResponse }
        if let scope {
            var verified: Set<Int> = []
            for row in page.results {
                guard let relation = scope.relation(row)?.id, relation > 0 else { throw APIError.invalidResponse }
                if let tree = scope.treeKind {
                    if !verified.contains(relation) {
                        guard try await ContextService(client: client, kind: tree).contains(relation, under: scope.id) else { throw APIError.invalidResponse }
                        verified.insert(relation)
                    }
                } else { guard relation == scope.id else { throw APIError.invalidResponse } }
            }
        }
        return page
    }
    func detail(id: Int) async throws -> InventoryObject {
        guard id > 0 else { throw APIError.invalidURL }
        let object: InventoryObject = try await client.get(kind.path + "\(id)/")
        guard object.id == id else { throw APIError.invalidResponse }
        return object
    }
}

struct InventoryScope: Sendable {
    enum Parent: Sendable { case site, rack, tenant, cluster, location, region, siteGroup, rackGroup }
    let parent: Parent
    let id: Int
    let title: String
    var key: String {
        switch parent {
        case .site: "site_id"
        case .rack: "rack_id"
        case .tenant: "tenant_id"
        case .cluster: "cluster_id"
        case .location: "location_id"
        case .region: "region_id"
        case .siteGroup, .rackGroup: "group_id"
        }
    }
    var treeKind: ContextKind? {
        switch parent { case .location: .locations; case .region: .regions; case .siteGroup: .siteGroups; default: nil }
    }
    func relation(_ row: InventoryObject) -> NetBoxLabel? {
        switch parent {
        case .site: row.site
        case .rack: row.rack
        case .tenant: row.tenant
        case .cluster: row.cluster
        case .location: row.location
        case .region: row.region
        case .siteGroup, .rackGroup: row.group
        }
    }
    func supports(_ kind: InventoryKind) -> Bool {
        switch parent {
        case .site: [.racks, .devices].contains(kind)
        case .rack: kind == .devices
        case .tenant: true
        case .cluster: kind == .virtualMachines
        case .location: [.racks, .devices].contains(kind)
        case .region, .siteGroup: kind == .sites
        case .rackGroup: kind == .racks
        }
    }
}
