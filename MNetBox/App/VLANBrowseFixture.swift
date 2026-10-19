#if DEBUG
import Foundation

enum VLANBrowseFixture {
    static func response(_ url: URL) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let groups = parts.path.contains("/api/ipam/vlan-groups/")
        guard groups || parts.path.contains("/api/ipam/vlans/") else { return nil }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first(where: { $0.name == key })?.value }
        var records = groups ? groupRecords : vlanRecords
        if let id = Int(url.lastPathComponent) {
            guard let record = records.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            return (200, json(record))
        }
        records = records.filter { row in
            for key in ["site", "group", "tenant", "role"] {
                if let selected = value(key + "_id"), selected != (((row[key] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null") { return false }
            }
            if let status = value("status"), status != (row["status"] as? [String: Any])?["value"] as? String { return false }
            let search = value("q")?.lowercased() ?? ""
            return search.isEmpty || (row["name"] as? String ?? "").lowercased().contains(search) || search == (row["vid"] as? Int).map(String.init)
        }
        if value("ordering") == "id" { records.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) } }
        else if !groups { records.sort { ($0["vid"] as? Int ?? 0, $0["id"] as? Int ?? 0) < ($1["vid"] as? Int ?? 0, $1["id"] as? Int ?? 0) } }
        else { records.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") } }
        let offset = max(0, Int(value("offset") ?? "0") ?? 0)
        let limit = min(2, max(1, Int(value("limit") ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < records.count {
            var following = parts
            following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": records.count, "next": next, "previous": NSNull(), "results": Array(records.dropFirst(offset).prefix(limit))]))
    }
    static var vlanRecords: [[String: Any]] {
        let rows: [(Int, Int, String, Int?, Int?)] = [(1, 100, "Documentation VLAN", nil, nil), (21, 100, "Global management", nil, nil),
         (22, 200, "Paris servers", 101, 31), (23, 300, "Other site", 102, 32), (24, 200, "Cluster servers", nil, 33)]
        return rows.map { id, vid, name, site, group in
            ["id": id, "vid": vid, "name": name, "site": site.map { ["id": $0, "name": $0 == 101 ? "Example Paris" : "Other"] } as Any? ?? NSNull(),
             "group": group.map { ["id": $0, "name": $0 == 31 ? "Paris VLANs" : $0 == 32 ? "Rack VLANs" : "Cluster VLANs"] } as Any? ?? NSNull(),
             "tenant": NSNull(), "role": ["id": 1, "name": "LAN"], "status": ["value": "active", "label": "Active"],
             "l2vpn_termination": NSNull(), "qinq_role": NSNull(), "qinq_svlan": NSNull(), "description": "Synthetic VLAN", "comments": "Documentation fixture", "tags": [], "prefix_count": id == 1 ? 7 : 0]
        }
    }
    static var groupRecords: [[String: Any]] {
        [(31, "Paris VLANs", "dcim.site", 101, "Example Paris"), (32, "Rack VLANs", "dcim.rack", 201, "Rack A"), (33, "Cluster VLANs", "virtualization.cluster", 9, "Example cluster")].map { id, name, type, scope, title in
            ["id": id, "name": name, "slug": "group-\(id)", "scope_type": type, "scope_id": scope, "scope": ["id": scope, "name": title], "tenant": NSNull(), "vid_ranges": [[100, 299], [400, 499]], "total_vlan_ids": 300, "utilization": "0.3333", "vlan_count": 1, "description": "Synthetic group", "comments": "", "tags": []]
        } + [["id": 34, "name": "Global VLANs", "slug": "group-34", "scope_type": NSNull(), "scope_id": NSNull(), "scope": NSNull(), "tenant": NSNull(), "vid_ranges": [[1, 4094]], "total_vlan_ids": 4094, "utilization": "0.0", "vlan_count": 0]]
    }
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
