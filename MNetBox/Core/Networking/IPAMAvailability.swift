import Foundation

/// Read-only suggestions from NetBox's native available-ips / available-prefixes endpoints.
/// Nothing is allocated here: the suggestion pre-fills the reviewed creation form, whose
/// duplicate check is repeated before its single POST.
enum IPAMAvailability {
    struct AvailableIP: Decodable, Sendable { let address: String; let vrf: NetBoxLabel? }
    struct AvailablePrefix: Decodable, Sendable { let prefix: String; let vrf: NetBoxLabel? }

    /// Whether the first `parent.mask` bits of both networks are equal (same family required).
    static func contains(_ parent: IPAMCIDR, _ child: IPAMCIDR) -> Bool {
        guard parent.family == child.family, child.mask >= parent.mask else { return false }
        return (0..<parent.mask).allSatisfy { (bit: Int) -> Bool in
            let flag = UInt8(1 << (7 - bit % 8))
            return parent.bytes[bit / 8] & flag == child.bytes[bit / 8] & flag
        }
    }
    /// First IP suggested by NetBox, checked against the parent prefix and its VRF.
    static func firstIP(_ values: [AvailableIP], parent: IPAMCIDR, vrfID: Int?) throws -> IPAMCIDR? {
        guard let first = values.first else { return nil }
        let address = try IPAMCIDR(first.address, network: false)
        guard contains(parent, address), first.vrf?.id == vrfID else { throw APIError.invalidResponse }
        return address
    }
    /// First /length block inside the first available range large enough. Available ranges
    /// are network-aligned, so their first child keeps the same network address.
    static func firstPrefix(_ values: [AvailablePrefix], parent: IPAMCIDR, vrfID: Int?, length: Int) throws -> IPAMCIDR? {
        guard length > parent.mask, length <= parent.bytes.count * 8 else { throw APIError.invalidCIDR }
        for value in values {
            let block = try IPAMCIDR(value.prefix, network: true)
            guard contains(parent, block), value.vrf?.id == vrfID else { throw APIError.invalidResponse }
            if block.mask <= length { return try IPAMCIDR("\(block.host)/\(length)", network: true) }
        }
        return nil
    }
}
