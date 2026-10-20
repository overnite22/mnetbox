import Foundation

struct IPRangeObject: Codable, Sendable, Identifiable {
    let id: Int
    let startAddress: String
    let endAddress: String
    let family: IPAMFamily
    let vrf: NetBoxLabel?
    let tenant: NetBoxLabel?
    let role: NetBoxLabel?
    let status: NetBoxLabel?
    let description: String?
    let comments: String?
    let tags: [NetBoxLabel]?
    let markPopulated: Bool?
    let markUtilized: Bool?
    enum CodingKeys: String, CodingKey {
        case id, family, vrf, tenant, role, status, description, comments, tags
        case startAddress = "start_address", endAddress = "end_address"
        case markPopulated = "mark_populated", markUtilized = "mark_utilized"
    }
    var title: String { startAddress + " – " + endAddress }
    func validate() throws {
        let start = try IPAMCIDR(startAddress, network: false)
        let end = try IPAMCIDR(endAddress, network: false)
        guard id > 0, start.family == end.family, start.family == family.value,
              start.bytes == end.bytes || start.bytes.lexicographicallyPrecedes(end.bytes),
              [vrf, tenant, role].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
    }
}

struct IPRangeQuery: Equatable, Sendable {
    var search = ""
    var family = ""
    var vrf: ReferenceSelection?
    var tenant: ReferenceSelection?
    var items: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50"), .init(name: "ordering", value: "start_address,id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(.init(name: "q", value: text)) }
        if !family.isEmpty { items.append(.init(name: "family", value: family)) }
        if let vrf { items.append(.init(name: "vrf_id", value: vrf.id == 0 ? "null" : String(vrf.id))) }
        if let tenant { items.append(.init(name: "tenant_id", value: String(tenant.id))) }
        return items
    }
    func validate() throws {
        guard ["", "4", "6"].contains(family), (vrf?.id ?? 0) >= 0, (tenant?.id ?? 1) > 0 else { throw APIError.invalidURL }
    }
    func matches(_ object: IPRangeObject) -> Bool {
        (family.isEmpty || String(object.family.value) == family) &&
        (vrf == nil || (vrf?.id == 0 ? object.vrf == nil : object.vrf?.id == vrf?.id)) &&
        (tenant == nil || object.tenant?.id == tenant?.id)
    }
}

struct IPRangeService: Sendable {
    let client: APIClient
    static let path = "ipam/ip-ranges/"
    func page(query: IPRangeQuery, next: String?) async throws -> NetBoxPage<IPRangeObject> {
        try query.validate()
        try CollectionLinks.validate(next, path: Self.path, required: query.items)
        let page: NetBoxPage<IPRangeObject> = try await client.get(next ?? Self.path, query: next == nil ? query.items : [])
        guard page.count >= page.results.count, page.results.count <= 50,
              Set(page.results.map(\.id)).count == page.results.count else { throw APIError.invalidResponse }
        for object in page.results {
            try object.validate()
            guard query.matches(object) else { throw APIError.invalidResponse }
        }
        return page
    }
    func detail(id: Int) async throws -> IPRangeObject {
        guard id > 0 else { throw APIError.invalidURL }
        let object: IPRangeObject = try await client.get(Self.path + "\(id)/")
        try object.validate()
        guard object.id == id else { throw APIError.invalidResponse }
        return object
    }
}
