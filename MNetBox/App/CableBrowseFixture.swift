#if DEBUG
import Foundation

enum CableBrowseFixture {
    static var rows: [[String: Any]] {
        func termination(_ id: Int, device: Int) -> [String: Any] {
            ["object_type": "dcim.interface", "object_id": id, "object": ["id": id, "name": "eth0", "display": "eth0", "device": ["id": device, "name": device == 301 ? "router-docs" : "peer-docs"]]]
        }
        return (701...704).map { id in
            ["id": id, "display": "Cable #\(id)", "label": id == 701 ? "Uplink-A" : "Documentation-\(id)", "type": "cat6", "status": ["value": id == 703 ? "planned" : "connected", "label": id == 703 ? "Planned" : "Connected"], "length": "2.50", "length_unit": ["value": "m", "label": "Meters"], "description": "Synthetic cable", "comments": "", "color": "2196f3", "tenant": NSNull(), "bundle": NSNull(), "a_terminations": [termination(501, device: 301)], "b_terminations": id == 702 ? [] : id == 701 ? [termination(601, device: 302), ["object_type": "dcim.frontport", "object_id": 602, "object": ["id": 602, "display": "Patch-panel port", "device": ["id": 302, "name": "peer-docs"]]]] : [termination(601, device: 302)]]
        }
    }
    static func response(_ url: URL) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.path.hasPrefix("/api/dcim/cables/") else { return nil }
        func json(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }; return text }
        if let id = Int(url.lastPathComponent) { guard let row = rows.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }; return (200, json(row)) }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        let filtered = rows.filter { row in
            if let status = value("status"), status != (row["status"] as? [String: Any])?["value"] as? String { return false }
            if value("unterminated") == "true", !(row["a_terminations"] as? [[String: Any]] ?? []).isEmpty, !(row["b_terminations"] as? [[String: Any]] ?? []).isEmpty { return false }
            if let device = value("device_id").flatMap(Int.init), !((row["a_terminations"] as? [[String: Any]] ?? []) + (row["b_terminations"] as? [[String: Any]] ?? [])).contains(where: { (($0["object"] as? [String: Any])?["device"] as? [String: Any])?["id"] as? Int == device }) { return false }
            let q = value("q") ?? ""
            return q.isEmpty || [row["label"] as? String ?? "", row["description"] as? String ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
        }
        let offset = Int(value("offset") ?? "0") ?? 0, limit = min(2, Int(value("limit") ?? "50") ?? 50)
        var next: Any = NSNull()
        if offset + limit < filtered.count { var following = parts; following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]; next = following.url?.absoluteString ?? "" }
        return (200, json(["count": filtered.count, "next": next, "results": Array(filtered.dropFirst(offset).prefix(limit))]))
    }
}
#endif
