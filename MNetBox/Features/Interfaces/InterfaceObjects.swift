import Foundation

enum InterfaceKind: String, Sendable {
    case physical = "dcim.interface", virtual = "virtualization.vminterface"
    var path: String { self == .physical ? "dcim/interfaces/" : "virtualization/interfaces/" }
    var parentKind: InventoryKind { self == .physical ? .devices : .virtualMachines }
    var parentFilter: String { self == .physical ? "device_id" : "virtual_machine_id" }
    var ipFilter: String { self == .physical ? "interface_id" : "vminterface_id" }
}

struct InterfaceQuery: Equatable, Sendable {
    var search = ""
    var enabled = ""
    var items: [URLQueryItem] {
        var result = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "ordering", value: "id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { result.append(URLQueryItem(name: "q", value: text)) }
        if !enabled.isEmpty { result.append(URLQueryItem(name: "enabled", value: enabled)) }
        return result
    }
}

struct InterfaceObject: Codable, Sendable, Identifiable {
    let id: Int
    let name: String
    let display: String?
    let type: NetBoxLabel?
    let enabled: Bool?
    let device: NetBoxLabel?
    let virtualMachine: NetBoxLabel?
    let mtu: Int?
    let speed: Int?
    let description: String?
    let macAddress: String?
    let primaryMACAddress: NetBoxLabel?
    let macAddresses: [NetBoxLabel]?
    let mode: NetBoxLabel?
    let qinqSVLAN: NetBoxLabel?
    let untaggedVLAN: NetBoxLabel?
    let taggedVLANs: [NetBoxLabel]?
    let cable: NetBoxLabel?
    let linkPeers: [InterfacePeer]?
    let linkPeersType: String?
    let connectedEndpoints: [InterfacePeer]?
    let connectedEndpointsType: String?
    let connectedEndpointsReachable: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, display, type, enabled, device, mtu, speed, description, mode, cable
        case virtualMachine = "virtual_machine", macAddress = "mac_address", primaryMACAddress = "primary_mac_address"
        case qinqSVLAN = "qinq_svlan"
        case macAddresses = "mac_addresses", untaggedVLAN = "untagged_vlan", taggedVLANs = "tagged_vlans"
        case linkPeers = "link_peers", linkPeersType = "link_peers_type", connectedEndpoints = "connected_endpoints"
        case connectedEndpointsType = "connected_endpoints_type", connectedEndpointsReachable = "connected_endpoints_reachable"
    }
}

struct InterfacePeer: Codable, Sendable, Identifiable {
    let id: Int
    let display: String?
    let name: String?
    let device: NetBoxLabel?
    let virtualMachine: NetBoxLabel?
    var title: String { display ?? name ?? L10n.format("Endpoint #%ld", id) }
    enum CodingKeys: String, CodingKey { case id, display, name, device; case virtualMachine = "virtual_machine" }
}

struct InterfaceService: Sendable {
    let client: APIClient
    let kind: InterfaceKind
    var parentID: Int? = nil
    var vlanID: Int? = nil
    func page(query: InterfaceQuery, next: String?) async throws -> NetBoxPage<InterfaceObject> {
        guard (parentID ?? 1) > 0, (vlanID ?? 1) > 0, parentID != nil || vlanID != nil else { throw APIError.invalidURL }
        var required: [URLQueryItem] = []
        if let parentID { required.append(URLQueryItem(name: kind.parentFilter, value: String(parentID))) }
        if let vlanID { required.append(URLQueryItem(name: "vlan_id", value: String(vlanID))) }
        try CollectionLinks.validate(next, path: kind.path, required: required + query.items.filter { $0.name != "limit" && (vlanID != nil || $0.name != "ordering") })
        let page: NetBoxPage<InterfaceObject> = try await client.get(next ?? kind.path, query: next == nil ? query.items + required : [])
        guard page.count >= 0, page.results.allSatisfy({ $0.id > 0 && !$0.name.isEmpty && (parent($0)?.id ?? 0) > 0 && (parentID == nil || parent($0)?.id == parentID) && (vlanID == nil || $0.untaggedVLAN?.id == vlanID || $0.taggedVLANs?.contains(where: { $0.id == vlanID }) == true || $0.qinqSVLAN?.id == vlanID) }) else { throw APIError.invalidResponse }
        return page
    }
    func detail(id: Int) async throws -> InterfaceObject {
        guard id > 0 else { throw APIError.invalidURL }
        let object: InterfaceObject = try await client.get(kind.path + "\(id)/")
        guard object.id == id, !object.name.isEmpty else { throw APIError.invalidResponse }
        if let parentID, parent(object)?.id != parentID { throw APIError.invalidReference }
        return object
    }
    func parent(_ object: InterfaceObject) -> NetBoxLabel? { kind == .physical ? object.device : object.virtualMachine }
}

struct CableTermination: Codable, Sendable {
    let objectType: String
    let objectID: Int
    let object: InterfacePeer?
    enum CodingKeys: String, CodingKey { case objectType = "object_type", objectID = "object_id", object }
}
struct CableObject: Codable, Sendable, Identifiable {
    let id: Int
    let display: String?
    let label: String?
    let type: String?
    let status: VLANBrowseChoice?
    let length: NetBoxQuantity?
    let lengthUnit: NetBoxLabel?
    let description: String?
    let color: String?
    let comments: String?
    let tenant: NetBoxLabel?
    let bundle: NetBoxLabel?
    let aTerminations: [CableTermination]?
    let bTerminations: [CableTermination]?
    var statusValue: String? { status?.value }
    enum CodingKeys: String, CodingKey {
        case id, display, label, type, status, length, description, color, comments, tenant, bundle
        case lengthUnit = "length_unit", aTerminations = "a_terminations", bTerminations = "b_terminations"
    }
}


extension InterfaceObject {
    var relatedVLANs: [NetBoxLabel] {
        var seen: Set<Int> = []
        return ([untaggedVLAN, qinqSVLAN].compactMap { $0 } + (taggedVLANs ?? [])).filter {
            guard let id = $0.id, id > 0 else { return false }
            return seen.insert(id).inserted
        }
    }
}
