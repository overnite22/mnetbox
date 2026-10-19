#if DEBUG
import Foundation

enum CableTraceFixture {
    static func body(host: String = "example.test") -> String {
        func port(_ kind: String, _ id: Int, _ name: String, _ device: Int) -> [String: Any] {
            ["id": id, "url": "https://\(host)/api/dcim/\(kind)/\(id)/", "name": name, "device": ["id": device, "name": device == 301 ? "Core-switch" : "Patch panel"]]
        }
        func cable(_ id: Int) -> [String: Any] { ["id": id, "label": "Link \(id)", "status": "connected", "length_unit": "m"] }
        let data: [[Any]] = [
            [[port("interfaces", 501, "eth0", 301)], cable(701), [port("rear-ports", 901, "Rear 1", 302)]],
            [[port("rear-ports", 901, "Rear 1", 302)], [], [port("front-ports", 902, "Front 1", 302)]],
            [[port("front-ports", 902, "Front 1", 302)], cable(702), [port("interfaces", 502, "eth1", 301)]]
        ]
        return (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys, .withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    static func response(_ url: URL) -> (Int, String)? {
        if ["front-ports", "rear-ports"].contains(url.deletingLastPathComponent().lastPathComponent), let id = Int(url.lastPathComponent), [901, 902].contains(id) {
            let rear = id == 901
            let row: [String: Any] = ["id": id, "name": rear ? "Rear 1" : "Front 1", "device": ["id": 302, "name": "Patch panel"], "type": ["label": "8P8C", "value": "8p8c"], "positions": 1, "description": "Synthetic patch-panel port", "cable": NSNull(), rear ? "front_ports" : "rear_ports": [["position": 1, rear ? "front_port" : "rear_port": rear ? 902 : 901, rear ? "front_port_position" : "rear_port_position": 1]]]
            return (200, (try? JSONSerialization.data(withJSONObject: row)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
        }
        guard url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/dcim/interfaces/501/trace" else { return nil }
        return (200, body(host: url.host ?? "example.test"))
    }
}
#endif
