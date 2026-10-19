#if DEBUG
import Foundation

final class IPAMAdministrationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var prefixes = IPAMFixture.recordsForCreation(.prefixes)
    private var addresses = IPAMFixture.recordsForCreation(.ipAddresses)
    init() {
        prefixes.append(["id": 9005, "prefix": "203.0.113.0/28", "family": ["value": 4, "label": "IPv4"], "status": ["value": "active", "label": "Active"], "vrf": NSNull(), "tenant": NSNull(), "role": NSNull(), "vlan": NSNull(), "scope_type": NSNull(), "scope_id": NSNull(), "scope": NSNull(), "children": 0, "description": "Unused prefix", "comments": ""])
        addresses.append(["id": 9006, "address": "203.0.113.99/24", "family": ["value": 4, "label": "IPv4"], "status": ["value": "active", "label": "Active"], "vrf": NSNull(), "tenant": NSNull(), "role": NSNull(), "assigned_object_type": NSNull(), "assigned_object_id": NSNull(), "assigned_object": NSNull(), "nat_inside": NSNull(), "nat_outside": [], "dns_name": "", "description": "Unused IP", "comments": ""])
        if var ipv6Prefix = prefixes.last, var ipv6IP = addresses.last {
            ipv6Prefix["id"] = 9007; ipv6Prefix["prefix"] = "2001:db8:abcd::/64"; ipv6Prefix["family"] = ["value": 6, "label": "IPv6"]
            ipv6IP["id"] = 9008; ipv6IP["address"] = "2001:db8:ffff::99/64"; ipv6IP["family"] = ["value": 6, "label": "IPv6"]
            prefixes.append(ipv6Prefix); addresses.append(ipv6IP)
        }
    }
    private func json(_ row: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: row), let value = String(data: data, encoding: .utf8) else { return "{}" }; return value }
    private func reference(_ value: Any, path: String) -> Any {
        guard let id = value as? Int, let url = URL(string: "https://example.test/api/" + path + "\(id)/"), let reply = ComponentFixture.response(url) ?? InventoryFixture.response(url), let data = reply.1.data(using: .utf8), let row = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return row
    }
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let prefix = parts.path.hasPrefix("/api/ipam/prefixes/")
        guard prefix || parts.path.hasPrefix("/api/ipam/ip-addresses/") else { return nil }
        lock.lock(); defer { lock.unlock() }
        var rows = prefix ? prefixes : addresses
        if let id = Int(url.lastPathComponent) {
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            if request.httpMethod == "PATCH", let data = requestBody(request), let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                for (key, value) in body {
                    if ["vlan", "role", "vrf"].contains(key) { rows[index][key] = reference(value, path: key == "vlan" ? "ipam/vlans/" : key == "role" ? "ipam/roles/" : "ipam/vrfs/") }
                    else { rows[index][key] = value }
                }
                if body["scope_type"] != nil {
                    let type = PrefixScope(rawValue: body["scope_type"] as? String ?? "") ?? .global
                    rows[index]["scope"] = reference(body["scope_id"] ?? NSNull(), path: type.path)
                }
                if let text = body[prefix ? "prefix" : "address"] as? String, let cidr = try? IPAMCIDR(text, network: prefix) { rows[index]["family"] = ["value": cidr.family, "label": "IPv\(cidr.family)"] }
                if prefix { prefixes = rows } else { addresses = rows }
            } else if request.httpMethod != "GET" { return nil }
            return (200, json(rows[index]))
        }
        guard request.httpMethod == "GET" else { return nil }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        func contained(_ text: String, by root: String) -> Bool {
            guard let a = try? IPAMCIDR(text, network: prefix), let b = try? IPAMCIDR(root, network: true), a.family == b.family else { return false }
            return (!prefix || a.mask > b.mask) && a.matches(b, bits: b.mask)
        }
        rows = rows.filter { row in
            for key in ["vrf", "vlan", "tenant", "role"] {
                if let selected = value(key + "_id"), selected != (((row[key] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null") { return false }
            }
            if let selected = value("prefix"), row["prefix"] as? String != selected { return false }
            if let selected = value("address"), let text = row["address"] as? String {
                guard let a = try? IPAMCIDR(text, network: false), let b = try? IPAMCIDR(selected.contains("/") ? selected : selected + (selected.contains(":") ? "/128" : "/32"), network: false), a.bytes == b.bytes else { return false }
            }
            if let network = value("within") ?? value("parent"), !contained(row[prefix ? "prefix" : "address"] as? String ?? "", by: network) { return false }
            for (key, actual) in [("scope_type", row["scope_type"] as? String), ("scope_id", (row["scope_id"] as? Int).map(String.init)), ("interface_id", row["assigned_object_type"] as? String == "dcim.interface" ? (row["assigned_object_id"] as? Int).map(String.init) : nil), ("vminterface_id", row["assigned_object_type"] as? String == "virtualization.vminterface" ? (row["assigned_object_id"] as? Int).map(String.init) : nil), ("nat_inside_id", ((row["nat_inside"] as? [String: Any])?["id"] as? Int).map(String.init))] {
                if let selected = value(key), selected != actual { return false }
            }
            if let q = value("q"), !q.isEmpty, ![row[prefix ? "prefix" : "address"] as? String ?? "", row["description"] as? String ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return false }
            return true
        }
        rows.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        let offset = Int(value("offset") ?? "0") ?? 0, limit = min(2, Int(value("limit") ?? "50") ?? 50)
        var next: Any = NSNull()
        if offset + limit < rows.count { var following = parts; following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]; next = following.url?.absoluteString ?? "" }
        return (200, json(["count": rows.count, "next": next, "results": Array(rows.dropFirst(offset).prefix(limit))]))
    }
}
#endif
