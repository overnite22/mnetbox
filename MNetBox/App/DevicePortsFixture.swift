#if DEBUG
import Foundation

enum DevicePortsFixture {
    static func response(_ request: URLRequest) -> (Int, String)? {
        guard request.httpMethod == "GET", let url = request.url else { return nil }
        guard let kind = DevicePortKind.allCases.first(where: { url.path == "/api/" + String($0.path.dropLast()) || url.path.hasPrefix("/api/" + $0.path) }) else { return nil }
        func row(_ id: Int) -> [String: Any] {
            var row: [String: Any] = ["id": id, "name": kind == .console && id == 1201 ? "Console A" : "Port \(id)", "device": ["id": 301, "name": "Core-switch"], "type": ["label": "Synthetic connector"], "description": "Synthetic port", "cable": NSNull(), "maximum_draw": 250, "allocated_draw": 100]
            if let passive = kind.passive { row["positions"] = 1; row[passive == .front ? "rear_ports" : "front_ports"] = [] }
            return row
        }
        func json(_ object: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
        if url.path.hasSuffix("/trace/") || url.path.hasSuffix("/trace") {
            let id = Int(url.deletingLastPathComponent().lastPathComponent) ?? 1201
            var endpoint = row(id); endpoint["url"] = "https://\(url.host ?? "example.test")/api/\(kind.path)\(id)/"
            return (200, json([[[endpoint], [], []]]))
        }
        if let id = Int(url.lastPathComponent) { return (200, json(row(id))) }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = parts?.queryItems ?? []
        let more = items.contains { $0.name == "offset" && $0.value == "50" }
        parts?.path = "/api/" + kind.path
        parts?.queryItems = items.filter { $0.name != "offset" } + [.init(name: "offset", value: "50")]
        let next: Any = more ? NSNull() : (parts?.url?.absoluteString ?? "")
        return (200, json(["count": 51, "next": next, "results": more ? [row(1251)] : (1201...1250).map(row)]))
    }
}
#endif
