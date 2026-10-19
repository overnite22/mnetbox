import Foundation
import ImageIO

struct NetBoxImageReference: Sendable, Identifiable {
    let id: String; let title: String; let url: URL
    var attachmentID: Int? = nil
}
struct NetBoxImageCatalog: Sendable {
    let images: [NetBoxImageReference]; let attachmentCount: Int
    let unavailable: Bool
}
struct NetBoxImagePolicy: Sendable {
    let apiURL: URL
    // Authorization is confined to NetBox's two native image directories; no cookies or redirects.
    func url(_ text: String) throws -> URL {
        guard var root = URLComponents(url: apiURL, resolvingAgainstBaseURL: false), root.path.hasSuffix("/api/") else { throw APIError.invalidImage }
        root.path = String(root.path.dropLast(5)) + "/media/"; root.query = nil; root.fragment = nil
        guard let media = root.url, let url = URL(string: text, relativeTo: media)?.absoluteURL,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.scheme == "https", url.host == apiURL.host, url.port == apiURL.port,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.hasPrefix(root.percentEncodedPath),
              !["%2e", "%2f", "%5c", "%25"].contains(where: { parts.percentEncodedPath.lowercased().contains($0) }), !parts.path.contains(".."), !parts.path.contains("\\") else { throw APIError.invalidImage }
        return url
    }
    func request(_ url: URL, credential: Credential? = nil) throws -> URLRequest {
        let checked = try self.url(url.absoluteString)
        var request = URLRequest(url: checked, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"; request.setValue("image/png, image/jpeg, image/webp, image/gif", forHTTPHeaderField: "Accept")
        if let credential {
            guard credential.configuration.baseURL == apiURL else { throw APIError.invalidImage }
            guard let apiParts = URLComponents(url: apiURL, resolvingAgainstBaseURL: false), apiParts.path.hasSuffix("/api/") else { throw APIError.invalidImage }
            let prefix = String(apiParts.path.dropLast(5)) + "/media/"
            guard ["image-attachments/", "devicetype-images/"].contains(where: { checked.path.hasPrefix(prefix + $0) }) else { throw APIError.invalidImage }
            // Reuse token validation and header format without relaxing API URL confinement.
            let authorized = try RequestBuilder(credential: credential).get("status/")
            request.setValue(authorized.value(forHTTPHeaderField: "Authorization"), forHTTPHeaderField: "Authorization")
        }
        return request
    }
    static let byteLimit = 8 * 1024 * 1024
    static func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(http.mimeType ?? ""),
              http.expectedContentLength <= byteLimit else { throw APIError.invalidImage }
    }
    static func validPixels(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= byteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 16000, h <= 16000, w * h <= 40_000_000 else { return false }
        return true
    }
}

actor NetBoxImageLoader {
    private let policy: NetBoxImagePolicy
    private let session: URLSession
    private let credential: Credential?
    init(apiURL: URL, credential: Credential? = nil, session: URLSession? = nil) {
        self.credential = credential
        policy = .init(apiURL: apiURL)
        let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    func data(_ url: URL) async throws -> Data {
        let request = try policy.request(url, credential: credential)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try NetBoxImagePolicy.validateResponse(response)
            var data = Data(); data.reserveCapacity(min(max(0, Int(response.expectedContentLength)), NetBoxImagePolicy.byteLimit))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < NetBoxImagePolicy.byteLimit else { throw APIError.invalidImage }; data.append(byte)
            }
            guard NetBoxImagePolicy.validPixels(data) else { throw APIError.invalidImage }; return data
        } catch { if Task.isCancelled { throw CancellationError() }; throw APIError.invalidImage }
    }
}

struct NetBoxImageAttachment: Decodable, Sendable {
    let id: Int; let objectType: String; let objectID: Int; let parent: NetBoxLabel?
    let name: String; let image: String; let imageSize: Int?
    enum CodingKeys: String, CodingKey { case id, parent, name, image; case objectType = "object_type", objectID = "object_id", imageSize = "image_size" }
}
struct NetBoxImagePage: Decodable, Sendable { let count: Int; let next: String?; let results: [NetBoxImageAttachment] }
struct NetBoxDeviceImages: Decodable, Sendable {
    let id: Int; let model: String; let front: String?; let rear: String?
    enum CodingKeys: String, CodingKey { case id, model, front = "front_image", rear = "rear_image" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.front), c.contains(.rear) else { throw APIError.invalidResponse }
        id = try c.decode(Int.self, forKey: .id); model = try c.decode(String.self, forKey: .model)
        front = try c.decodeIfPresent(String.self, forKey: .front); rear = try c.decodeIfPresent(String.self, forKey: .rear)
    }
}
