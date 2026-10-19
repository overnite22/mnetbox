import Foundation

enum VLANMode: String, CaseIterable, Sendable {
    case routed = "", access, tagged
    case taggedAll = "tagged-all"
    var title: String {
        L10n.text(self == .routed ? "Routed (no VLANs)" : self == .access ? "Access" : self == .tagged ? "Tagged" : "Tagged all")
    }
}

struct VLANPlan: Encodable, Equatable, Sendable {
    var mode: String
    var untagged: ReferenceSelection?
    var tagged: [ReferenceSelection]
    enum CodingKeys: String, CodingKey { case mode; case untagged = "untagged_vlan", tagged = "tagged_vlans" }
    func validate() throws {
        guard let choice = VLANMode(rawValue: mode), untagged.map({ $0.id > 0 }) ?? true,
              tagged.allSatisfy({ $0.id > 0 }), Set(tagged.map(\.id)).count == tagged.count,
              !tagged.contains(where: { $0.id == untagged?.id }),
              choice != .routed || (untagged == nil && tagged.isEmpty),
              choice == .tagged || tagged.isEmpty else { throw APIError.invalidVLANConfiguration }
    }
    func matches(_ other: VLANPlan) -> Bool {
        mode == other.mode && untagged?.id == other.untagged?.id && Set(tagged.map(\.id)) == Set(other.tagged.map(\.id))
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        if let untagged { try c.encode(untagged.id, forKey: .untagged) } else { try c.encodeNil(forKey: .untagged) }
        try c.encode(tagged.map(\.id).sorted(), forKey: .tagged)
    }
}

struct VLANInterface: Decodable, Sendable {
    let id: Int
    let name: String
    let device: NetBoxLabel?
    let virtualMachine: NetBoxLabel?
    let plan: VLANPlan
    let qinq: NetBoxLabel?
    let translation: NetBoxLabel?
    enum CodingKeys: String, CodingKey {
        case id, name, device, mode
        case virtualMachine = "virtual_machine", untagged = "untagged_vlan", tagged = "tagged_vlans"
        case qinq = "qinq_svlan", translation = "vlan_translation_policy"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        device = try c.decodeIfPresent(NetBoxLabel.self, forKey: .device)
        virtualMachine = try c.decodeIfPresent(NetBoxLabel.self, forKey: .virtualMachine)
        guard [.mode, .untagged, .tagged, .qinq, .translation].allSatisfy({ c.contains($0) }) else { throw APIError.invalidResponse }
        struct Choice: Decodable { let value: String }
        let mode: String
        if try c.decodeNil(forKey: .mode) { mode = "" }
        else if let choice = try? c.decode(Choice.self, forKey: .mode) { mode = choice.value }
        else { mode = try c.decode(String.self, forKey: .mode) }
        let untagged = try c.decodeIfPresent(NetBoxLabel.self, forKey: .untagged)
        let tagged = try c.decode([NetBoxLabel].self, forKey: .tagged)
        guard untagged.map({ ($0.id ?? 0) > 0 }) ?? true, tagged.allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
        plan = VLANPlan(mode: mode, untagged: untagged.map { ReferenceSelection(id: $0.id ?? 0, title: $0.text) },
                        tagged: tagged.map { ReferenceSelection(id: $0.id ?? 0, title: $0.text) })
        qinq = try c.decodeIfPresent(NetBoxLabel.self, forKey: .qinq)
        translation = try c.decodeIfPresent(NetBoxLabel.self, forKey: .translation)
    }
    func validate(target: StructuredEditTarget) throws {
        guard target.collection.isInterface, id == target.id, !name.isEmpty,
              (target.collection == .physicalInterfaces ? device?.id : virtualMachine?.id) == target.parentID else { throw APIError.invalidResponse }
        guard VLANMode(rawValue: plan.mode) != nil, qinq == nil, translation == nil else { throw APIError.unsupportedVLANConfiguration }
        try plan.validate()
    }
}
struct VLANSnapshot: Sendable {
    let target: StructuredEditTarget
    let object: VLANInterface
    let etag: String
    let siteID: Int?
}

struct VLANParent: Decodable, Sendable {
    let id: Int
    let site: NetBoxLabel?
    enum CodingKeys: String, CodingKey { case id, site }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard c.contains(.site) else { throw APIError.invalidResponse }
        site = try c.decodeIfPresent(NetBoxLabel.self, forKey: .site)
        guard site.map({ ($0.id ?? 0) > 0 }) ?? true else { throw APIError.invalidResponse }
    }
}

struct VLANReference: Codable, Sendable, Identifiable {
    let id: Int
    let vid: Int
    let name: String
    let site: NetBoxLabel?
    enum CodingKeys: String, CodingKey { case id, vid, name, site }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); vid = try c.decode(Int.self, forKey: .vid)
        name = try c.decode(String.self, forKey: .name)
        guard c.contains(.site), id > 0, (1...4094).contains(vid), !name.isEmpty else { throw APIError.invalidResponse }
        site = try c.decodeIfPresent(NetBoxLabel.self, forKey: .site)
        guard site.map({ ($0.id ?? 0) > 0 }) ?? true else { throw APIError.invalidResponse }
    }
    var title: String { "\(vid) · \(name)" }
}
