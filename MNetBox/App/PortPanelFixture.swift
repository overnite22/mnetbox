#if DEBUG
import Foundation

enum PortPanelFixture {
    static func row(_ number: Int) -> [String: Any] {
        let id = 1500 + number
        return ["id": id, "name": number <= 48 ? "Gi1/0/\(number)" : "Te1/0/\(number - 48)", "device": ["id": 301, "name": "Core-switch"], "enabled": number % 7 != 0, "type": ["value": number <= 48 ? "1000base-t" : "10gbase-x-sfpp", "label": number <= 48 ? "1000BASE-T" : "SFP+"], "cable": number % 3 == 0 ? NSNull() : ["id": 7000 + number], "description": "Synthetic switch port", "_occupied": number % 3 != 0, "mark_connected": false]
    }
    static func response(_ request: URLRequest) -> (Int, String)? {
        guard request.httpMethod == "GET", let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), url.path.hasPrefix("/api/dcim/") else { return nil }
        func json(_ object: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
        let family = PortPanelFamily.allCases.first { url.path == "/api/" + $0.path.dropLast() || url.path == "/api/" + $0.path }
        if let family, family != .interfaces {
            if family == .console || family == .power { return DevicePortsFixture.response(request) }
            return (200, json(["count": 0, "next": NSNull(), "previous": NSNull(), "results": []]))
        }
        guard url.path == "/api/dcim/interfaces" || url.path.hasPrefix("/api/dcim/interfaces/") else { return nil }
        if let id = Int(url.lastPathComponent), (1501...1554).contains(id) { return (200, json(row(id - 1500))) }
        let items = parts.queryItems ?? []
        let q = items.first { $0.name == "q" }?.value?.lowercased() ?? ""
        let rows = (1...54).map(row).filter { q.isEmpty || ($0["name"] as? String ?? "").lowercased().contains(q) }
        let offset = Int(items.first { $0.name == "offset" }?.value ?? "0") ?? 0
        guard offset >= 0 else { return (400, "{}") }
        parts.path = "/api/dcim/interfaces/"; parts.queryItems = items.filter { $0.name != "offset" } + [.init(name: "offset", value: String(offset + 50))]
        let next: Any = offset + 50 < rows.count ? (parts.url?.absoluteString ?? "") : NSNull()
        return (200, json(["count": rows.count, "next": next, "previous": NSNull(), "results": Array(rows.dropFirst(offset).prefix(50))]))
    }
}
#endif
