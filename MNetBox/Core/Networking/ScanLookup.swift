import Foundation

/// Interprets a scanned label. A link is never opened: only a device ID is extracted when the
/// link points to the configured NetBox server; anything else becomes a bounded search term.
enum ScanLookup: Equatable, Sendable {
    case device(Int)
    case search(String)

    static func interpret(_ code: String, server: URL) -> ScanLookup? {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.unicodeScalars.count <= 200,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            // Same HTTPS host and port as the configured server, device detail path only.
            guard scheme == "https", url.host?.lowercased() == server.host?.lowercased(), url.port == server.port,
                  url.user == nil, url.password == nil,
                  let match = url.path.range(of: #"/dcim/devices/(\d{1,10})/?\z"#, options: .regularExpression) else { return nil }
            let digits = url.path[match].filter(\.isNumber)
            guard let id = Int(digits), id > 0 else { return nil }
            return .device(id)
        }
        return .search(value)
    }
}
