import Foundation

struct MACRecord: Codable, Sendable, Identifiable {
    let id: Int
    let macAddress: String
    let assignedObjectType: String?
    let assignedObjectID: Int?
    let assignedObject: NetBoxLabel?
    let isPrimary: Bool
    let description: String
    let comments: String
    enum CodingKeys: String, CodingKey { case id, description, comments; case macAddress = "mac_address", assignedObjectType = "assigned_object_type", assignedObjectID = "assigned_object_id", assignedObject = "assigned_object", isPrimary = "is_primary" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); macAddress = try c.decode(String.self, forKey: .macAddress)
        guard c.contains(.assignedObjectType), c.contains(.assignedObjectID) else { throw APIError.invalidResponse }
        assignedObjectType = try c.decodeIfPresent(String.self, forKey: .assignedObjectType)
        assignedObjectID = try c.decodeIfPresent(Int.self, forKey: .assignedObjectID)
        assignedObject = try c.decodeIfPresent(NetBoxLabel.self, forKey: .assignedObject)
        isPrimary = try c.decode(Bool.self, forKey: .isPrimary)
        description = try c.decode(String.self, forKey: .description); comments = try c.decode(String.self, forKey: .comments)
        guard id > 0, (try? MACValue(macAddress)) != nil,
              (assignedObjectType == nil && assignedObjectID == nil && assignedObject == nil && !isPrimary)
                || (assignedObjectType?.isEmpty == false && (assignedObjectID ?? 0) > 0 && (assignedObject == nil || assignedObject?.id == assignedObjectID)) else { throw APIError.invalidResponse }
    }
    var assignment: (InterfaceKind, Int)? {
        guard let type = assignedObjectType, let kind = InterfaceKind(rawValue: type), let id = assignedObjectID, id > 0 else { return nil }
        return (kind, id)
    }
}
struct MACService: Sendable {
    let client: APIClient
    var interface: InterfaceSelection? = nil
    func page(search: String, next: String?) async throws -> NetBoxPage<MACRecord> {
        var query = [URLQueryItem(name: "ordering", value: "mac_address,id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { query.append(.init(name: "q", value: text)) }
        if let interface {
            guard interface.id > 0 else { throw APIError.invalidReference }
            query.append(.init(name: interface.kind.ipFilter, value: String(interface.id)))
        }
        try CollectionLinks.validate(next, path: "dcim/mac-addresses/", required: query)
        let page: NetBoxPage<MACRecord> = try await client.get(next ?? "dcim/mac-addresses/", query: next == nil ? query + [.init(name: "limit", value: "50")] : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count,
              page.results.allSatisfy({ interface == nil || ($0.assignment?.0 == interface?.kind && $0.assignment?.1 == interface?.id) }) else { throw APIError.invalidResponse }
        return page
    }
    func detail(id: Int) async throws -> MACRecord {
        guard id > 0 else { throw APIError.invalidURL }
        let row: MACRecord = try await client.get("dcim/mac-addresses/\(id)/")
        guard row.id == id else { throw APIError.invalidResponse }
        return row
    }
}
