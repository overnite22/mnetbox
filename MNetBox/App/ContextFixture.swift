#if DEBUG
import Foundation

enum ContextFixture {
    static func response(_ url: URL) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kind = ContextKind.allCases.first(where: { parts.path.hasPrefix("/api/" + $0.path) }) else { return nil }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first(where: { $0.name == key })?.value }
        var rows = records(kind)
        if let id = Int(url.lastPathComponent) {
            guard let row = rows.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            return (200, json(row))
        }
        rows = rows.filter { row in
            for key in ["site", "tenant", "group"] {
                if let selected = value(key + "_id"), selected != ((row[key] as? [String: Any])?["id"] as? Int).map(String.init) { return false }
            }
            let search = value("q")?.lowercased() ?? ""
            return search.isEmpty || ["name", "description", "rd"].contains { (row[$0] as? String ?? "").lowercased().contains(search) }
        }
        rows.sort { ($0["name"] as? String ?? "", $0["id"] as? Int ?? 0) < ($1["name"] as? String ?? "", $1["id"] as? Int ?? 0) }
        let offset = max(0, Int(value("offset") ?? "0") ?? 0)
        let limit = min(2, max(1, Int(value("limit") ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < rows.count {
            var following = parts
            following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": rows.count, "next": next, "previous": NSNull(), "results": Array(rows.dropFirst(offset).prefix(limit))]))
    }
    static func treeContains(_ kind: ContextKind, candidate: Int, root: Int) -> Bool {
        var next: Int? = candidate
        var seen: Set<Int> = []
        while let id = next, seen.insert(id).inserted {
            if id == root { return true }
            next = (records(kind).first { $0["id"] as? Int == id }?["parent"] as? [String: Any])?["id"] as? Int
        }
        return false
    }
    static func records(_ kind: ContextKind) -> [[String: Any]] {
        func reference(_ id: Int, _ name: String) -> [String: Any] { ["id": id, "name": name] }
        func row(_ id: Int, _ name: String, _ fields: [String: Any] = [:]) -> [String: Any] {
            ["id": id, "name": name, "description": "Synthetic context", "comments": "", "tags": [], "parent": NSNull(), "tenant": NSNull(), "group": NSNull(), "site": NSNull()].merging(fields) { _, new in new }
        }
        switch kind {
        case .vrfs:
            return [row(7, "Blue", ["rd": "64512:7", "enforce_unique": true, "tenant": reference(1, "Example tenant"), "import_targets": [reference(17, "64512:100")], "export_targets": []]),
                    row(8, "Blue", ["rd": "64512:8", "tenant": reference(2, "Other tenant")]), row(9, "Green")]
        case .tenants: return [row(1, "Example tenant"), row(2, "Other tenant"), row(3, "Unused tenant")]
        case .roles: return [row(1, "LAN"), row(2, "WAN")]
        case .clusters:
            return [row(9, "Example Cluster", ["type": reference(1, "Hypervisor"), "group": reference(81, "Virtualization clusters"), "tenant": reference(1, "Example tenant"), "status": ["value": "active", "label": "Active"], "scope_type": "dcim.site", "scope_id": 101, "scope": reference(101, "Example Paris"), "allocated_vcpus": "4.50", "allocated_memory": 8192, "allocated_disk": 81920]), row(10, "Other Cluster")]
        case .locations:
            return [row(61, "DC1", ["site": reference(101, "Example Paris"), "tenant": reference(1, "Example tenant")]),
                    row(62, "Server room", ["site": reference(101, "Example Paris"), "parent": reference(61, "DC1"), "tenant": reference(1, "Example tenant")]), row(63, "Other DC", ["site": reference(102, "Example Lyon")])]
        case .regions: return [row(41, "France"), row(42, "Paris", ["parent": reference(41, "France")]), row(43, "Other region")]
        case .siteGroups: return [row(51, "Europe"), row(52, "Paris sites", ["parent": reference(51, "Europe")]), row(53, "Other group")]
        case .rackGroups: return [row(71, "Production racks"), row(72, "Other racks")]
        case .clusterGroups: return [row(81, "Virtualization clusters"), row(82, "Other clusters")]
        }
    }
    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
