#if DEBUG
import Foundation

final class ContextAdministrationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: [[String: Any]]] = [:]
    init() {
        for kind in [ContextKind.vrfs, .tenants, .roles] {
            records[kind.rawValue] = ContextFixture.records(kind).map { original in
                var row = original
                if kind == .vrfs { row["rd"] = row["rd"] ?? NSNull(); row["enforce_unique"] = row["enforce_unique"] ?? true; row["import_targets"] = row["import_targets"] ?? []; row["export_targets"] = row["export_targets"] ?? []; row["prefix_count"] = 0; row["ipaddress_count"] = 0 }
                else { row["slug"] = kind.rawValue + "-" + String(row["id"] as? Int ?? 0); if kind == .roles { row["weight"] = 1000; row["prefix_count"] = 0; row["vlan_count"] = 0; row["asn_count"] = 0 } else { row["device_count"] = 0; row["virtualmachine_count"] = 0; row["prefix_count"] = 0; row["vlan_count"] = 0; row["ipaddress_count"] = 0 } }
                return row
            }
        }
    }
    private func json(_ value: Any) -> String { (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if parts.path.contains("/api/tenancy/tenant-groups/") {
            let rows: [[String: Any]] = [["id": 51, "name": "Customers"], ["id": 52, "name": "Operations"]]
            if let id = Int(url.lastPathComponent) { return rows.first { $0["id"] as? Int == id }.map { (200, json($0)) } ?? (404, "{}") }
            return (200, json(["count": rows.count, "next": NSNull(), "results": rows]))
        }
        guard let kind = [ContextKind.vrfs, .tenants, .roles].first(where: { parts.path.contains("/api/" + $0.path) }) else { return nil }
        var rows = records[kind.rawValue] ?? []
        func reference(_ value: Any, group: Bool = false) -> Any {
            guard let id = value as? Int else { return NSNull() }
            if group { return ["id": id, "name": id == 51 ? "Customers" : "Operations"] }
            return (records[ContextKind.tenants.rawValue] ?? []).first { $0["id"] as? Int == id }.map { ["id": id, "name": $0["name"] ?? "Tenant"] } ?? NSNull() as Any
        }
        let body = requestBody(request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if request.httpMethod == "POST", let body {
            var row = body; row["id"] = 9400 + rows.count; row["tags"] = []
            if kind == .vrfs { row["tenant"] = reference(body["tenant"] ?? NSNull()); row["import_targets"] = []; row["export_targets"] = []; row["prefix_count"] = 0; row["ipaddress_count"] = 0 }
            if kind == .tenants { row["group"] = reference(body["group"] ?? NSNull(), group: true); for key in ["device_count", "virtualmachine_count", "prefix_count", "vlan_count", "ipaddress_count"] { row[key] = 0 } }
            if kind == .roles { row["prefix_count"] = 0; row["vlan_count"] = 0; row["asn_count"] = 0 }
            rows.append(row); records[kind.rawValue] = rows; return (201, json(row))
        }
        if let id = Int(url.lastPathComponent) {
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            var row = rows[index]
            if request.httpMethod == "DELETE" {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                rows.remove(at: index); records[kind.rawValue] = rows; return (204, "")
            }
            if request.httpMethod == "PATCH", let body, body.count == 1, let field = body.first {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                let key = field.key
                if key == "group" || key == "tenant" { row[key] = reference(field.value, group: key == "group") }
                else { row[key] = field.value }
                if key == "name" { row.removeValue(forKey: "display") }
                rows[index] = row; records[kind.rawValue] = rows
            } else if request.httpMethod != "GET" { return (405, "{}") }
            return (200, json(row))
        }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        rows = rows.filter { row in
            for key in ["name", "slug", "rd"] { if let filter = value(key), row[key] as? String != filter { return false } }
            if let tenant = value("tenant_id"), String(((row["tenant"] as? [String: Any])?["id"] as? Int) ?? 0) != tenant { return false }
            let q = value("q")?.lowercased() ?? ""; return q.isEmpty || (row["name"] as? String ?? "").lowercased().contains(q)
        }
        rows.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        let offset = max(0, Int(value("offset") ?? "0") ?? 0), limit = min(2, max(1, Int(value("limit") ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < rows.count { var following = parts; following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]; next = following.url?.absoluteString ?? "" }
        return (200, json(["count": rows.count, "next": next, "results": Array(rows.dropFirst(offset).prefix(limit))]))
    }
}
#endif
