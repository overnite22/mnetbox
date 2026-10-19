import Foundation

struct DeletionTarget: Sendable, Equatable {
    enum Collection: String, Sendable, CaseIterable {
        case vlans = "ipam/vlans/", vlanGroups = "ipam/vlan-groups/", macAddresses = "dcim/mac-addresses/"
        case prefixes = "ipam/prefixes/", ipAddresses = "ipam/ip-addresses/"
        case vrfs = "ipam/vrfs/", ipamRoles = "ipam/roles/"
        case imageAttachments = "extras/image-attachments/"
        case physicalInterfaces = "dcim/interfaces/", virtualInterfaces = "virtualization/interfaces/"
        case cables = "dcim/cables/"
        var interfaceKind: InterfaceKind? {
            switch self { case .physicalInterfaces: .physical; case .virtualInterfaces: .virtual; default: nil }
        }
        var titleKey: String {
            switch self {
            case .vrfs: "VRF"
            case .ipamRoles: "IPAM role"
            case .imageAttachments: "Image attachment"
            case .vlanGroups: "VLAN group"
            case .vlans: "VLAN"
            case .macAddresses: "MAC address"
            case .prefixes: "Prefix"
            case .ipAddresses: "IP address"
            case .physicalInterfaces: "Physical interface"
            case .virtualInterfaces: "VM interface"
            case .cables: "Cable"
            }
        }
    }
    let collection: Collection
    let id: Int
    var parentID: Int? = nil
    var imageParent: ImageUploadTarget? = nil
    var path: String { get throws {
        guard id > 0, collection.interfaceKind == nil || (parentID ?? 0) > 0 else { throw APIError.invalidURL }
        if collection == .imageAttachments { guard let imageParent else { throw APIError.invalidReference }; try imageParent.validate() }
        else if imageParent != nil { throw APIError.invalidReference }
        return collection.rawValue + "\(id)/"
    } }
}

