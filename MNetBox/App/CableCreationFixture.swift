#if DEBUG
import Foundation

final class CableCreationFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var endpointReads = 0
    private(set) var posts = 0
    var occupiedAtConfirm = false
    var statusCode = 201
    var wrongReply = false
    private var connected = false
    func response(_ request: URLRequest) -> (Int, String)? {
        lock.lock(); defer { lock.unlock() }
        guard let url = request.url else { return nil }
        func json(_ object: Any) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self) }
        if request.httpMethod == "GET", url.path.hasPrefix("/api/dcim/devices") { return InventoryFixture.response(url) }
        if request.httpMethod == "GET", url.path.hasPrefix("/api/dcim/interfaces") {
            if let id = Int(url.lastPathComponent), id == 1503 || id == 1601 {
                endpointReads += 1
                var row = id == 1503 ? PortPanelFixture.row(3) : destination()
                row["mark_connected"] = occupiedAtConfirm && endpointReads > 2
                if connected { row["cable"] = ["id": 9902]; row["_occupied"] = true }
                return (200, json(row))
            }
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if connected, parts?.queryItems?.contains(.init(name: "device_id", value: "301")) == true, let reply = PortPanelFixture.response(request),
               var page = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any], let rows = page["results"] as? [[String: Any]] {
                page["results"] = rows.map { row in
                    var updated = row
                    if row["id"] as? Int == 1503 { updated["cable"] = ["id": 9902]; updated["_occupied"] = true }
                    return updated
                }
                return (200, json(page))
            }
            if parts?.queryItems?.contains(.init(name: "device_id", value: "303")) == true {
                return (200, json(["count": 1, "next": NSNull(), "previous": NSNull(), "results": [destination()]]))
            }
        }
        if url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "api/dcim/cables", request.httpMethod == "POST" {
            posts += 1
            guard statusCode == 201 else { return (statusCode, "{}") }
            let body = (try? JSONSerialization.jsonObject(with: requestBody(request) ?? Data())) as? [String: Any] ?? [:]
            var result = body; result["id"] = wrongReply ? 0 : 9902
            result["status"] = ["value": body["status"] ?? "connected", "label": "Connected"]
            result["length"] = NSNull(); result["length_unit"] = NSNull()
            connected = true
            return (201, json(result))
        }
        return nil
    }
    private func destination() -> [String: Any] {
        ["id": 1601, "name": "eth1", "device": ["id": 303, "name": "Edge-router"], "type": ["value": "1000base-t", "label": "1000BASE-T"], "cable": NSNull(), "_occupied": false, "mark_connected": false, "enabled": true]
    }
}
#endif
