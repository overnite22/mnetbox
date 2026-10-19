#if DEBUG
import Foundation
final class FixtureInterfaceCreations: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [InterfaceKind: [[String: Any]]] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let kind = [InterfaceKind.physical, .virtual].first(where: { (URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? "").hasPrefix("/api/" + $0.path) }) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if request.httpMethod == "POST" {
            guard let data = requestBody(request), let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let parent = body[kind == .physical ? "device" : "virtual_machine"] as? Int,
                  let name = body["name"] as? String, let enabled = body["enabled"] as? Bool,
                  let description = body["description"] as? String else { return (400, "{}") }
            var row: [String: Any] = ["id": 1001 + (records[kind]?.count ?? 0), "name": name, "display": name, "enabled": enabled,
                "mtu": body["mtu"] ?? NSNull(), "description": description,
                kind == .physical ? "device" : "virtual_machine": ["id": parent, "name": "Synthetic parent"]]
            if kind == .physical, let type = body["type"] as? String { row["type"] = ["value": type, "label": type] }
            row = FixtureDeletions.completeInterface(row, physical: kind == .physical)
            records[kind, default: []].append(row)
            guard let encoded = try? JSONSerialization.data(withJSONObject: row), let text = String(data: encoded, encoding: .utf8) else { return (500, "{}") }
            return (201, text)
        }
        return ComponentFixture.response(url, extra: records[kind] ?? [])
    }
}
#endif
