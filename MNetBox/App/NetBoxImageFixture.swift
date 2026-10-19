#if DEBUG
import Foundation
import CoreGraphics
import ImageIO

enum NetBoxImageFixture {
    static var png: Data {
        guard let context = CGContext(data: nil, width: 800, height: 240, bitsPerComponent: 8, bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        context.setFillColor(CGColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 800, height: 240))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1)); context.fill(CGRect(x: 30, y: 55, width: 740, height: 120))
        for i in 0..<12 {
            context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.95, alpha: 1)); context.fill(CGRect(x: 70 + i * 45, y: 90, width: 28, height: 35))
            context.setFillColor(CGColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 75 + i * 45, y: 80, width: 7, height: 5))
        }
        let data = NSMutableData()
        guard let image = context.makeImage(), let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return Data() }
        CGImageDestinationAddImage(dest, image, nil); guard CGImageDestinationFinalize(dest) else { return Data() }; return data as Data
    }
    static func response(_ url: URL) -> (Int, String)? {
        if url.path.hasSuffix("/dcim/devices/301"), let original = InventoryFixture.response(url),
           var row = (try? JSONSerialization.jsonObject(with: Data(original.1.utf8))) as? [String: Any] {
            row["device_type"] = ["id": 1, "model": "Documentation switch"]
            if let data = try? JSONSerialization.data(withJSONObject: row), let text = String(data: data, encoding: .utf8) { return (200, text) }
        }
        if url.path.contains("/api/dcim/device-types/1") { return (200, "{\"id\":1,\"model\":\"Documentation switch\",\"front_image\":\"https://example.test/media/devicetype-images/front.png\",\"rear_image\":null}") }
        if url.path.contains("/api/extras/image-attachments") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let id = Int(query.first { $0.name == "object_id" }?.value ?? "0") ?? 0
            let type = query.first { $0.name == "object_type" }?.value ?? ""
            return (200, "{\"count\":1,\"next\":null,\"results\":[{\"id\":81,\"object_type\":\"\(type)\",\"object_id\":\(id),\"parent\":{\"id\":\(id)},\"name\":\"Documentation attachment\",\"image\":\"https://example.test/media/image-attachments/fixture.png\",\"image_size\":1024}]}")
        }
        return nil
    }
}
#endif
