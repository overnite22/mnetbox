#if DEBUG
import Foundation

// Process-local synthetic state. No real credentials or server are used.
enum FixtureDeletions {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var paths = Set<String>()
    }
    private static let state = State()
    static func isDeleted(_ url: URL, id: Int?) -> Bool {
        guard let id else { return false }
        let components = url.path.split(separator: "/")
        guard components.count >= 3 else { return false }
        let path = "/" + components.prefix(3).joined(separator: "/") + "/\(id)"
        state.lock.lock(); defer { state.lock.unlock() }
        return state.paths.contains(path)
    }
    static func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url else { return nil }
        if request.httpMethod == "GET", isDeleted(url, id: Int(url.lastPathComponent)) { return (404, "{}") }
        // Dependency checks before deletion always ask for limit=1; browsing IP ranges must reach IPRangeFixture.
        if request.httpMethod == "GET", ["ip-ranges", "fhrp-groups"].contains(url.lastPathComponent),
           URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "limit", value: "1")) == true {
            return (200, "{\"count\":0,\"next\":null,\"previous\":null,\"results\":[]}")
        }
        guard request.httpMethod == "DELETE", Int(url.lastPathComponent) != nil,
              DeletionTarget.Collection.allCases.contains(where: { url.path.hasPrefix("/api/" + $0.rawValue) }),
              request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-delete-forbidden") { return (403, "{}") }
        state.lock.lock(); state.paths.insert(url.path); state.lock.unlock()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-delete-uncertain") { return (503, "{}") }
        return (204, "")
    }
    static func completeInterface(_ input: [String: Any], physical: Bool) -> [String: Any] {
        var row = input
        for key in ["mode", "parent", "bridge", "mac_address", "primary_mac_address", "untagged_vlan", "qinq_svlan", "vlan_translation_policy", "l2vpn_termination", "vrf"] where row[key] == nil { row[key] = NSNull() }
        for key in ["mac_addresses", "tagged_vlans"] where row[key] == nil { row[key] = [] }
        for key in ["count_ipaddresses", "count_fhrp_groups"] where row[key] == nil { row[key] = 0 }
        if physical {
            for key in ["cable", "lag", "module", "wireless_link"] where row[key] == nil { row[key] = NSNull() }
            for key in ["wireless_lans", "link_peers", "connected_endpoints", "bridge_interfaces"] where row[key] == nil { row[key] = [] }
            row["_occupied"] = row["_occupied"] ?? false
            row["mark_connected"] = row["mark_connected"] ?? false
        }
        return row
    }
}
#endif
