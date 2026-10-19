#if DEBUG
import Foundation

enum InventoryFixture {
    static func response(_ url: URL) -> (Int, String)? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kind = InventoryKind.allCases.first(where: { parts.path.contains("/api/" + $0.path) }) else { return nil }
        let query = parts.queryItems ?? []
        if query.contains(URLQueryItem(name: "brief", value: "true")) { return nil }
        if parts.path.hasSuffix("/elevation/") { return elevation(parts) }
        let records = records(kind)
        if let id = Int(url.lastPathComponent) {
            guard let object = records.first(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            return (200, json(object))
        }
        let search = query.first(where: { $0.name == "q" })?.value?.lowercased() ?? ""
        let status = query.first(where: { $0.name == "status" })?.value ?? ""
        let parentSite = query.first(where: { $0.name == "site_id" })?.value.flatMap(Int.init)
        let parentRack = query.first(where: { $0.name == "rack_id" })?.value.flatMap(Int.init)
        let filtered = records.filter { record in
            for (key, field) in [("tenant_id", "tenant"), ("cluster_id", "cluster"), ("group_id", "group")] {
                if let filter = query.first(where: { $0.name == key })?.value.flatMap(Int.init) {
                    guard let relation = (record[field] as? [String: Any])?["id"] as? Int else { return false }
                    if field == "group", kind == .sites { if !ContextFixture.treeContains(.siteGroups, candidate: relation, root: filter) { return false } }
                    else if relation != filter { return false }
                }
            }
            for (key, field, tree) in [("region_id", "region", ContextKind.regions), ("location_id", "location", .locations)] {
                if let filter = query.first(where: { $0.name == key })?.value.flatMap(Int.init) {
                    guard let relation = (record[field] as? [String: Any])?["id"] as? Int, ContextFixture.treeContains(tree, candidate: relation, root: filter) else { return false }
                }
            }
            if let oob = query.first(where: { $0.name == "oob_ip_id" })?.value, oob != ((record["oob_ip"] as? [String: Any])?["id"] as? Int).map(String.init) { return false }
            let primaryMatches = ["primary_ip4", "primary_ip6"].contains { key in
                guard let address = (record[key] as? [String: Any])?["address"] as? String else { return false }
                return address.split(separator: "/").first.map(String.init) == search
            }
            let name = record["name"] as? String ?? record["display"] as? String ?? ""
            let description = record["description"] as? String ?? ""
            let s = (record["status"] as? [String: Any])?["value"] as? String ?? ""
            let site = (record["site"] as? [String: Any])?["id"] as? Int
            let rack = (record["rack"] as? [String: Any])?["id"] as? Int
            return (parentSite == nil || site == parentSite) && (parentRack == nil || rack == parentRack) && (search.isEmpty || primaryMatches || (name + " " + description).lowercased().contains(search)) && (status.isEmpty || status == s)
        }
        let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
        let limit = min(2, max(1, Int(query.first(where: { $0.name == "limit" })?.value ?? "2") ?? 2))
        var next: Any = NSNull()
        if offset + limit < filtered.count {
            var following = parts
            following.queryItems = query.filter { $0.name != "offset" } + [URLQueryItem(name: "offset", value: String(offset + limit))]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": filtered.count, "next": next, "previous": NSNull(),
                           "results": Array(filtered.dropFirst(max(0, offset)).prefix(limit))]))
    }

    private static func elevation(_ parts: URLComponents) -> (Int, String) {
        let query = parts.queryItems ?? []
        let rear = query.contains(URLQueryItem(name: "face", value: "rear"))
        let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
        let positions = [4.5, 4, 3.5, 3, 2.5, 2, 1.5, 1]
        let records: [[String: Any]] = positions.map { position in
            var row: [String: Any] = ["id": position, "name": "U\(position)", "occupied": false, "device": NSNull()]
            if position == 4.5 { row["occupied"] = true } // hidden by permissions
            if !rear && [2.0, 1.5].contains(position) {
                row["occupied"] = true
                row["device"] = ["id": 301, "display": "Core-switch"]
            }
            return row
        }
        var next: Any = NSNull()
        if offset == 0 {
            var following = parts
            following.queryItems = query + [URLQueryItem(name: "offset", value: "4")]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": 8, "next": next, "previous": NSNull(), "results": Array(records.dropFirst(offset).prefix(4))]))
    }

    private static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private static func records(_ kind: InventoryKind) -> [[String: Any]] {
        let base = (InventoryKind.allCases.firstIndex(of: kind) ?? 0) * 100 + 101
        let names: [String]
        switch kind {
        case .sites: names = ["Example Paris", "Example Lyon", "Example retired site"]
        case .racks: names = ["Rack-A", "Rack-B", "Rack-C"]
        case .devices: names = ["Core-switch", "Unnamed device", "Edge-router"]
        case .virtualMachines: names = ["monitoring-01", "web-01", "offline-01"]
        }
        return names.enumerated().map { index, name in
            let status = index == 2 ? (kind == .sites ? "retired" : kind == .racks ? "deprecated" : "offline") : "active"
            var object: [String: Any] = ["id": base + index, "name": name, "display": name,
                                         "status": ["value": status, "label": status.capitalized],
                                         "tenant": NSNull(), "description": "Example inventory", "comments": "Read-only fixture",
                                         "tags": [["name": "example"]]]
            switch kind {
            case .sites:
                object["region"] = ["id": index == 1 ? 42 : 41, "name": index == 1 ? "Paris" : "France"]
                object["group"] = ["id": index == 1 ? 52 : 51, "name": index == 1 ? "Paris sites" : "Europe"]
                object["facility"] = "Example facility"
                object["physical_address"] = "Example address, Paris"
                object["time_zone"] = "Europe/Paris"
            case .racks:
                object["site"] = ["id": 101, "name": "Example Paris"]
                object["location"] = ["id": 62, "name": "Server room"]
                object["group"] = ["id": 71, "name": "Production racks"]
                object["role"] = ["id": 1, "name": "Network"]
                object["u_height"] = 42
                object["serial"] = "TEST-RACK-\(index)"
                object["asset_tag"] = NSNull()
            case .devices:
                object["location"] = ["id": 62, "name": "Server room"]
                object["site"] = ["id": 101, "name": "Example Paris"]
                if index == 0 { object["rack"] = ["id": 201, "name": "Rack-A"] }
                else { object["rack"] = NSNull() }
                object["role"] = ["id": 1, "name": "Network"]
                object["device_type"] = ["model": "Example Switch"]
                object["position"] = 1.5
                object["face"] = ["value": "front", "label": "Front"]
                object["serial"] = "TEST-DEVICE-\(index)"
                object["platform"] = NSNull()
                object["oob_ip"] = NSNull()
                object["primary_ip6"] = NSNull()
                object["primary_ip4"] = ["id": 11, "address": "192.0.2.10/24"]
                if index == 1 { object["name"] = NSNull() }
            case .virtualMachines:
                object["cluster"] = ["id": 9, "name": "Example Cluster"]
                object["site"] = NSNull()
                object["device"] = NSNull()
                object["role"] = NSNull()
                object["platform"] = ["id": 1, "name": "Linux"]
                if index == 0 { object["vcpus"] = "1.50" }
                else { object["vcpus"] = 2 }
                object["memory"] = 2048
                object["disk"] = 40960
                object["primary_ip4"] = NSNull()
                object["primary_ip6"] = ["id": 12, "address": "2001:db8::10/64"]
            }
            return object
        }
    }
}
#endif