// A full fresh response is required: absent dependency fields are never interpreted as empty.
struct DeletionObject: Decodable, Sendable {
    let id: Int
    let collection: DeletionTarget.Collection
    let title: String
    let vrf: NetBoxLabel?
    let parent: NetBoxLabel?
    let cidr: IPAMCIDR?
    let blockers: [String]
    private(set) var groupMetadata: Data? = nil
    private(set) var groupVLANCount: Int? = nil
    private(set) var imageTarget: ImageUploadTarget? = nil
    /// Reviewed cable ends, one line per termination ("A · Device · Port").
    private(set) var cableEnds: [String] = []
    private enum Keys: String, CodingKey {
        case rd, weight
        case image, objectType = "object_type", objectID = "object_id"
        case vid, site, group, isPrimary = "is_primary", prefixCount = "prefix_count", qinqRole = "qinq_role"
        case id, prefix, address, vrf, name, device, children, parent, bridge, lag, module, cable
        case vm = "virtual_machine", assignedType = "assigned_object_type", assignedID = "assigned_object_id", assigned = "assigned_object"
        case natInside = "nat_inside", natOutside = "nat_outside", mac = "mac_address", primaryMAC = "primary_mac_address", macs = "mac_addresses"
        case ipCount = "count_ipaddresses", fhrpCount = "count_fhrp_groups", vlan = "untagged_vlan", vlans = "tagged_vlans", qinq = "qinq_svlan"
        case translation = "vlan_translation_policy", vpn = "l2vpn_termination"
        case wireless = "wireless_link", wlans = "wireless_lans", peers = "link_peers", endpoints = "connected_endpoints", bridgeMembers = "bridge_interfaces"
        case occupied = "_occupied", markConnected = "mark_connected", vlanCount = "vlan_count"
        case aTerminations = "a_terminations", bTerminations = "b_terminations"
    }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        id = try fields.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.invalidResponse }
        var reasons: [String] = []
        func require(_ keys: [Keys]) throws {
            guard keys.allSatisfy(fields.contains) else { throw APIError.invalidResponse }
        }
        func reference(_ key: Keys, reason: String) throws {
            if let value = try fields.decodeIfPresent(NetBoxLabel.self, forKey: key) {
                guard (value.id ?? 0) > 0 else { throw APIError.invalidResponse }
                reasons.append(reason)
            }
        }
        func references(_ key: Keys, reason: String) throws {
            let values = try fields.decodeIfPresent([NetBoxLabel].self, forKey: key) ?? []
            guard values.allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
            if !values.isEmpty { reasons.append(reason) }
        }
        if fields.contains(.rd) || fields.contains(.weight) {
            let kind: ContextKind = fields.contains(.rd) ? .vrfs : .roles
            let record = try ContextAdminRecord(from: decoder); try record.validate(kind, id: id)
            collection = kind == .vrfs ? .vrfs : .ipamRoles
            title = record.row.title; vrf = nil; parent = nil; cidr = nil
            var required = ["prefix_count", kind == .vrfs ? "ipaddress_count" : "vlan_count"]
            if kind == .roles { required.append("asn_count") }
            var signature = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record.row)) as? [String: Any] ?? [:]
            let raw = try decoder.container(keyedBy: ContextCountKey.self)
            for key in required {
                let count = try raw.decode(Int.self, forKey: ContextCountKey(stringValue: key))
                guard count >= 0 else { throw APIError.invalidResponse }
                signature[key] = count
                if count > 0 { reasons.append(["prefix_count": "ipam/prefixes/", "ipaddress_count": "ipam/ip-addresses/", "vlan_count": "ipam/vlans/", "asn_count": "ipam/asns/"][key] ?? key) }
            }
            groupMetadata = try JSONSerialization.data(withJSONObject: signature, options: [.sortedKeys])
            if kind == .vrfs, !(record.row.importTargets ?? []).isEmpty || !(record.row.exportTargets ?? []).isEmpty { reasons.append("Route targets") }
        } else if fields.contains(.image) {
            let reply = try ImageUploadReply(from: decoder), a = reply.attachment
            guard let kind = InventoryKind.allCases.first(where: { ImageUploadTarget(kind: $0, id: a.objectID).objectType == a.objectType }),
                  a.objectID > 0, a.parent?.id == a.objectID, !a.image.isEmpty, reply.width > 0, reply.height > 0 else { throw APIError.invalidResponse }
            imageTarget = .init(kind: kind, id: a.objectID)
            collection = .imageAttachments; title = a.name.isEmpty ? "#\(id)" : a.name
            cidr = nil; vrf = nil; parent = a.parent
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            groupMetadata = try encoder.encode([a.objectType, String(a.objectID), a.name, a.image, a.imageSize.map(String.init) ?? "null", reply.description, String(reply.width), String(reply.height)])
        } else if fields.contains(.address) || fields.contains(.prefix) {
            try require([.vrf])
            vrf = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .vrf)
            if let vrf, (vrf.id ?? 0) <= 0 { throw APIError.invalidResponse }
            parent = nil
            let prefix = fields.contains(.prefix)
            collection = prefix ? .prefixes : .ipAddresses
            title = try fields.decode(String.self, forKey: prefix ? .prefix : .address)
            cidr = try IPAMCIDR(title, network: prefix)
            if prefix {
                let children = try fields.decode(Int.self, forKey: .children)
                guard children >= 0 else { throw APIError.invalidResponse }
                if children > 0 { reasons.append("Contained prefixes") }
            } else {
                try require([.assignedType, .assignedID, .assigned, .natInside, .natOutside])
                let type = try fields.decodeIfPresent(String.self, forKey: .assignedType)
                let identifier = try fields.decodeIfPresent(Int.self, forKey: .assignedID)
                let assignment = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .assigned)
                if type != nil || identifier != nil || assignment != nil { reasons.append("Interface or object assignment") }
                try reference(.natInside, reason: "NAT relationship")
                try references(.natOutside, reason: "NAT relationship")
            }
        } else if fields.contains(.vlanCount) {
            let group = try VLANAdminRecord(from: decoder)
            try group.validate(kind: .groups, id: id)
            collection = .vlanGroups; cidr = nil; vrf = nil; parent = nil
            title = "\(group.row.name) · \(group.row.slug ?? "") · \(group.row.scopeText.isEmpty ? L10n.text("Global") : group.row.scopeText)"
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            groupMetadata = try encoder.encode(group.row)
            groupVLANCount = group.row.vlanCount
            if (group.row.vlanCount ?? 0) > 0 { reasons.append("VLANs") }
        } else if fields.contains(.vid) {
            collection = .vlans; cidr = nil; vrf = nil; parent = nil
            try require([.vid, .name, .site, .group, .prefixCount, .qinqRole, .qinq, .vpn])
            let vid = try fields.decode(Int.self, forKey: .vid)
            let name = try fields.decode(String.self, forKey: .name)
            let site = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .site)
            let group = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .group)
            guard (1...4094).contains(vid), !name.isEmpty, [site, group].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
            title = "\(vid) · \(name) · Site \(site?.id.map(String.init) ?? "—") · Group \(group?.id.map(String.init) ?? "—")"
            let count = try fields.decode(Int.self, forKey: .prefixCount)
            guard count >= 0 else { throw APIError.invalidResponse }
            if count > 0 { reasons.append("Prefixes") }
            let role = try fields.decodeIfPresent(VLANBrowseChoice.self, forKey: .qinqRole)
            if role != nil { reasons.append("QinQ relationship") }
            try reference(.qinq, reason: "QinQ relationship")
            try reference(.vpn, reason: "L2VPN relationship")
        } else if fields.contains(.isPrimary) && fields.contains(.mac) {
            try require([.mac, .isPrimary, .assignedType, .assignedID, .assigned])
            let mac = try MACRecord(from: decoder)
            collection = .macAddresses; cidr = nil; vrf = nil; parent = nil
            title = "\(mac.macAddress) (#\(mac.id))"
            if mac.isPrimary { reasons.append("Primary MAC") }
            if mac.assignedObjectType != nil { reasons.append("Interface or object assignment") }
        } else if fields.contains(.aTerminations) || fields.contains(.bTerminations) {
            // Deleting a cable removes only the cable record; endpoints are left untouched by NetBox.
            let cable = try CableObject(from: decoder)
            try cable.validate()
            collection = .cables; cidr = nil; vrf = nil; parent = nil
            title = cable.title
            let a = cable.aTerminations ?? [], b = cable.bTerminations ?? []
            var lines: [String] = []
            // Bind the reviewed identity and terminations, so any change since review is a conflict.
            var signature: [String] = [cable.label ?? "", cable.type ?? "", cable.statusValue ?? "", cable.color ?? ""]
            for (side, values) in [("A", a), ("B", b)] {
                signature.append(side)
                signature += values.map { (value: CableTermination) -> String in "\(value.objectType)#\(value.objectID)" }.sorted()
                for value in values {
                    var parts: [String] = [side]
                    if let owner = value.object?.device?.text ?? value.object?.virtualMachine?.text { parts.append(owner) }
                    parts.append(value.object?.title ?? "\(value.objectType) #\(value.objectID)")
                    lines.append(parts.joined(separator: " · "))
                }
            }
            cableEnds = lines
            groupMetadata = try JSONEncoder().encode(signature)
        } else {
            cidr = nil
            try require([.parent, .bridge, .mac, .primaryMAC, .macs, .ipCount, .fhrpCount, .vlan, .vlans, .qinq, .translation, .vpn, .vrf])
            title = try fields.decode(String.self, forKey: .name)
            guard !title.isEmpty else { throw APIError.invalidResponse }
            let physical = fields.contains(.device)
            collection = physical ? .physicalInterfaces : .virtualInterfaces
            parent = try fields.decode(NetBoxLabel.self, forKey: physical ? .device : .vm)
            guard (parent?.id ?? 0) > 0 else { throw APIError.invalidResponse }
            vrf = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .vrf)
            for (key, reason) in [(Keys.parent, "Parent interface"), (.bridge, "Bridge"), (.primaryMAC, "MAC addresses"), (.vlan, "VLAN configuration"), (.qinq, "VLAN configuration"), (.translation, "VLAN configuration"), (.vpn, "L2VPN termination"), (.vrf, "VRF configuration")] {
                try reference(key, reason: reason)
            }
            try references(.macs, reason: "MAC addresses")
            try references(.vlans, reason: "VLAN configuration")
            if let mac = try fields.decodeIfPresent(String.self, forKey: .mac), !mac.isEmpty { reasons.append("MAC addresses") }
            for (key, reason) in [(Keys.ipCount, "Assigned IP addresses"), (.fhrpCount, "FHRP groups")] {
                let count = try fields.decode(Int.self, forKey: key)
                guard count >= 0 else { throw APIError.invalidResponse }
                if count > 0 { reasons.append(reason) }
            }
            if physical {
                try require([.cable, .lag, .module, .wireless, .wlans, .peers, .endpoints, .bridgeMembers, .occupied, .markConnected])
                for (key, reason) in [(Keys.cable, "Cable"), (.lag, "Link aggregation"), (.module, "Module"), (.wireless, "Wireless link")] { try reference(key, reason: reason) }
                for (key, reason) in [(Keys.wlans, "Wireless networks"), (.peers, "Connected endpoints"), (.endpoints, "Connected endpoints"), (.bridgeMembers, "Bridge members")] { try references(key, reason: reason) }
                if try fields.decode(Bool.self, forKey: .occupied) || fields.decode(Bool.self, forKey: .markConnected) { reasons.append("Occupied interface") }
            }
        }
        blockers = Array(Set(reasons)).sorted()
    }
    func validate(_ target: DeletionTarget) throws {
        _ = try target.path
        guard id == target.id, collection == target.collection else { throw APIError.invalidResponse }
        if target.collection == .imageAttachments {
            guard imageTarget == target.imageParent, parent?.id == target.imageParent?.id, cidr == nil else { throw APIError.invalidResponse }
        } else if let _ = target.collection.interfaceKind {
            guard cidr == nil, parent?.id == target.parentID else { throw APIError.invalidResponse }
        } else {
            let addressed: Set<DeletionTarget.Collection> = [.prefixes, .ipAddresses]
            guard (addressed.contains(target.collection) ? cidr != nil : cidr == nil), parent == nil else { throw APIError.invalidResponse }
        }
    }
}
struct DeletionSnapshot: Sendable {
    let target: DeletionTarget
    let object: DeletionObject
    let etag: String
    let blockers: [String]
    var imageParentTitle: String? = nil
}
struct DeletionPrimaryObject: Codable, Sendable {
    let id: Int
    let primaryIP4: NetBoxLabel?
    let primaryIP6: NetBoxLabel?
    enum CodingKeys: String, CodingKey { case id; case primaryIP4 = "primary_ip4", primaryIP6 = "primary_ip6" }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard fields.contains(.primaryIP4), fields.contains(.primaryIP6) else { throw APIError.invalidResponse }
        id = try fields.decode(Int.self, forKey: .id)
        primaryIP4 = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .primaryIP4)
        primaryIP6 = try fields.decodeIfPresent(NetBoxLabel.self, forKey: .primaryIP6)
        guard id > 0 else { throw APIError.invalidResponse }
    }
}
struct DeletionDependencyPage: Decodable, Sendable {
    let count: Int
    let next: String?
    let results: [Row]
    struct Row: Decodable, Sendable { let id: Int }
    func validate() throws {
        guard count >= 0, results.count <= 1, results.allSatisfy({ $0.id > 0 }),
              (count == 0 ? results.isEmpty && next == nil : !results.isEmpty) else { throw APIError.invalidResponse }
    }
}

struct ContextDeletionDependency: Codable, Sendable {
    let id: Int; let vrf: NetBoxLabel?; let role: NetBoxLabel?; let fields: Set<String>
    enum CodingKeys: String, CodingKey { case id, vrf, role }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); vrf = try c.decodeIfPresent(NetBoxLabel.self, forKey: .vrf); role = try c.decodeIfPresent(NetBoxLabel.self, forKey: .role)
        fields = Set(c.allKeys.map(\.stringValue))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(id, forKey: .id)
        if fields.contains("vrf") { try c.encode(vrf, forKey: .vrf) }; if fields.contains("role") { try c.encode(role, forKey: .role) }
    }
}

private struct ContextCountKey: CodingKey {
    let stringValue: String; var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
