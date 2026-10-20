#if DEBUG
import Foundation

// Synthetic state only. Never present in Release and never contacts a real server.
final class FixtureIPAMCreations: @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [[String: Any]] = []
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kind = [IPAMKind.prefixes, .ipAddresses].first(where: { parts.path.hasPrefix("/api/" + $0.path) }) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let key = kind == .prefixes ? "prefix" : "address"
        let records = objects.filter { $0[key] != nil && !FixtureDeletions.isDeleted(url, id: $0["id"] as? Int) }
        let collection = parts.path == "/api/" + kind.path
        if request.httpMethod == "POST" {
            guard collection, let data = requestBody(request),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let primary = payload[key] as? String, let status = payload["status"] as? String,
                  let cidr = try? IPAMCIDR(primary, network: kind == .prefixes) else { return (400, "{}") }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-create-forbidden") { return (403, "{}") }
            let object = record(kind: kind, cidr: cidr, payload: payload, status: status, id: 9001 + objects.count)
            objects.append(object)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-create-uncertain") { return (503, "{}") }
            return (201, json(object))
        }
        guard request.httpMethod == "GET" else { return nil }
        if !collection {
            if let id = Int(url.lastPathComponent), let object = records.first(where: { $0["id"] as? Int == id }) { return (200, json(object)) }
            return nil
        }
        let query = parts.queryItems ?? []
        if let primary = query.first(where: { $0.name == key })?.value {
            let text = primary.contains("/") ? primary : primary + (primary.contains(":") ? "/128" : "/32")
            guard let wanted = try? IPAMCIDR(text, network: kind == .prefixes) else { return (400, "{}") }
            let vrf = query.first(where: { $0.name == "vrf_id" })?.value.flatMap(Int.init)
            var existing = IPAMFixture.recordsForCreation(kind) + records
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-create-duplicate") {
                existing.append(record(kind: kind, cidr: wanted, payload: ["vrf": vrf.map { $0 as Any } ?? NSNull()], status: "active", id: 9999))
            }
            let matches = existing.filter { value in
                guard let current = value[key] as? String, let parsed = try? IPAMCIDR(current, network: kind == .prefixes) else { return false }
                return (value["vrf"] as? [String: Any])?["id"] as? Int == vrf
                    && (kind == .prefixes ? parsed == wanted : (parsed.bytes == wanted.bytes && parsed.family == wanted.family))
            }
            return (200, json(["count": matches.count, "next": NSNull(), "previous": NSNull(), "results": Array(matches.prefix(1))]))
        }
        return records.isEmpty ? nil : IPAMFixture.response(url, extra: records)
    }
    private func record(kind: IPAMKind, cidr: IPAMCIDR, payload: [String: Any], status: String, id: Int) -> [String: Any] {
        var record = payload
        record["id"] = id
        record[kind == .prefixes ? "prefix" : "address"] = cidr.text
        record["family"] = ["value": cidr.family, "label": "IPv\(cidr.family)"]
        record["status"] = ["value": status, "label": status.capitalized]
        for key in ["vrf", "tenant"] {
            record[key] = (payload[key] as? Int).map { ["id": $0, "name": key == "vrf" ? "Blue" : "Example tenant"] as Any } ?? NSNull()
        }
        record["description"] = payload["description"] ?? ""
        record["comments"] = payload["comments"] ?? ""
        if kind == .ipAddresses {
            record["dns_name"] = payload["dns_name"] ?? ""
            for key in ["assigned_object", "assigned_object_type", "assigned_object_id", "nat_inside"] { record[key] = NSNull() }
            if let type = payload["assigned_object_type"] as? String, let kind = InterfaceKind(rawValue: type), let id = payload["assigned_object_id"] as? Int,
               let url = URL(string: "https://example.test/api/" + kind.path + "\(id)/"), let reply = ComponentFixture.response(url), reply.0 == 200,
               let object = try? JSONSerialization.jsonObject(with: Data(reply.1.utf8)) as? [String: Any] {
                record["assigned_object_type"] = type; record["assigned_object_id"] = id; record["assigned_object"] = object
            }
            record["nat_outside"] = []
        } else { record["children"] = 0 }
        return record
    }
    private func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
