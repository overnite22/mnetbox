import Foundation

/// One reviewed device creation. References are re-read and visible duplicates re-checked
/// immediately before the single POST; NetBox validation (rack occupancy, uniqueness) stays authoritative.
struct DeviceCreationPlan: Encodable, Sendable, Equatable {
    var name = ""
    var deviceType: ReferenceSelection?
    var role: ReferenceSelection?
    var site: ReferenceSelection?
    var status = "active"
    var rack: ReferenceSelection?
    var position: Int?
    var face = ""
    var serial = ""
    var assetTag = ""
    var tenant: ReferenceSelection?
    var description = ""

    static let faces = ["", "front", "rear"]
    func normalized() -> Self {
        var plan = self
        plan.name = EditableTextField.name.normalized(name)
        plan.serial = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.assetTag = assetTag.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.description = EditableTextField.description.normalized(description)
        if rack == nil { plan.position = nil; plan.face = "" }
        return plan
    }
    func validated() throws -> Self {
        let plan = normalized()
        guard let deviceType = plan.deviceType, let role = plan.role, let site = plan.site,
              [deviceType.id, role.id, site.id].allSatisfy({ $0 > 0 }), (plan.rack?.id ?? 1) > 0, (plan.tenant?.id ?? 1) > 0 else { throw APIError.invalidReference }
        guard InventoryKind.devices.statuses.contains(plan.status), Self.faces.contains(plan.face) else { throw APIError.invalidStatus }
        try EditableTextField.name.validate(plan.name, for: .devices)
        try EditableTextField.description.validate(plan.description)
        for value in [plan.serial, plan.assetTag] {
            guard value.unicodeScalars.count <= 50, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidName }
        }
        if let position = plan.position {
            guard plan.rack != nil, (1...100).contains(position), !plan.face.isEmpty else { throw APIError.invalidPosition }
        }
        return plan
    }
    enum Keys: String, CodingKey { case name, role, site, status, rack, position, face, serial, tenant, description; case deviceType = "device_type", assetTag = "asset_tag" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        if name.isEmpty { try c.encodeNil(forKey: .name) } else { try c.encode(name, forKey: .name) }
        try c.encode(deviceType?.id, forKey: .deviceType); try c.encode(role?.id, forKey: .role); try c.encode(site?.id, forKey: .site)
        try c.encode(status, forKey: .status)
        if let rack { try c.encode(rack.id, forKey: .rack) } else { try c.encodeNil(forKey: .rack) }
        if let position { try c.encode(position, forKey: .position) } else { try c.encodeNil(forKey: .position) }
        try c.encode(face, forKey: .face)
        try c.encode(serial, forKey: .serial)
        // Asset tags are unique when set: an empty tag is sent as null, never as "".
        if assetTag.isEmpty { try c.encodeNil(forKey: .assetTag) } else { try c.encode(assetTag, forKey: .assetTag) }
        if let tenant { try c.encode(tenant.id, forKey: .tenant) } else { try c.encodeNil(forKey: .tenant) }
        try c.encode(description, forKey: .description)
    }
    func matches(_ reply: DeviceCreationReply) -> Bool {
        reply.id > 0 && (reply.name ?? "") == name && reply.site.id == site?.id && reply.deviceType.id == deviceType?.id
            && reply.role.id == role?.id && reply.rack?.id == rack?.id && reply.status.value == status
    }
}

struct DeviceCreationReply: Decodable, Sendable {
    struct Choice: Decodable, Sendable { let value: String }
    let id: Int; let name: String?; let site: NetBoxLabel; let deviceType: NetBoxLabel; let role: NetBoxLabel
    let rack: NetBoxLabel?; let status: Choice
    enum CodingKeys: String, CodingKey { case id, name, site, role, rack, status; case deviceType = "device_type" }
}

struct DeviceRackSite: Decodable, Sendable { let id: Int; let site: NetBoxLabel }
