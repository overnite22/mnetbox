#if DEBUG
import Foundation

enum ComponentFixture {
    static func response(_ url: URL, extra: [[String: Any]] = []) -> (Int, String)? {
        if let reply = ContextFixture.response(url) { return reply }
        if let reply = VLANBrowseFixture.response(url) { return reply }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if let reply = CableBrowseFixture.response(url) { return reply }
        let virtual = parts.path.contains("/api/virtualization/interfaces/")
        let physical = parts.path.contains("/api/dcim/interfaces/")
        let lookup: [[String: Any]]?
        if parts.path.contains("/api/dcim/device-roles/") { lookup = [["id": 1, "name": "Network", "vm_role": false], ["id": 2, "name": "Application", "vm_role": true]] }
        else if parts.path.contains("/api/dcim/platforms/") { lookup = [["id": 1, "name": "Linux"], ["id": 2, "name": "RouterOS"]] }
        else { lookup = nil }
        guard virtual || physical || lookup != nil else { return nil }
        let query = parts.queryItems ?? []
        var records = lookup ?? (virtual ? [interface(801, parent: 401, virtual: true), interface(802, parent: 401, virtual: true), interface(803, parent: 401, virtual: true), interface(901, parent: 402, virtual: true)] : [interface(501, parent: 301), interface(502, parent: 301), interface(503, parent: 301), interface(601, parent: 303)])
        records += extra
        records = records.filter { !FixtureDeletions.isDeleted(url, id: $0["id"] as? Int) }
        if let id = Int(url.lastPathComponent) {
            guard let record = records.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            return (200, json(record))
        }
        let search = query.first(where: { $0.name == "q" })?.value?.lowercased() ?? ""
        let enabled = query.first(where: { $0.name == "enabled" })?.value
        let parent = query.first(where: { $0.name == (virtual ? "virtual_machine_id" : "device_id") })?.value.flatMap(Int.init)
        records = records.filter { row in
            if let vlan = query.first(where: { $0.name == "vlan_id" })?.value.flatMap(Int.init) {
                let untagged = (row["untagged_vlan"] as? [String: Any])?["id"] as? Int
                let tagged = (row["tagged_vlans"] as? [[String: Any]])?.contains { $0["id"] as? Int == vlan } == true
                let qinq = (row["qinq_svlan"] as? [String: Any])?["id"] as? Int
                if untagged != vlan && !tagged && qinq != vlan { return false }
            }
            if let site = query.first(where: { $0.name == "site_id" })?.value {
                let actual = ((row["site"] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null"
                if site != actual { return false }
            }
            if query.contains(URLQueryItem(name: "vm_role", value: "true")), row["vm_role"] as? Bool != true { return false }
            if let name = query.first(where: { $0.name == "name" })?.value, row["name"] as? String != name { return false }
            if let parent, (row[virtual ? "virtual_machine" : "device"] as? [String: Any])?["id"] as? Int != parent { return false }
            for key in ["parent", "bridge", "lag"] {
                if let value = query.first(where: { $0.name == key + "_id" })?.value, value != ((row[key] as? [String: Any])?["id"] as? Int).map(String.init) { return false }
            }
            if let enabled, (row["enabled"] as? Bool) != (enabled == "true") { return false }
            return search.isEmpty || (row["name"] as? String ?? "").lowercased().contains(search)
        }
        let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
        var next: Any = NSNull()
        if offset + 2 < records.count {
            var nextParts = parts
            nextParts.queryItems = query.filter { $0.name != "offset" } + [URLQueryItem(name: "offset", value: String(offset + 2))]
            next = nextParts.url?.absoluteString ?? ""
        }
        return (200, json(["count": records.count, "next": next, "previous": NSNull(), "results": Array(records.dropFirst(offset).prefix(min(2, Int(query.first(where: { $0.name == "limit" })?.value ?? "2") ?? 2)))]))
    }
    private static func interface(_ id: Int, parent: Int, virtual: Bool = false) -> [String: Any] {
        let name = [501: "eth0", 502: "eth1", 503: "eth0.100", 601: "uplink", 801: "eth0", 802: "eth1", 803: "eth2", 901: "eth0"][id] ?? "eth0"
        var record: [String: Any] = ["id": id, "name": name, "display": name, "enabled": id != 502 && id != 802,
                                    virtual ? "virtual_machine" : "device": ["id": parent, "name": virtual ? "monitoring-01" : parent == 301 ? "Core-switch" : "Edge-router"],
                                    "mtu": 1500, "description": "Synthetic interface", "mac_address": NSNull(),
                                    "primary_mac_address": ["id": 1, "mac_address": "02:00:00:00:00:01"],
                                    "mac_addresses": [["id": 1, "mac_address": "02:00:00:00:00:01"], ["id": 2, "mac_address": "02:00:00:00:00:02"]]]
        if !virtual {
            record["type"] = ["value": "1000base-t", "label": "1000BASE-T"]
            record["speed"] = 1000000
            record["cable"] = id == 501 ? ["id": 701, "display": "Uplink-A"] : NSNull()
            record["link_peers"] = id == 501 ? [["id": 601, "display": "Edge-router uplink", "device": ["id": 303, "name": "Edge-router"]]] : []
            record["link_peers_type"] = id == 501 ? "dcim.interface" : NSNull()
            record["connected_endpoints"] = record["link_peers"]
            record["connected_endpoints_type"] = record["link_peers_type"]
            record["connected_endpoints_reachable"] = id == 501
        }
        record = FixtureDeletions.completeInterface(record, physical: !virtual)
        if id == 503 || id == 803 { record["mode"] = ["value": "access", "label": "Access"]; record["untagged_vlan"] = ["id": 1, "name": "Documentation VLAN"] }
        return record
    }
    private static func termination(_ id: Int) -> [String: Any] {
        ["object_type": "dcim.interface", "object_id": id, "object": ["id": id, "display": id == 501 ? "Core-switch eth0" : "Edge-router uplink"]]
    }
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
