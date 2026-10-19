import Foundation

enum IPAMKind: String, Sendable, Hashable {
    case prefixes, ipAddresses
    var title: String { L10n.text(self == .prefixes ? "Prefixes" : "IP addresses") }
    var path: String { self == .prefixes ? "ipam/prefixes/" : "ipam/ip-addresses/" }
    var statuses: [String] {
        self == .prefixes ? ["active", "container", "reserved", "deprecated"]
            : ["active", "reserved", "deprecated", "dhcp", "slaac"]
    }
}

struct IPAMQuery: Equatable, Sendable {
    var search = ""
    var family = ""
    var status = ""
    var ipRole = ""
    var vrf: ReferenceSelection?
    var tenant: ReferenceSelection?
    var role: ReferenceSelection?
    var site: ReferenceSelection?
    func items(for kind: IPAMKind) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50")]
        // NetBox IPAddressManager orders numerically by host (ignoring mask), then ID.
        // An explicit address ordering would replace that host-aware ordering.
        if kind == .prefixes { items.append(URLQueryItem(name: "ordering", value: "prefix,id")) }
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(URLQueryItem(name: "q", value: text)) }
        if !family.isEmpty { items.append(URLQueryItem(name: "family", value: family)) }
        if !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        if !ipRole.isEmpty { items.append(URLQueryItem(name: "role", value: ipRole)) }
        if let vrf { items.append(URLQueryItem(name: "vrf_id", value: vrf.id == 0 ? "null" : String(vrf.id))) }
        if let tenant { items.append(URLQueryItem(name: "tenant_id", value: String(tenant.id))) }
        if let role { items.append(URLQueryItem(name: "role_id", value: String(role.id))) }
        if let site {
            items += [URLQueryItem(name: "scope_type", value: "dcim.site"), URLQueryItem(name: "scope_id", value: String(site.id))]
        }
        return items
    }
}

typealias IPAMLabel = NetBoxLabel

struct IPAMFamily: Codable, Sendable {
    let value: Int
    let label: String?
    var text: String { label ?? "IPv\(value)" }
}

struct IPAMObject: Codable, Sendable, Identifiable {
    let id: Int
    let prefix: String?
    let address: String?
    let family: IPAMFamily?
    let status: IPAMLabel?
    let vrf: IPAMLabel?
    let tenant: IPAMLabel?
    let role: IPAMLabel?
    let vlan: IPAMLabel?
    let scope: IPAMLabel?
    let description: String?
    let comments: String?
    let dnsName: String?
    let assignedObject: IPAMLabel?
    let assignedObjectType: String?
    let assignedObjectID: Int?
    let scopeType: String?
    let tags: [IPAMLabel]?

    var title: String { prefix ?? address ?? "—" }
    enum CodingKeys: String, CodingKey {
        case id, prefix, address, family, status, vrf, tenant, role, vlan, scope, description, comments, tags
        case dnsName = "dns_name", assignedObject = "assigned_object", assignedObjectType = "assigned_object_type"
        case assignedObjectID = "assigned_object_id", scopeType = "scope_type"
    }
}

struct IPAMService: Sendable {
    let client: APIClient
    let kind: IPAMKind
    var context: IPAMContext? = nil

    func page(query: IPAMQuery, next: String?) async throws -> NetBoxPage<IPAMObject> {
        guard (query.tenant?.id ?? 1) > 0, (query.role?.id ?? 1) > 0,
              (query.site?.id ?? 1) > 0, (query.vrf?.id ?? 0) >= 0 else { throw APIError.invalidURL }
        guard kind == .prefixes ? query.ipRole.isEmpty : (query.site == nil && query.role == nil) else { throw APIError.invalidURL }
        var items = query.items(for: kind)
        if let context {
            let scope = try context.items(kind: kind)
            items.removeAll { item in scope.contains { $0.name == item.name } }
            items += scope
        }
        let required = items.filter { $0.name != "limit" }
        try CollectionLinks.validate(next, path: kind.path, required: required)
        if kind == .ipAddresses, let next, URLComponents(string: next)?.queryItems?.contains(where: { $0.name == "ordering" }) == true { throw APIError.invalidURL }
        let page: NetBoxPage<IPAMObject> = try await client.get(next ?? kind.path, query: next == nil ? items : [])
        guard page.count >= 0, page.results.allSatisfy({ valid($0) && (context?.matches($0) ?? true) }) else { throw APIError.invalidResponse }
        return page
    }

