import Foundation

extension PortPanelFamily {
    /// Inverse of CableEndpointSelection.objectType, for device components only.
    init?(objectType: String) {
        switch objectType {
        case "dcim.interface": self = .interfaces
        case "dcim.frontport": self = .front
        case "dcim.rearport": self = .rear
        case "dcim.consoleport": self = .console
        case "dcim.consoleserverport": self = .consoleServer
        case "dcim.powerport": self = .power
        case "dcim.poweroutlet": self = .outlet
        default: return nil
        }
    }
}

enum CableSide: String, Sendable, CaseIterable, Identifiable {
    case a, b
    var id: String { rawValue }
    var title: String { self == .a ? "A" : "B" }
    var key: String { rawValue + "_terminations" }
}

/// Moves exactly one end of a single-termination cable to another free, compatible port.
/// The reviewed cable version (ETag + both ends) must still hold immediately before the PATCH.
struct CableRewirePlan: Sendable, Equatable {
    let cableID: Int
    let etag: String
    let side: CableSide
    let current: CableEndpointSelection
    let kept: CableEndpointSelection
    let destination: CableEndpointSelection

    static func ends(of cable: CableObject) throws -> (a: CableEndpointSelection, b: CableEndpointSelection) {
        try cable.validate()
        guard let a = cable.aTerminations, let b = cable.bTerminations, a.count == 1, b.count == 1 else { throw CableCreationError.unsupported }
        return (try selection(a[0]), try selection(b[0]))
    }
    private static func selection(_ value: CableTermination) throws -> CableEndpointSelection {
        guard let family = PortPanelFamily(objectType: value.objectType), let object = value.object, object.id == value.objectID,
              let device = object.device, let deviceID = device.id, deviceID > 0, let name = object.name, !name.isEmpty else { throw CableCreationError.unsupported }
        return CableEndpointSelection(family: family, id: value.objectID, deviceID: deviceID, deviceName: device.text, name: name)
    }
    func validated() throws -> Self {
        guard cableID > 0, TextEditSnapshot.validETag(etag) else { throw APIError.missingETag }
        try current.validate(); try kept.validate(); try destination.validate()
        guard !(destination.family == current.family && destination.id == current.id), !(destination.family == kept.family && destination.id == kept.id) else { throw CableCreationError.sameEndpoint }
        guard CableEndpointSelection.compatible(kept.family, destination.family) else { throw CableCreationError.unsupported }
        return self
    }
    private struct Termination: Encodable { let object_type: String; let object_id: Int }
    /// Only the moved side is sent; the kept side is never rewritten.
    var body: Data { get throws { try JSONEncoder().encode([side.key: [Termination(object_type: destination.objectType, object_id: destination.id)]]) } }
    func matches(_ cable: CableObject, moved: Bool) throws {
        let ends = try Self.ends(of: cable)
        let expected = moved ? destination : current
        let (changed, other) = side == .a ? (ends.a, ends.b) : (ends.b, ends.a)
        guard cable.id == cableID, changed.family == expected.family, changed.id == expected.id, changed.deviceID == expected.deviceID, changed.name == expected.name,
              other.family == kept.family, other.id == kept.id, other.deviceID == kept.deviceID, other.name == kept.name else { throw moved ? APIError.invalidResponse : APIError.conflict }
    }
}
