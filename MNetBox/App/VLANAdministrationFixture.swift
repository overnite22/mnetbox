#if DEBUG
import Foundation

// Isolated synthetic state. Never loaded by an ordinary app launch.
final class VLANAdministrationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var vlans: [[String: Any]] = VLANBrowseFixture.vlanRecords + [
        ["id": 9020, "vid": 250, "name": "Editable VLAN", "site": NSNull(), "group": NSNull(), "tenant": NSNull(), "role": NSNull(), "status": ["value": "active", "label": "Active"], "description": "Synthetic unused VLAN", "comments": "", "tags": [], "prefix_count": 0, "qinq_role": NSNull(), "qinq_svlan": NSNull(), "l2vpn_termination": NSNull()]]
    private var groups: [[String: Any]] = VLANBrowseFixture.groupRecords.map { original in
        var row = original; row["description"] = row["description"] ?? ""; row["comments"] = row["comments"] ?? ""; row["tags"] = row["tags"] ?? []; return row
    } + [["id": 9021, "name": "Editable group", "slug": "editable-group", "scope_type": NSNull(), "scope_id": NSNull(), "scope": NSNull(), "tenant": NSNull(), "vid_ranges": [[1, 4094]], "vlan_count": 0, "total_vlan_ids": 4094, "utilization": "0.0", "description": "Synthetic empty group", "comments": "", "tags": []]]
    init() {
        var group = groups.last ?? [:]; group["id"] = 9022; group["name"] = "Paged group"; group["slug"] = "paged-group"; group["vlan_count"] = 3; groups.append(group)
        for (id, vid) in [(9030, 10), (9031, 20), (9032, 4000)] {
            var row = vlans.last ?? [:]; row["id"] = id; row["vid"] = vid; row["name"] = "Member \(vid)"; row["group"] = ["id": 9022, "name": "Paged group"]; vlans.append(row)
        }
    }
    private func json(_ value: Any) -> String { (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
    private func reference(_ value: Any, path: String) -> Any {
        guard let id = value as? Int, let url = URL(string: "https://example.test/api/" + path + "\(id)/") else { return NSNull() }
        if path == "ipam/vlan-groups/", let row = groups.first(where: { $0["id"] as? Int == id }) { return ["id": id, "name": row["name"] ?? "Group"] }
        guard let reply = ComponentFixture.response(url) ?? InventoryFixture.response(url), reply.0 == 200,
              let row = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] else { return NSNull() }
        return ["id": id, "name": row["name"] ?? row["display"] ?? "Reference"]
    }
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        if let vlan = value("vlan_id"), ["prefixes", "interfaces"].contains(url.lastPathComponent) {
            let count = vlan == "1" ? 1 : 0
            return (200, json(["count": count, "next": NSNull(), "results": count == 0 ? [] : [["id": 501]]]))
        }
        let isGroup = parts.path.contains("/api/ipam/vlan-groups/"), isVLAN = parts.path.contains("/api/ipam/vlans/")
        guard isGroup || isVLAN else { return nil }
        var rows = isGroup ? groups : vlans
        if let id = Int(url.lastPathComponent) {
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            var row = rows[index]
            if request.httpMethod == "DELETE", isGroup {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                guard !vlans.contains(where: { ($0["group"] as? [String: Any])?["id"] as? Int == id }) else { return (409, "{}") }
                groups.remove(at: index); return (204, "")
            } else if request.httpMethod == "PATCH" {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"", let data = requestBody(request),
                      let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (412, "{}") }
                let permitted: Set<String> = isGroup ? ["slug", "tenant", "vid_ranges"] : ["vid", "site", "group"]
                guard (body.count == 1 && Set(body.keys).isSubset(of: permitted)) || (isGroup && Set(body.keys) == ["scope_type", "scope_id"]) else { return (400, "{}") }
                for (key, value) in body {
                    if ["site", "group", "tenant"].contains(key) { row[key] = reference(value, path: key == "site" ? "dcim/sites/" : key == "group" ? "ipam/vlan-groups/" : "tenancy/tenants/") }
                    else { row[key] = value }
                }
                if body["scope_type"] != nil { row["scope"] = reference(body["scope_id"] ?? NSNull(), path: VLANGroupScope(rawValue: body["scope_type"] as? String ?? "")?.path ?? "") }
                if let ranges = body["vid_ranges"] as? [[Int]] { row["total_vlan_ids"] = ranges.reduce(0) { $0 + $1[1] - $1[0] + 1 } }
                rows[index] = row; if isGroup { groups = rows } else { vlans = rows }
            } else if request.httpMethod != "GET" { return (405, "{}") }
            if isGroup { row["vlan_count"] = vlans.filter { ($0["group"] as? [String: Any])?["id"] as? Int == id }.count }
            return (200, json(row))
        }
        rows = rows.filter { row in
            for key in ["site", "group", "tenant", "role"] {
                if let expected = value(key + "_id"), expected != (((row[key] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null") { return false }
            }
            for key in ["name", "slug", "vid"] { if let expected = value(key), expected != (row[key] as? String ?? (row[key] as? Int).map(String.init)) { return false } }
            if let id = value("qinq_svlan_id"), id != (((row["qinq_svlan"] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null") { return false }
            let search = value("q")?.lowercased() ?? ""
            return search.isEmpty || (row["name"] as? String ?? "").lowercased().contains(search)
        }
        rows.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        if isGroup { rows = rows.map { original in var row = original; row["vlan_count"] = vlans.filter { ($0["group"] as? [String: Any])?["id"] as? Int == row["id"] as? Int }.count; return row } }
        let offset = max(0, Int(value("offset") ?? "0") ?? 0), limit = min(2, max(1, Int(value("limit") ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < rows.count { var following = parts; following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]; next = following.url?.absoluteString ?? "" }
        return (200, json(["count": rows.count, "next": next, "results": Array(rows.dropFirst(offset).prefix(limit))]))
    }
}
#endif
