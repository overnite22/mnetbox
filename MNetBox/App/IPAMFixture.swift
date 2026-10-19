#if DEBUG
import Foundation

// Documentation-range data shared by unit and UI tests. Never installed in Release builds.
enum IPAMFixture {
    static func response(_ url: URL, extra: [[String: Any]] = []) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let isPrefix = parts.path.contains("/ipam/prefixes/")
        guard isPrefix || parts.path.contains("/ipam/ip-addresses/") else { return nil }
        let query = parts.queryItems ?? []
        if query.contains(URLQueryItem(name: "brief", value: "true")) { return nil }
        let scoped = query.contains { ["vlan_id", "device_id", "virtual_machine_id", "within", "parent", "vrf_id", "interface_id", "vminterface_id", "tenant_id", "role_id", "scope_id", "role", "nat_inside_id"].contains($0.name) }
        let all = ((isPrefix ? extendedPrefixes : extendedAddresses) + extra).filter { !FixtureDeletions.isDeleted(url, id: $0["id"] as? Int) }
        let records = scoped ? all : ((isPrefix ? prefixes : addresses) + extra).filter { !FixtureDeletions.isDeleted(url, id: $0["id"] as? Int) }
        if let id = Int(url.lastPathComponent) {
            guard let record = all.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            return (200, json(record))
        }
        let q = query.first(where: { $0.name == "q" })?.value?.lowercased() ?? ""
        let family = query.first(where: { $0.name == "family" })?.value ?? ""
        let status = query.first(where: { $0.name == "status" })?.value ?? ""
        func value(_ key: String) -> String? { query.first(where: { $0.name == key })?.value }
        let filtered = records.filter { record in
            let primary = record[isPrefix ? "prefix" : "address"] as? String ?? ""
            let description = record["description"] as? String ?? ""
            let f = (record["family"] as? [String: Any])?["value"] as? Int ?? 0
            let s = (record["status"] as? [String: Any])?["value"] as? String ?? ""
            let vrf = (record["vrf"] as? [String: Any])?["id"] as? Int
            let tenant = (record["tenant"] as? [String: Any])?["id"] as? Int
            let role = (record["role"] as? [String: Any])?["id"] as? Int
            let scope = (record["scope"] as? [String: Any])?["id"] as? Int
            let assignment = record["assigned_object_id"] as? Int
            let assignmentType = record["assigned_object_type"] as? String
            for (key, type, parentKey) in [("device_id", "dcim.interface", "device"), ("virtual_machine_id", "virtualization.vminterface", "virtual_machine")] {
                if let filter = value(key) {
                    guard assignmentType == type, let assignment, let kind = InterfaceKind(rawValue: type),
                          let url = URL(string: "https://example.test/api/" + kind.path + "\(assignment)/"), let reply = ComponentFixture.response(url),
                          let interface = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any],
                          let parent = (interface[parentKey] as? [String: Any])?["id"] as? Int, String(parent) == filter else { return false }
                }
            }
            if let filter = value("vlan_id"), filter != ((record["vlan"] as? [String: Any])?["id"] as? Int).map(String.init) { return false }
            if let filter = value("vrf_id"), filter != (vrf.map(String.init) ?? "null") { return false }
            if let filter = value("tenant_id"), filter != tenant.map(String.init) { return false }
            if let filter = value("role_id"), filter != role.map(String.init) { return false }
            if let filter = value("scope_id"), filter != scope.map(String.init) { return false }
            if let filter = value("scope_type"), filter != record["scope_type"] as? String { return false }
            if let filter = value("interface_id"), assignmentType != "dcim.interface" || filter != assignment.map(String.init) { return false }
            if let filter = value("vminterface_id"), assignmentType != "virtualization.vminterface" || filter != assignment.map(String.init) { return false }
            if let network = value("within") ?? value("parent") {
                guard let parent = try? IPAMCIDR(network, network: true), let child = try? IPAMCIDR(primary, network: isPrefix), parent.family == child.family,
                      child.matches(parent, bits: parent.mask),
                      !isPrefix || child.mask > parent.mask else { return false }
            }
            if let filter = value("nat_inside_id"), filter != ((record["nat_inside"] as? [String: Any])?["id"] as? Int).map(String.init) { return false }
            if let filter = value("role"), filter != (record["role"] as? [String: Any])?["value"] as? String { return false }
            return (q.isEmpty || (primary + " " + description).lowercased().contains(q))
                && (family.isEmpty || family == String(f)) && (status.isEmpty || status == s)
        }
        let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
        let limit = min(2, max(1, Int(value("limit") ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < filtered.count {
            var following = parts
            following.queryItems = query.filter { $0.name != "offset" } + [URLQueryItem(name: "offset", value: String(offset + limit))]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": filtered.count, "next": next, "previous": NSNull(),
                           "results": Array(filtered.dropFirst(max(0, offset)).prefix(limit))]))
    }

    static func recordsForCreation(_ kind: IPAMKind) -> [[String: Any]] {
        kind == .prefixes ? extendedPrefixes : extendedAddresses
    }
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private static var prefixes: [[String: Any]] {
        [record(id: 1, primary: "192.0.2.0/24", prefix: true, family: 4, description: "Documentation LAN"),
         record(id: 2, primary: "2001:db8::/64", prefix: true, family: 6, description: "IPv6 LAN"),
         record(id: 3, primary: "198.51.100.0/24", prefix: true, family: 4, description: "Reserved network", status: "reserved")]
    }
    private static var addresses: [[String: Any]] {
        [record(id: 11, primary: "192.0.2.10/24", prefix: false, family: 4, description: "Documentation host"),
         record(id: 12, primary: "2001:db8::10/64", prefix: false, family: 6, description: "IPv6 host")]
    }
    private static var extendedPrefixes: [[String: Any]] {
        var global = record(id: 4, primary: "192.0.2.0/25", prefix: true, family: 4, description: "Global child")
        var overlap = record(id: 5, primary: "192.0.2.0/24", prefix: true, family: 4, description: "Blue parent")
        var child = record(id: 6, primary: "192.0.2.0/25", prefix: true, family: 4, description: "Blue child")
        overlap["vrf"] = ["id": 7, "name": "Blue"]
        child["vrf"] = ["id": 7, "name": "Blue"]
        global["tenant"] = NSNull()
        let ipv6 = record(id: 7, primary: "2001:db8::/80", prefix: true, family: 6, description: "IPv6 child")
        return prefixes + [global, overlap, child, ipv6]
    }
    private static var extendedAddresses: [[String: Any]] {
        var overlap = record(id: 13, primary: "192.0.2.10/24", prefix: false, family: 4, description: "Blue host")
        overlap["vrf"] = ["id": 7, "name": "Blue"]
        overlap["assigned_object"] = NSNull(); overlap["assigned_object_type"] = NSNull(); overlap["assigned_object_id"] = NSNull()
        var unassigned = record(id: 14, primary: "192.0.2.20/24", prefix: false, family: 4, description: "Unassigned host")
        unassigned["assigned_object"] = NSNull(); unassigned["assigned_object_type"] = NSNull(); unassigned["assigned_object_id"] = NSNull()
        return addresses + [overlap, unassigned]
    }
    private static func record(id: Int, primary: String, prefix: Bool, family: Int,
                               description: String, status: String = "active") -> [String: Any] {
        var record: [String: Any] = ["id": id, prefix ? "prefix" : "address": primary,
                                    "family": ["value": family, "label": "IPv\(family)"],
                                    "status": ["value": status, "label": status.capitalized],
                                    "vrf": NSNull(), "tenant": ["id": 1, "name": "Example tenant"],
                                    "description": description, "comments": "Read-only fixture", "tags": [["name": "example"]]]
        if prefix {
            record["children"] = [1, 2, 5].contains(id) ? 1 : 0
            record["role"] = ["id": 1, "name": "LAN"]
            record["vlan"] = ["id": 1, "display": "Documentation VLAN (100)"]
            record["scope"] = ["id": 101, "display": "Example Paris"]
            record["scope_type"] = "dcim.site"
            record["scope_id"] = 101
        } else {
            record["role"] = NSNull()
            record["nat_inside"] = NSNull(); record["nat_outside"] = []
            record["dns_name"] = "host.example.test"
            record["assigned_object"] = ["id": family == 4 ? 501 : 801, "display": "eth0"]
            record["assigned_object_type"] = family == 4 ? "dcim.interface" : "virtualization.vminterface"
            record["assigned_object_id"] = family == 4 ? 501 : 801
        }
        return record
    }
}

extension IPAMCIDR {
    /// Whether the leading bits of both addresses are equal; fixture filtering only.
    func matches(_ other: IPAMCIDR, bits: Int) -> Bool {
        (0..<bits).allSatisfy { (bit: Int) -> Bool in
            let flag = UInt8(1 << (7 - bit % 8))
            return bytes[bit / 8] & flag == other.bytes[bit / 8] & flag
        }
    }
}
#endif
