import Foundation

enum CableCreationError: Error, LocalizedError {
    case occupied, unsupported, sameEndpoint, changed
    var errorDescription: String? {
        let text = switch self {
        case .occupied: "This port is occupied or marked connected. Choose a free port."
        case .unsupported: "Choose a compatible port: network, front/rear, console or power."
        case .sameEndpoint: "Choose two different ports."
        case .changed: "A cable endpoint changed. Reload and review the connection again."
        }
        return L10n.text(text)
    }
}
struct CableEndpointSelection: Identifiable, Equatable, Sendable {
    let family: PortPanelFamily; let id: Int; let deviceID: Int; let deviceName: String; let name: String
    var objectType: String {
        switch family {
        case .interfaces: "dcim.interface"
        case .front: "dcim.frontport"
        case .rear: "dcim.rearport"
        case .console: "dcim.consoleport"
        case .consoleServer: "dcim.consoleserverport"
        case .power: "dcim.powerport"
        case .outlet: "dcim.poweroutlet"
        }
    }
    var path: String { family.path + "\(id)/" }
    static let families: [PortPanelFamily] = [.interfaces, .front, .rear, .console, .consoleServer, .power, .outlet]
    /// NetBox 4.7 COMPATIBLE_TERMINATION_TYPES restricted to device components.
    static func compatible(_ a: PortPanelFamily, _ b: PortPanelFamily) -> Bool {
        let passive: Set<PortPanelFamily> = [.front, .rear]
        switch a {
        case .interfaces: return b == .interfaces || passive.contains(b)
        case .front, .rear: return [.interfaces, .front, .rear, .console, .consoleServer].contains(b)
        case .console: return b == .consoleServer || passive.contains(b)
        case .consoleServer: return b == .console || passive.contains(b)
        case .power: return b == .outlet
        case .outlet: return b == .power
        }
    }
    func validate() throws {
        guard Self.families.contains(family), id > 0, deviceID > 0, !name.isEmpty else { throw CableCreationError.unsupported }
    }
}
struct CableEndpointSnapshot: Decodable, Sendable {
    let id: Int; let name: String; let device: NetBoxLabel
    let cable: NetBoxLabel?; let occupied: Bool; let marked: Bool; let type: VLANBrowseChoice?
    let channel: Int?
    enum CodingKeys: String, CodingKey { case id, name, device, cable, type, channel; case occupied = "_occupied", marked = "mark_connected" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.cable) else { throw APIError.invalidResponse }
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        device = try c.decode(NetBoxLabel.self, forKey: .device); cable = try c.decodeIfPresent(NetBoxLabel.self, forKey: .cable)
        occupied = try c.decode(Bool.self, forKey: .occupied); marked = try c.decode(Bool.self, forKey: .marked)
        type = try c.decodeIfPresent(VLANBrowseChoice.self, forKey: .type); channel = try c.decodeIfPresent(Int.self, forKey: .channel)
    }
    static func connectableType(_ value: String?) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return !["virtual", "lag", "bridge", "channel", "other-wireless", "gsm", "cdma", "lte", "4g", "5g"].contains(value) && !value.hasPrefix("ieee802.")
    }
    func validate(_ selected: CableEndpointSelection) throws {
        try selected.validate()
        guard id == selected.id, name == selected.name, device.id == selected.deviceID else { throw CableCreationError.changed }
        guard cable == nil, !occupied, !marked else { throw CableCreationError.occupied }
        if selected.family == .interfaces {
            guard Self.connectableType(type?.value), channel == nil else { throw CableCreationError.unsupported }
        }
    }
}
struct CableCreationPlan: Encodable, Sendable {
    let a: CableEndpointSelection; let b: CableEndpointSelection
    let label: String; let type: String; let status: String; let color: String
    static let types = ["", "cat5e", "cat6", "cat6a", "dac-passive", "dac-active", "smf", "mmf", "mmf-om3", "mmf-om4", "power", "usb"]
    static let colors = ["0088ff", "00aa66", "ff9900", "aa55dd", "333333"]
    static func colorName(_ hex: String) -> String {
        L10n.text(["0088ff": "Blue", "00aa66": "Green", "ff9900": "Orange", "aa55dd": "Purple", "333333": "Black", "": "None"][hex.lowercased()] ?? hex)
    }
    func validated() throws -> Self {
        try a.validate(); try b.validate()
        guard a.family != b.family || a.id != b.id else { throw CableCreationError.sameEndpoint }
        guard CableEndpointSelection.compatible(a.family, b.family) else { throw CableCreationError.unsupported }
        guard Self.types.contains(type), ["connected", "planned"].contains(status), Self.colors.contains(color) else { throw APIError.invalidResponse }
        guard label.unicodeScalars.count <= 100, !label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidName }
        return self
    }
    enum Keys: String, CodingKey { case a = "a_terminations", b = "b_terminations", label, type, status, color }
    private struct Termination: Encodable { let object_type: String; let object_id: Int }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode([Termination(object_type: a.objectType, object_id: a.id)], forKey: .a)
        try c.encode([Termination(object_type: b.objectType, object_id: b.id)], forKey: .b)
        try c.encode(label, forKey: .label); try c.encode(type, forKey: .type); try c.encode(status, forKey: .status); try c.encode(color, forKey: .color)
    }
    func validateReply(_ cable: CableObject) throws {
        try cable.validate()
        guard cable.label == label, cable.type == type, cable.statusValue == status, cable.color?.lowercased() == color,
              let sideA = cable.aTerminations, let sideB = cable.bTerminations,
              sideA.count == 1, sideB.count == 1,
              sideA[0].objectType == a.objectType, sideA[0].objectID == a.id,
              sideB[0].objectType == b.objectType, sideB[0].objectID == b.id else { throw APIError.invalidResponse }
        for (side, endpoint) in [(sideA[0], a), (sideB[0], b)] {
            if let device = side.object?.device { guard device.id == endpoint.deviceID else { throw APIError.invalidResponse } }
        }
    }
}
