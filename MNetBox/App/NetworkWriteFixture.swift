#if DEBUG
import Foundation

final class NetworkWriteFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var groups = VLANBrowseFixture.groupRecords
    private var vlans = VLANBrowseFixture.vlanRecords
    private var primary = ["dcim.interface-501": 11, "virtualization.vminterface-801": 13]
    private var macs: [[String: Any]] = [
        ["id": 11, "mac_address": "02:00:00:00:00:01", "display": "02:00:00:00:00:01", "assigned_object_type": "dcim.interface", "assigned_object_id": 501, "assigned_object": ["id": 501, "name": "eth0"], "is_primary": true, "description": "Primary fixture", "comments": ""],
        ["id": 12, "mac_address": "02:00:00:00:00:02", "display": "02:00:00:00:00:02", "assigned_object_type": "dcim.interface", "assigned_object_id": 501, "assigned_object": ["id": 501, "name": "eth0"], "is_primary": false, "description": "Secondary fixture", "comments": ""],
        ["id": 13, "mac_address": "02:00:00:00:00:03", "display": "02:00:00:00:00:03", "assigned_object_type": "virtualization.vminterface", "assigned_object_id": 801, "assigned_object": ["id": 801, "name": "ens18"], "is_primary": true, "description": "VM fixture", "comments": ""],
        ["id": 14, "mac_address": "02:00:00:00:00:02", "display": "02:00:00:00:00:02", "assigned_object_type": NSNull(), "assigned_object_id": NSNull(), "assigned_object": NSNull(), "is_primary": false, "description": "Unassigned reused address", "comments": ""]]
    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private func reference(_ value: Any, path: String) -> Any {
        if path == "ipam/vlan-groups/", let id = value as? Int { return groups.first(where: { $0["id"] as? Int == id }) ?? NSNull() as Any }
        guard let id = value as? Int, let url = URL(string: "https://example.test/api/" + path + "\(id)/"), let result = ComponentFixture.response(url) ?? InventoryFixture.response(url),
              let data = result.1.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return object
    }
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let isMAC = parts.path.hasPrefix("/api/dcim/mac-addresses/")
        let isGroup = parts.path.hasPrefix("/api/ipam/vlan-groups/")
        let isVLAN = parts.path.hasPrefix("/api/ipam/vlans/")
        let kind: InterfaceKind? = parts.path.hasPrefix("/api/dcim/interfaces/") ? .physical : parts.path.hasPrefix("/api/virtualization/interfaces/") ? .virtual : nil
        let id = Int(url.lastPathComponent)
        let payload = requestBody(request).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        func primaryKey(_ row: [String: Any]) -> String { "\(row["assigned_object_type"] as? String ?? "")-\(row["assigned_object_id"] as? Int ?? 0)" }
        func currentMAC(_ row: [String: Any]) -> [String: Any] {
            var value = row; value["is_primary"] = primary[primaryKey(row)] == row["id"] as? Int; return value
        }
        if let kind, id == nil, let selected = parts.queryItems?.first(where: { $0.name == "primary_mac_address_id" })?.value.flatMap(Int.init) {
            let ids = primary.filter { $0.key.hasPrefix(kind.rawValue + "-") && $0.value == selected }.keys.compactMap { Int($0.split(separator: "-").last ?? "") }
            return (200, json(["count": ids.count, "next": NSNull(), "results": ids.prefix(1).map { ["id": $0] }]))
        }
        if let kind, let id, let original = ComponentFixture.response(url), var object = (try? JSONSerialization.jsonObject(with: Data(original.1.utf8))) as? [String: Any] {
            let key = "\(kind.rawValue)-\(id)"
            if request.httpMethod == "PATCH", let payload, Set(payload.keys) == ["primary_mac_address"] {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                if let mac = payload["primary_mac_address"] as? Int {
                    guard macs.contains(where: { $0["id"] as? Int == mac && primaryKey($0) == key }) else { return (400, "{}") }
                    primary[key] = mac
                } else if payload["primary_mac_address"] is NSNull { primary.removeValue(forKey: key) }
                else { return (400, "{}") }
            } else if request.httpMethod != "GET" { return nil }
            object["primary_mac_address"] = macs.first(where: { $0["id"] as? Int == primary[key] }) ?? NSNull() as Any
            object["mac_addresses"] = macs.filter { primaryKey($0) == key }.map(currentMAC)
            return (200, json(object))
        }
        guard isMAC || isVLAN || isGroup else { return nil }
        if request.httpMethod == "POST", let payload {
            var row = payload
            row["id"] = isMAC ? 1000 + macs.count : isGroup ? 1000 + groups.count : 1000 + vlans.count
            if isMAC {
                guard let address = payload["mac_address"] as? String else { return (400, "{}") }
                row["display"] = address; row["is_primary"] = false
                let type = payload["assigned_object_type"] as? String ?? ""
                row["assigned_object"] = reference(payload["assigned_object_id"] ?? NSNull(), path: type == "dcim.interface" ? "dcim/interfaces/" : "virtualization/interfaces/")
                macs.append(row)
            } else if isGroup {
                row["scope"] = reference(payload["scope_id"] ?? NSNull(), path: VLANGroupScope(rawValue: payload["scope_type"] as? String ?? "")?.path ?? "")
                row["tenant"] = reference(payload["tenant"] ?? NSNull(), path: "tenancy/tenants/")
                row["vlan_count"] = 0; row["tags"] = []; groups.append(row)
            } else {
                for (key, path) in [("site", "dcim/sites/"), ("group", "ipam/vlan-groups/"), ("tenant", "tenancy/tenants/"), ("role", "ipam/roles/")] { row[key] = reference(payload[key] ?? NSNull(), path: path) }
                row["status"] = ["value": payload["status"] ?? "active", "label": "Active"]
                row["l2vpn_termination"] = NSNull(); row["qinq_role"] = NSNull(); row["qinq_svlan"] = NSNull(); row["tags"] = []; row["prefix_count"] = 0
                vlans.append(row)
            }
            return (201, json(row))
        }
        if let id {
            var rows = isMAC ? macs : isGroup ? groups : vlans
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            var row = rows[index]
            if request.httpMethod == "DELETE", !isGroup {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                rows.remove(at: index); if isMAC { macs = rows } else { vlans = rows }
                return (204, "")
            }
            if request.httpMethod == "PATCH", let payload {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                if isMAC, Set(payload.keys) == ["assigned_object_type", "assigned_object_id"] {
                    guard currentMAC(row)["is_primary"] as? Bool == false else { return (400, "{}") }
                    row["assigned_object_type"] = payload["assigned_object_type"]; row["assigned_object_id"] = payload["assigned_object_id"]
                    if let type = payload["assigned_object_type"] as? String { row["assigned_object"] = reference(payload["assigned_object_id"] ?? NSNull(), path: type == "dcim.interface" ? "dcim/interfaces/" : "virtualization/interfaces/") }
                    else { row["assigned_object"] = NSNull() }
                } else if payload.count == 1, let entry = payload.first {
                    if entry.key == "status" { row[entry.key] = ["value": entry.value, "label": entry.value] }
                    else if entry.key == "tenant" || entry.key == "role" { row[entry.key] = reference(entry.value, path: entry.key == "role" ? "ipam/roles/" : "tenancy/tenants/") }
                    else { row[entry.key] = entry.value }
                } else { return (400, "{}") }
                rows[index] = row; if isMAC { macs = rows } else if isGroup { groups = rows } else { vlans = rows }
            }
            return (200, json(isMAC ? currentMAC(row) : row))
        }
        let query = parts.queryItems ?? []
        func value(_ key: String) -> String? { query.first(where: { $0.name == key })?.value }
        var rows = isMAC ? macs.map(currentMAC) : isGroup ? groups : vlans
        rows = rows.filter { row in
            if isMAC {
                for (filter, type) in [("interface_id", "dcim.interface"), ("vminterface_id", "virtualization.vminterface")] {
                    if let selected = value(filter), (row["assigned_object_type"] as? String != type || String(row["assigned_object_id"] as? Int ?? 0) != selected) { return false }
                }
                if let selected = value("mac_address"), row["mac_address"] as? String != selected { return false }
            } else if isGroup {
                for key in ["name", "slug"] { if let selected = value(key), row[key] as? String != selected { return false } }
            } else {
                if let selected = value("qinq_svlan_id"), (row["qinq_svlan"] as? [String: Any])?["id"] as? Int != Int(selected) { return false }
                for key in ["site", "group", "tenant", "role"] {
                    if let selected = value(key + "_id"), selected != (((row[key] as? [String: Any])?["id"] as? Int).map(String.init) ?? "null") { return false }
                }
                if let selected = value("vid"), row["vid"] as? Int != Int(selected) { return false }
                if let selected = value("name"), row["name"] as? String != selected { return false }
            }
            if let search = value("q"), !search.isEmpty {
                return [row[isMAC ? "mac_address" : "name"] as? String ?? "", row["description"] as? String ?? ""].contains(where: { $0.localizedCaseInsensitiveContains(search) })
            }
            return true
        }
        rows.sort { ($0["id"] as? Int ?? 0) < ($1["id"] as? Int ?? 0) }
        let offset = Int(value("offset") ?? "0") ?? 0, limit = min(2, Int(value("limit") ?? "2") ?? 2)
        var next: Any = NSNull()
        if offset + limit < rows.count {
            var following = parts; following.queryItems = query.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + limit))]
            next = following.url?.absoluteString ?? ""
        }
        return (200, json(["count": rows.count, "results": Array(rows.dropFirst(offset).prefix(limit)), "next": next, "previous": NSNull()]))
    }
}
#endif