    func detail(id: Int) async throws -> IPAMObject {
        guard id > 0 else { throw APIError.invalidURL }
        let object: IPAMObject = try await client.get(kind.path + "\(id)/")
        guard object.id == id, valid(object) else { throw APIError.invalidResponse }
        return object
    }

    private func valid(_ object: IPAMObject) -> Bool {
        let primary = kind == .prefixes ? object.prefix : object.address
        return object.id > 0 && primary?.isEmpty == false
    }
}

enum IPAMContext: Sendable {
    case vrf(id: Int, title: String)
    case tenant(id: Int, title: String)
    case role(id: Int, title: String)
    case scope(type: String, id: Int, title: String)
    case vlan(id: Int, title: String)
    case network(cidr: String, vrfID: Int?, vrfTitle: String)
    case interface(kind: InterfaceKind, id: Int, title: String)
    var title: String {
        switch self {
        case .vrf(_, let title), .tenant(_, let title), .role(_, let title), .scope(_, _, let title), .vlan(_, let title): title
        case .network(let cidr, _, let vrf): "\(cidr) · \(vrf) VRF"
        case .interface(_, _, let title): title
        }
    }
    var locksVRF: Bool { if case .network = self { return true }; if case .vrf = self { return true }; return false }
    func matches(_ object: IPAMObject) -> Bool {
        switch self {
        case .vrf(let id, _): return object.vrf?.id == id
        case .tenant(let id, _): return object.tenant?.id == id
        case .role(let id, _): return object.role?.id == id
        case .scope(let type, let id, _): return object.scopeType == type && object.scope?.id == id
        case .vlan(let id, _): return object.vlan?.id == id
        case .network(_, let vrfID, _):
            return vrfID == nil ? object.vrf == nil : object.vrf?.id == vrfID
        case .interface(let kind, let id, _):
            return object.assignedObjectType == kind.rawValue && object.assignedObjectID == id
        }
    }
    func items(kind: IPAMKind) throws -> [URLQueryItem] {
        switch self {
        case .vrf(let id, _), .tenant(let id, _), .role(let id, _):
            guard id > 0 else { throw APIError.invalidURL }
            let key: String
            switch self { case .vrf: key = "vrf_id"; case .tenant: key = "tenant_id"; default: key = "role_id"; guard kind == .prefixes else { throw APIError.invalidURL } }
            return [.init(name: key, value: String(id))]
        case .scope(let type, let id, _):
            guard kind == .prefixes, id > 0, ["dcim.region", "dcim.sitegroup", "dcim.site", "dcim.location"].contains(type) else { throw APIError.invalidURL }
            return [.init(name: "scope_type", value: type), .init(name: "scope_id", value: String(id))]
        case .vlan(let id, _):
            guard kind == .prefixes, id > 0 else { throw APIError.invalidURL }
            return [URLQueryItem(name: "vlan_id", value: String(id))]
        case .network(let cidr, let vrfID, _):
            guard !cidr.isEmpty, cidr.contains("/"), vrfID == nil || (vrfID ?? 0) > 0 else { throw APIError.invalidURL }
            return [URLQueryItem(name: kind == .prefixes ? "within" : "parent", value: cidr),
                    URLQueryItem(name: "vrf_id", value: vrfID.map(String.init) ?? "null")]
        case .interface(let interface, let id, _):
            guard kind == .ipAddresses, id > 0 else { throw APIError.invalidURL }
            return [URLQueryItem(name: interface.ipFilter, value: String(id))]
        }
    }
}

extension IPAMObject {
    var networkContext: IPAMContext? {
        guard let prefix, vrf == nil || (vrf?.id ?? 0) > 0 else { return nil }
        return .network(cidr: prefix, vrfID: vrf?.id, vrfTitle: vrf?.text ?? L10n.text("Global"))
    }
    var interfaceAssignment: (InterfaceKind, Int)? {
        guard let type = assignedObjectType, let kind = InterfaceKind(rawValue: type),
              let id = assignedObjectID, id > 0, let nestedID = assignedObject?.id, nestedID == id else { return nil }
        return (kind, id)
    }
}
