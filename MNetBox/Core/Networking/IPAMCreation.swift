import Foundation
import Darwin

struct IPAMCIDR: Equatable, Sendable {
    let bytes: [UInt8]
    let mask: Int
    let family: Int
    let host: String
    var text: String { "\(host)/\(mask)" }
    init(_ input: String, network: Bool) throws {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              parts[0].utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) || $0 == 46 || $0 == 58 }),
              parts[1].utf8.allSatisfy({ (48...57).contains($0) }), let mask = Int(parts[1]) else { throw APIError.invalidCIDR }
        // Darwin accepts leading-zero IPv4 octets; reject ambiguous notation before parsing.
        if parts[0].contains(".") {
            let dotted = parts[0].split(separator: ":", omittingEmptySubsequences: false).last ?? parts[0]
            let octets = dotted.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.count <= 3 && ($0.count == 1 || $0.first != "0") && (Int($0) ?? 256) <= 255 }) else { throw APIError.invalidCIDR }
        }
        let version = parts[0].contains(":") ? 6 : 4
        let socketFamily = version == 6 ? AF_INET6 : AF_INET
        let count = version == 6 ? 16 : 4
        guard (0...(count * 8)).contains(mask) else { throw APIError.invalidCIDR }
        var bytes = [UInt8](repeating: 0, count: count)
        let parsed = String(parts[0]).withCString { input in
            bytes.withUnsafeMutableBytes { inet_pton(socketFamily, input, $0.baseAddress) }
        }
        guard parsed == 1 else { throw APIError.invalidCIDR }
        if network, (mask..<(count * 8)).contains(where: { bytes[$0 / 8] & UInt8(1 << (7 - $0 % 8)) != 0 }) {
            throw APIError.networkHostBits
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let formatted = bytes.withUnsafeBytes { data in
            buffer.withUnsafeMutableBufferPointer { inet_ntop(socketFamily, data.baseAddress, $0.baseAddress, socklen_t($0.count)) != nil }
        }
        guard formatted else { throw APIError.invalidCIDR }
        self.bytes = bytes; self.mask = mask; family = version; host = String(cString: buffer)
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes && lhs.mask == rhs.mask && lhs.family == rhs.family }
}

struct IPAMCreationDraft: Sendable {
    let kind: IPAMKind
    var cidr = ""
    var status = "active"
    var vrf: ReferenceSelection?
    var tenant: ReferenceSelection?
    var description = ""
    var comments = ""
    var dnsName = ""
    var assignment: InterfaceSelection?
    func plan() throws -> IPAMCreationPlan {
        guard kind.statuses.contains(status), (vrf?.id ?? 1) > 0, (tenant?.id ?? 1) > 0 else { throw APIError.invalidResponse }
        if let assignment {
            guard kind == .ipAddresses, assignment.id > 0, (assignment.parentID ?? 0) > 0, !assignment.title.isEmpty else { throw APIError.invalidReference }
        }
        let parsed = try IPAMCIDR(cidr, network: kind == .prefixes)
        guard parsed.mask > 0 else { throw APIError.invalidCIDR }
        let description = EditableTextField.description.normalized(description)
        let comments = EditableTextField.comments.normalized(comments)
        let dns = EditableTextField.dnsName.normalized(dnsName)
        try EditableTextField.description.validate(description)
        try EditableTextField.comments.validate(comments)
        if kind == .ipAddresses { try EditableTextField.dnsName.validate(dns) }
        else if !dns.isEmpty { throw APIError.invalidResponse }
        return IPAMCreationPlan(kind: kind, cidr: parsed, status: status, vrf: vrf, tenant: tenant,
                                description: description, comments: comments, dnsName: dns, assignment: assignment)
    }
}

struct IPAMCreationPlan: Encodable, Sendable {
    let kind: IPAMKind
    let cidr: IPAMCIDR
    let status: String
    let vrf: ReferenceSelection?
    let tenant: ReferenceSelection?
    let description: String
    let comments: String
    let dnsName: String
    var assignment: InterfaceSelection? = nil
    enum CodingKeys: String, CodingKey { case prefix, address, status, vrf, tenant, description, comments; case dnsName = "dns_name", assignedType = "assigned_object_type", assignedID = "assigned_object_id" }
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(cidr.text, forKey: kind == .prefixes ? .prefix : .address)
        try fields.encode(status, forKey: .status)
        if let vrf { try fields.encode(vrf.id, forKey: .vrf) } else { try fields.encodeNil(forKey: .vrf) }
        if let tenant { try fields.encode(tenant.id, forKey: .tenant) } else { try fields.encodeNil(forKey: .tenant) }
        try fields.encode(description, forKey: .description)
        try fields.encode(comments, forKey: .comments)
        if kind == .ipAddresses { try fields.encode(dnsName, forKey: .dnsName) }
        if let assignment {
            try fields.encode(assignment.kind.rawValue, forKey: .assignedType)
            try fields.encode(assignment.id, forKey: .assignedID)
        }
    }
    // Validate again at the transport boundary, even if a plan was constructed outside the form.
    func validated() throws -> IPAMCreationPlan {
        try IPAMCreationDraft(kind: kind, cidr: cidr.text, status: status, vrf: vrf, tenant: tenant,
                              description: description, comments: comments, dnsName: dnsName, assignment: assignment).plan()
    }
    func matches(_ object: IPAMObject, exactMask: Bool = true) -> Bool {
        guard object.id > 0, (vrf == nil ? object.vrf == nil : object.vrf?.id == vrf?.id),
              let value = kind == .prefixes ? object.prefix : object.address,
              let parsed = try? IPAMCIDR(value, network: kind == .prefixes) else { return false }
        return exactMask ? parsed == cidr : (parsed.family == cidr.family && parsed.bytes == cidr.bytes)
    }
}

struct IPAMCreationReply: Decodable, Sendable {
    let object: IPAMObject
    let status: String
    private struct Choice: Decodable { let value: String }
    private enum CodingKeys: String, CodingKey { case vrf, tenant, status }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard fields.contains(.vrf), fields.contains(.tenant) else { throw APIError.invalidResponse }
        status = try fields.decode(Choice.self, forKey: .status).value
        object = try IPAMObject(from: decoder)
    }
}
