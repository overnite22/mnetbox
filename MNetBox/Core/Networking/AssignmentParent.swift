import Foundation

// Presence of nullable keys matters: an omitted relation is not proof of no dependency.
struct AssignmentParent: Decodable, Sendable {
    let id: Int
    let primaryIP4: NetBoxLabel?
    let primaryIP6: NetBoxLabel?
    let oobIP: NetBoxLabel?
    let hasOOB: Bool
    enum CodingKeys: String, CodingKey { case id; case primaryIP4 = "primary_ip4", primaryIP6 = "primary_ip6", oobIP = "oob_ip" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard c.contains(.primaryIP4), c.contains(.primaryIP6) else { throw APIError.invalidResponse }
        primaryIP4 = try c.decodeIfPresent(NetBoxLabel.self, forKey: .primaryIP4)
        primaryIP6 = try c.decodeIfPresent(NetBoxLabel.self, forKey: .primaryIP6)
        hasOOB = c.contains(.oobIP)
        oobIP = try c.decodeIfPresent(NetBoxLabel.self, forKey: .oobIP)
    }
    func validate(id expected: Int, physical: Bool) throws {
        guard id == expected, !physical || hasOOB,
              [primaryIP4, primaryIP6, oobIP].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
    }
}
