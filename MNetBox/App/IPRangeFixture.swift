#if DEBUG
import Foundation

enum IPRangeFixture {
    static func response(_ url: URL) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.path.hasPrefix("/api/ipam/ip-ranges/") else { return nil }
        func row(_ id: Int, _ start: String, _ end: String, _ family: Int) -> [String: Any] {
            ["id": id, "start_address": start, "end_address": end, "family": ["value": family, "label": "IPv\(family)"], "vrf": NSNull(), "tenant": NSNull(), "role": NSNull(), "status": ["value": "active", "label": "Active"], "description": "Synthetic range", "comments": "Range notes", "tags": [], "mark_populated": false, "mark_utilized": false]
        }
        let rows = [row(91, "198.51.100.10/24", "198.51.100.20/24", 4), row(92, "203.0.113.10/24", "203.0.113.30/24", 4), row(93, "2001:db8::10/64", "2001:db8::20/64", 6)]
        func reply(_ value: Any) -> (Int, String)? {
            guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return nil }
            return (200, text)
        }
        if let id = Int(url.lastPathComponent) { return rows.first { $0["id"] as? Int == id }.flatMap(reply) ?? (404, "{}") }
        let items = parts.queryItems ?? []
        func value(_ key: String) -> String? { items.first { $0.name == key }?.value }
        let rowsToShow = rows.filter { row in
            if let family = value("family"), family != String((row["family"] as? [String: Any])?["value"] as? Int ?? 0) { return false }
            if let vrf = value("vrf_id"), vrf != "null" { return false }
            if value("tenant_id") != nil { return false }
            let search = value("q") ?? ""
            return search.isEmpty || [row["start_address"] as? String ?? "", row["end_address"] as? String ?? "", row["description"] as? String ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
        }
        let offset = max(0, Int(value("offset") ?? "0") ?? 0)
        let limit = 2
        var next: Any = NSNull()
        if offset + limit < rowsToShow.count {
            var following = parts
            following.queryItems = items.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]
            guard let link = following.url?.absoluteString else { return nil }
            next = link
        }
        return reply(["count": rowsToShow.count, "next": next, "results": Array(rowsToShow.dropFirst(offset).prefix(limit))])
    }
}
#endif
