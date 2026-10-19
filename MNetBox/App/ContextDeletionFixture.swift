#if DEBUG
import Foundation

enum ContextDeletionFixture {
    static func response(_ request: URLRequest) -> (Int, String)? {
        guard request.httpMethod == "GET", let url = request.url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = c.queryItems ?? []
        guard ["vrf_id", "role_id"].contains(where: { key in items.contains { $0.name == key } }), items.contains(where: { $0.name == "limit" && $0.value == "1" }) else { return nil }
        return (200, "{\"count\":0,\"next\":null,\"results\":[]}")
    }
}
#endif
