import Foundation

struct StructuredEditTarget: Sendable, Equatable {
    enum Collection: String, Sendable, CaseIterable {
        case devices = "dcim/devices/", virtualMachines = "virtualization/virtual-machines/"
        case physicalInterfaces = "dcim/interfaces/", virtualInterfaces = "virtualization/interfaces/"
        case prefixes = "ipam/prefixes/", ipAddresses = "ipam/ip-addresses/"
        case vlans = "ipam/vlans/", macAddresses = "dcim/mac-addresses/"
        var isIPAM: Bool { self == .prefixes || self == .ipAddresses }
        var isInterface: Bool { self == .physicalInterfaces || self == .virtualInterfaces }
    }
    let collection: Collection
    let id: Int
    var parentID: Int? = nil
    var path: String { get throws {
        guard id > 0, !collection.isInterface || (parentID ?? 0) > 0 else { throw APIError.invalidURL }
        return collection.rawValue + "\(id)/"
    } }
}
enum StructuredEditField: String, CodingKey, CaseIterable, Identifiable, Sendable {
    case enabled, mtu, tenant, role, platform, status, name, description, type
    case primaryMAC = "primary_mac_address"
    case primaryIP4 = "primary_ip4", primaryIP6 = "primary_ip6", assignment
    var id: String { rawValue }
    var title: String { L10n.text(self == .primaryMAC ? "Primary MAC" : self == .mtu ? "MTU" : self == .primaryIP4 ? "Primary IPv4" : self == .primaryIP6 ? "Primary IPv6" : rawValue.capitalized) }
    var editTitle: String { L10n.text("Edit " + (self == .primaryMAC ? "primary MAC" : self == .mtu ? "MTU" : self == .primaryIP4 ? "primary IPv4" : self == .primaryIP6 ? "primary IPv6" : rawValue)) }
    var isText: Bool { self == .name || self == .description }
    var isReference: Bool { self == .primaryMAC || self == .tenant || self == .role || self == .platform || self == .primaryIP4 || self == .primaryIP6 }
    var referencePath: String {
        self == .primaryMAC ? "dcim/mac-addresses/" : self == .primaryIP4 || self == .primaryIP6 ? "ipam/ip-addresses/" : self == .tenant ? "tenancy/tenants/" : self == .role ? "dcim/device-roles/" : "dcim/platforms/"
    }
    func supports(_ collection: StructuredEditTarget.Collection) -> Bool {
        if collection == .vlans { return self == .tenant || self == .role }
        if collection == .macAddresses { return self == .assignment }
        switch self {
        case .primaryMAC: return collection.isInterface
        case .enabled, .mtu, .name, .description: return collection.isInterface
        case .type: return collection == .physicalInterfaces
        case .tenant: return !collection.isInterface
        case .status: return collection.isIPAM
        case .assignment: return collection == .ipAddresses
        case .role, .platform, .primaryIP4, .primaryIP6: return !collection.isInterface && !collection.isIPAM
        }
    }
    func statuses(_ collection: StructuredEditTarget.Collection) -> [String] {
        (collection == .prefixes ? IPAMKind.prefixes : .ipAddresses).statuses
    }
    func allowsEmpty(_ collection: StructuredEditTarget.Collection) -> Bool { self != .role || collection != .devices }
    func filters(_ collection: StructuredEditTarget.Collection, id: Int = 0) -> [URLQueryItem] {
        if self == .primaryMAC { return [.init(name: collection == .physicalInterfaces ? "interface_id" : "vminterface_id", value: String(id))] }
        if self == .primaryIP4 || self == .primaryIP6 {
            return [.init(name: collection == .devices ? "device_id" : "virtual_machine_id", value: String(id)), .init(name: "family", value: self == .primaryIP4 ? "4" : "6")]
        }
        return self == .role && collection == .virtualMachines ? [.init(name: "vm_role", value: "true")] : []
    }
}
enum StructuredEditValue: Sendable {
    case enabled(Bool), mtu(Int?), reference(ReferenceSelection?), status(String), assignment(InterfaceSelection?), text(String), interfaceType(String)
    func matches(_ other: StructuredEditValue) -> Bool {
        switch (self, other) {
        case let (.text(a), .text(b)), let (.interfaceType(a), .interfaceType(b)): a == b
        case let (.status(a), .status(b)): a == b
        case let (.assignment(a), .assignment(b)): a?.id == b?.id && a?.kind == b?.kind
        case let (.enabled(a), .enabled(b)): a == b
        case let (.mtu(a), .mtu(b)): a == b
        case let (.reference(a), .reference(b)): a?.id == b?.id
        default: false
        }
    }
    var display: String {
        switch self {
        case .text(let value): value.isEmpty ? L10n.text("Empty") : value
        case .interfaceType(let value): InterfaceTypeOptions.title(value)
        case .status(let value): L10n.text(value.capitalized)
        case .assignment(let value): value.map { "\($0.kind.parentKind.singular) · \($0.title) (#\($0.id))" } ?? L10n.text("None")
        case .enabled(let enabled): L10n.text(enabled ? "Yes" : "No")
        case .mtu(let value): value.map(String.init) ?? L10n.text("Empty")
        case .reference(let value): value.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None")
        }
    }
    func validate(field: StructuredEditField, target: StructuredEditTarget) throws {
        _ = try target.path
        guard field.supports(target.collection) else { throw APIError.invalidURL }
        switch (field, self) {
        case (.name, .text(let value)):
            guard try InterfaceCreationDraft.normalizedName(value) == value else { throw APIError.invalidName }
        case (.description, .text(let value)):
            try EditableTextField.description.validate(value)
            guard EditableTextField.description.normalized(value) == value else { throw APIError.invalidResponse }
        case (.type, .interfaceType(let value)):
            guard InterfaceTypeOptions.values.contains(value) else { throw APIError.invalidResponse }
        case (.status, .status(let value)):
            guard field.statuses(target.collection).contains(value) else { throw APIError.invalidResponse }
        case (.assignment, .assignment(let value)):
            if let value { guard value.id > 0 else { throw APIError.invalidReference } }
        case (.enabled, .enabled): break
        case (.mtu, .mtu(let value)):
            if let value, !(1...65536).contains(value) { throw APIError.invalidMTU }
        case (_, .reference(let value)) where field.isReference:
            if let value { guard value.id > 0 else { throw APIError.invalidReference } }
            else if !field.allowsEmpty(target.collection) { throw APIError.requiredRole }
        default: throw APIError.invalidResponse
        }
    }
}
struct InterfaceSelection: Sendable {
    let kind: InterfaceKind
    let id: Int
    let title: String
    var parentID: Int? = nil
}
struct EditReference: Decodable, Sendable {
    let id: Int
    let name: String?
    let display: String?
    let address: String?
    let vmRole: Bool?
    enum CodingKeys: String, CodingKey { case id, name, display, address; case vmRole = "vm_role" }
    var selection: ReferenceSelection { ReferenceSelection(id: id, title: display ?? name ?? address ?? "#\(id)") }
}
struct StructuredEditObject: Decodable, Sendable {
    let id: Int
    let title: String
    let parentDevice: EditReference?
    let parentVM: EditReference?
    private let values: [StructuredEditField: StructuredEditValue]
    enum Keys: String, CodingKey { case id, display, name, address, prefix, enabled, mtu, tenant, role, platform, device, status, description, type
        case primaryMAC = "primary_mac_address", macAddress = "mac_address"
        case primaryIP4 = "primary_ip4", primaryIP6 = "primary_ip6"
        case assignedType = "assigned_object_type", assignedID = "assigned_object_id", assignedObject = "assigned_object"; case virtualMachine = "virtual_machine" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .display) ?? container.decodeIfPresent(String.self, forKey: .name) ?? container.decodeIfPresent(String.self, forKey: .address) ?? container.decodeIfPresent(String.self, forKey: .prefix) ?? container.decodeIfPresent(String.self, forKey: .macAddress) ?? "#\(id)"
        parentDevice = try container.decodeIfPresent(EditReference.self, forKey: .device)
        parentVM = try container.decodeIfPresent(EditReference.self, forKey: .virtualMachine)
        var values: [StructuredEditField: StructuredEditValue] = [:]
        for (field, key) in [(StructuredEditField.name, Keys.name), (.description, .description)] {
            if let text = try container.decodeIfPresent(String.self, forKey: key) { values[field] = .text(text) }
        }
        if container.contains(.type) {
            struct TypeChoice: Decodable { let value: String }
            if let choice = try container.decodeIfPresent(TypeChoice.self, forKey: .type) { values[.type] = .interfaceType(choice.value) }
        }
        if let value = try container.decodeIfPresent(Bool.self, forKey: .enabled) { values[.enabled] = .enabled(value) }
        if container.contains(.mtu) { values[.mtu] = .mtu(try container.decodeIfPresent(Int.self, forKey: .mtu)) }
        for (field, key) in [(StructuredEditField.tenant, Keys.tenant), (.role, .role), (.platform, .platform), (.primaryIP4, .primaryIP4), (.primaryIP6, .primaryIP6), (.primaryMAC, .primaryMAC)] {
            if container.contains(key) {
                let reference = try container.decodeIfPresent(EditReference.self, forKey: key)
                if let reference, reference.id <= 0 { throw APIError.invalidResponse }
                values[field] = .reference(reference?.selection)
            }
        }
        if container.contains(.status) {
            struct Choice: Decodable { let value: String }
            values[.status] = .status(try container.decode(Choice.self, forKey: .status).value)
        }
        if container.contains(.assignedType) && container.contains(.assignedID) {
            let type = try container.decodeIfPresent(String.self, forKey: .assignedType)
            let identifier = try container.decodeIfPresent(Int.self, forKey: .assignedID)
            if type == nil && identifier == nil { values[.assignment] = .assignment(nil) }
            else if let type, let kind = InterfaceKind(rawValue: type), let identifier, identifier > 0 {
                let object = try container.decodeIfPresent(EditReference.self, forKey: .assignedObject)
                guard object == nil || object?.id == identifier else { throw APIError.invalidResponse }
                values[.assignment] = .assignment(InterfaceSelection(kind: kind, id: identifier, title: object?.selection.title ?? "#\(identifier)"))
            }
        }
        self.values = values
    }
    func value(_ field: StructuredEditField) -> StructuredEditValue? { values[field] }
    func validate(target: StructuredEditTarget, field: StructuredEditField) throws {
        guard id == target.id, let value = value(field) else { throw APIError.invalidResponse }
        if target.collection.isInterface {
            let parent = target.collection == .physicalInterfaces ? parentDevice : parentVM
            guard parent?.id == target.parentID else { throw APIError.invalidResponse }
        }
        if case .text(let text) = value, field.isText {
            guard field.supports(target.collection), text.unicodeScalars.count <= (field == .name ? 64 : 200), field != .name || !text.isEmpty else { throw APIError.invalidResponse }
        } else if case .interfaceType(let type) = value, field == .type {
            guard field.supports(target.collection), !type.isEmpty else { throw APIError.invalidResponse }
        } else { try value.validate(field: field, target: target) }
    }
}
struct StructuredEditSnapshot: Sendable {
    let target: StructuredEditTarget
    let field: StructuredEditField
    let object: StructuredEditObject
    let etag: String
}
struct StructuredEditPayload: Encodable {
    let field: StructuredEditField
    let value: StructuredEditValue
    private enum AssignmentKeys: String, CodingKey { case type = "assigned_object_type", id = "assigned_object_id" }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StructuredEditField.self)
        switch value {
        case .text(let value), .interfaceType(let value), .status(let value): try container.encode(value, forKey: field)
        case .assignment(let value):
            var assignment = encoder.container(keyedBy: AssignmentKeys.self)
            try assignment.encode(value?.kind.rawValue, forKey: .type)
            try assignment.encode(value?.id, forKey: .id)
        case .enabled(let value): try container.encode(value, forKey: field)
        case .mtu(let value): try container.encode(value, forKey: field)
        case .reference(let value): try container.encode(value?.id, forKey: field)
        }
    }
}
