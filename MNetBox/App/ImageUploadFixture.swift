#if DEBUG
import Foundation
import ImageIO

final class ImageUploadFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [[String: Any]] = []
    private var images: [String: Data] = [:]
    private(set) var postCount = 0
    func media(_ url: URL) -> Data? { lock.lock(); defer { lock.unlock() }; return images[url.lastPathComponent] }
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, url.path.contains("/api/extras/image-attachments") else { return nil }
        lock.lock(); defer { lock.unlock() }
        func json(_ object: Any) -> String { (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
        if request.httpMethod == "POST" {
            postCount += 1
            guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="), let body = requestBody(request) else { return (400, "{}") }
            let boundary = String(type.dropFirst("multipart/form-data; boundary=".count)), delimiter = Data(("--" + boundary).utf8)
            var fields: [String: String] = [:], picture: Data?, ext = "jpg"
            var offset = 0
            while let start = body.range(of: delimiter, in: offset..<body.count), start.upperBound + 2 < body.count {
                let begin = start.upperBound + 2
                guard let end = body.range(of: delimiter, in: begin..<body.count), let headerEnd = body.range(of: Data("\r\n\r\n".utf8), in: begin..<end.lowerBound) else { break }
                let header = String(decoding: body[begin..<headerEnd.lowerBound], as: UTF8.self)
                let data = Data(body[headerEnd.upperBound..<(end.lowerBound - 2)])
                if header.contains("name=\"image\"") { let png = header.contains("filename=\"mnetbox-photo.png\"") && header.contains("image/png")
                    let jpeg = header.contains("filename=\"mnetbox-photo.jpg\"") && header.contains("image/jpeg")
                    guard png || jpeg else { return (400, "{}") }; ext = png ? "png" : "jpg"; picture = data }
                else { for name in ["object_type", "object_id", "name", "description"] where header.contains("name=\"\(name)\"") { fields[name] = String(decoding: data, as: UTF8.self) } }
                offset = end.lowerBound
            }
            guard fields.count == 4, let data = picture, let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let id = Int(fields["object_id"] ?? ""), id > 0 else { return (400, "{}") }
            let number = 9900 + postCount, filename = "upload-\(number).\(ext)"
            let row: [String: Any] = ["id": number, "object_type": fields["object_type"] ?? "", "object_id": id, "parent": ["id": id], "name": fields["name"] ?? "", "description": fields["description"] ?? "", "image": "https://\(url.host ?? "example.test")/media/image-attachments/\(filename)", "image_size": data.count, "image_width": properties[kCGImagePropertyPixelWidth] ?? 0, "image_height": properties[kCGImagePropertyPixelHeight] ?? 0]
            rows.insert(row, at: 0); images[filename] = data; return (201, json(row))
        }
        if let id = Int(url.lastPathComponent) {
            guard let index = rows.firstIndex(where: { $0["id"] as? Int == id }) else { return (404, "{}") }
            if request.httpMethod == "DELETE" {
                guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"" else { return (412, "{}") }
                let row = rows.remove(at: index)
                if let image = row["image"] as? String, let url = URL(string: image) { images.removeValue(forKey: url.lastPathComponent) }
                return (204, "")
            }
            guard request.httpMethod == "GET" else { return (405, "{}") }; return (200, json(rows[index]))
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let type = query.first { $0.name == "object_type" }?.value ?? "", id = Int(query.first { $0.name == "object_id" }?.value ?? "0") ?? 0
        let matching = rows.filter { $0["object_type"] as? String == type && $0["object_id"] as? Int == id }
        return (200, json(["count": matching.count, "next": NSNull(), "results": matching]))
    }
}
#endif
