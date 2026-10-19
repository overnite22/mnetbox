import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageUploadTarget: Sendable, Equatable {
    let kind: InventoryKind
    let id: Int
    var objectType: String { kind == .virtualMachines ? "virtualization.virtualmachine" : kind == .sites ? "dcim.site" : kind == .racks ? "dcim.rack" : "dcim.device" }
    func validate() throws { guard id > 0 else { throw APIError.invalidReference } }
}
struct PreparedUploadImage: Sendable {
    let data: Data
    let width: Int
    let height: Int
    var isPNG: Bool { data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) }
    var mimeType: String { isPNG ? "image/png" : "image/jpeg" }
    var fileExtension: String { isPNG ? "png" : "jpg" }
    static func prepare(_ sourceData: Data) throws -> Self {
        guard !sourceData.isEmpty, sourceData.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(sourceData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 20000, h <= 20000, w * h <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw APIError.invalidImage }
        let alpha = image.alphaInfo
        let preserveAlpha = [CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly].contains(alpha)
        let format = CGImageSourceGetType(source) as String? == UTType.png.identifier || preserveAlpha ? UTType.png : UTType.jpeg
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, format.identifier as CFString, 1, nil) else { throw APIError.invalidImage }
        // Encode pixels only: source EXIF/GPS, filename and other metadata are not copied.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), bytes.length <= NetBoxImagePolicy.byteLimit else { throw APIError.invalidImage }
        return .init(data: bytes as Data, width: image.width, height: image.height)
    }
    func validate() throws {
        guard NetBoxImagePolicy.validPixels(data), width > 0, height > 0, width <= 2048, height <= 2048,
              let source = CGImageSourceCreateWithData(data as CFData, nil), [UTType.jpeg.identifier, UTType.png.identifier].contains(CGImageSourceGetType(source) as String? ?? ""),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], props[kCGImagePropertyPixelWidth] as? Int == width, props[kCGImagePropertyPixelHeight] as? Int == height else { throw APIError.invalidImage }
    }
}
struct ImageUploadPlan: Sendable {
    let target: ImageUploadTarget
    let targetTitle: String
    let name: String
    let description: String
    let image: PreparedUploadImage
    func validate() throws {
        try target.validate(); try image.validate()
        guard !targetTitle.isEmpty, !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines), name.unicodeScalars.count <= 50,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidName }
        try EditableTextField.description.validate(description)
    }
    func multipart(boundary: String) throws -> Data {
        try validate()
        guard boundary.range(of: "^[A-Za-z0-9-]{10,80}$", options: .regularExpression) != nil else { throw APIError.invalidImage }
        let values = [("object_type", target.objectType), ("object_id", String(target.id)), ("name", name), ("description", description)]
        guard values.allSatisfy({ !$0.1.contains(boundary) }), image.data.range(of: Data(boundary.utf8)) == nil else { throw APIError.invalidImage }
        var body = Data()
        for (key, value) in values { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8)) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"mnetbox-photo.\(image.fileExtension)\"\r\nContent-Type: \(image.mimeType)\r\n\r\n".utf8))
        body.append(image.data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); return body
    }
}
struct ImageUploadReply: Decodable, Sendable {
    let attachment: NetBoxImageAttachment
    let description: String
    let width: Int
    let height: Int
    enum CodingKeys: String, CodingKey { case description, width = "image_width", height = "image_height" }
    init(from decoder: Decoder) throws {
        attachment = try NetBoxImageAttachment(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decode(String.self, forKey: .description); width = try c.decode(Int.self, forKey: .width); height = try c.decode(Int.self, forKey: .height)
    }
    func validate(_ plan: ImageUploadPlan, apiURL: URL) throws {
        let a = attachment
        guard a.id > 0, a.objectType == plan.target.objectType, a.objectID == plan.target.id, a.parent?.id == plan.target.id, a.name == plan.name, description == plan.description,
              a.imageSize == plan.image.data.count, width == plan.image.width, height == plan.image.height else { throw APIError.invalidResponse }
        let media = try NetBoxImagePolicy(apiURL: apiURL).url(a.image)
        let apiPath = URLComponents(url: apiURL, resolvingAgainstBaseURL: false)?.path ?? ""
        guard media.path.hasPrefix(String(apiPath.dropLast(5)) + "/media/image-attachments/") else { throw APIError.invalidResponse }
    }
}
