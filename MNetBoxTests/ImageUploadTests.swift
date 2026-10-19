import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import MNetBox

@MainActor final class ImageUploadTests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [UploadProtocol.self]
        return APIClient(credential: .init(configuration: try NetBoxConfiguration("https://\(scenario)-\(UUID().uuidString).test"), token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    private func plan(name: String = "Photo", description: String = "") throws -> ImageUploadPlan { .init(target: .init(kind: .devices, id: 301), targetTitle: "Core-switch", name: name, description: description, image: try PreparedUploadImage.prepare(NetBoxImageFixture.png)) }
    func testPreparationReencodesJPEGAndStripsGPSMetadata() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(NetBoxImageFixture.png as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)), data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.0, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary); XCTAssertTrue(CGImageDestinationFinalize(dest))
        let prepared = try PreparedUploadImage.prepare(data as Data); try prepared.validate()
        let cleaned = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(cleaned, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary]); XCTAssertEqual(prepared.width, 800); XCTAssertEqual(prepared.height, 240)
        XCTAssertEqual(CGImageSourceGetType(cleaned) as String?, UTType.jpeg.identifier)
    }
    func testPNGPreservesTransparentPixelsAndCorrectMultipartType() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); context.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
        let source = NSMutableData(), destination = try XCTUnwrap(CGImageDestinationCreateWithData(source, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let prepared = try PreparedUploadImage.prepare(source as Data); try prepared.validate(); XCTAssertTrue(prepared.isPNG)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        let output = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        output.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        let pixels = try XCTUnwrap(output.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(pixels[3], 0); XCTAssertEqual(Double(pixels[(8 * 16 + 8) * 4 + 3]), 128, accuracy: 1)
        let plan = ImageUploadPlan(target: .init(kind: .devices, id: 301), targetTitle: "Core-switch", name: "Transparent", description: "", image: prepared)
        let body = String(decoding: try plan.multipart(boundary: "Synthetic-PNG-Boundary"), as: UTF8.self)
        XCTAssertTrue(body.contains("mnetbox-photo.png")); XCTAssertTrue(body.contains("Content-Type: image/png"))
    }
    func testImageDeletionChecksExactParentAndNeverDeletesDeviceType() async throws {
        let api = try api(), upload = ImageUploadModel(client: api, target: .init(kind: .devices, id: 301))
        await upload.prepare(NetBoxImageFixture.png); await upload.review(); await upload.upload(); XCTAssertTrue(upload.uploaded)
        let wrong = DeletionModel(client: api, target: .init(collection: .imageAttachments, id: 9901, imageParent: .init(kind: .virtualMachines, id: 301)))
        await wrong.load(); XCTAssertNil(wrong.snapshot); XCTAssertNotNil(wrong.errorMessage)
        let model = DeletionModel(client: api, target: .init(collection: .imageAttachments, id: 9901, imageParent: .init(kind: .devices, id: 301)))
        await model.load(); XCTAssertNotNil(model.snapshot)
        model.confirmation = "9901"; await model.delete(); XCTAssertTrue(model.deleted)
        await model.delete()
        let catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil); XCTAssertEqual(catalog.attachmentCount, 0)
        XCTAssertThrowsError(try DeletionTarget(collection: .imageAttachments, id: 1).path)
        await api.close()
    }
    func testBoundsNameDescriptionAndMultipartWhitelist() throws {
        for name in ["", " Photo ", String(repeating: "a", count: 51), "a\r\nb"] { XCTAssertThrowsError(try plan(name: name).validate()) }
        XCTAssertThrowsError(try plan(description: String(repeating: "a", count: 201)).validate())
        XCTAssertThrowsError(try PreparedUploadImage.prepare(Data("<html>bad</html>".utf8)))
        XCTAssertThrowsError(try PreparedUploadImage.prepare(Data(count: 20 * 1024 * 1024 + 1)))
        let p = try plan(name: "Photo é", description: "Description"), boundary = "MNetBox-SyntheticBoundary"
        let bytes = try p.multipart(boundary: boundary), text = String(decoding: bytes, as: UTF8.self)
        for field in ["object_type", "object_id", "name", "description", "image"] { XCTAssertTrue(text.contains("name=\"\(field)\"")) }
        XCTAssertFalse(text.contains("Authorization")); XCTAssertTrue(text.contains("image/png")); XCTAssertNotNil(bytes.range(of: p.image.data)); XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
        XCTAssertThrowsError(try p.multipart(boundary: "bad\r\nheader"))
        XCTAssertThrowsError(try plan(name: boundary).multipart(boundary: boundary))
        XCTAssertThrowsError(try ImageUploadTarget(kind: .devices, id: 0).validate())
    }
    func testAllFourParentsUploadExactAttachmentAndRefreshCatalog() async throws {
        for (kind, id) in [(InventoryKind.devices, 301), (.virtualMachines, 401), (.sites, 101), (.racks, 201)] {
            let api = try api(), model = ImageUploadModel(client: api, target: .init(kind: kind, id: id))
            await model.prepare(NetBoxImageFixture.png); await model.review(); XCTAssertNotNil(model.reviewed)
            await model.upload(); XCTAssertTrue(model.uploaded); XCTAssertTrue(model.attempted)
            let catalog = try await api.imageCatalog(kind: kind, id: id, deviceTypeID: nil)
            XCTAssertEqual(catalog.attachmentCount, 1); XCTAssertEqual(catalog.images.first?.title, "Photo")
            await model.upload(); let after = try await api.imageCatalog(kind: kind, id: id, deviceTypeID: nil); XCTAssertEqual(after.attachmentCount, 1)
            await api.close()
        }
    }
    func testDeniedLostAndWrongRepliesRetainImageAndNeverRetry() async throws {
        for scenario in ["denied", "lost", "wrongreply", "wrongstatus"] {
            let api = try api(scenario), model = ImageUploadModel(client: api, target: .init(kind: .devices, id: 301))
            await model.prepare(NetBoxImageFixture.png); await model.review(); XCTAssertNotNil(model.reviewed)
            await model.upload(); XCTAssertFalse(model.uploaded); XCTAssertTrue(model.attempted); XCTAssertNotNil(model.errorMessage); XCTAssertNotNil(model.image)
            await model.upload(); model.back(); XCTAssertNotNil(model.reviewed)
            let catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil)
            XCTAssertEqual(catalog.attachmentCount, scenario == "denied" ? 0 : 1)
            await api.close()
        }
    }
    func testDeletionDeniedLostAndInvalidResponseNeverRetry() async throws {
        for scenario in ["deletedenied", "deletelost", "deletewrongstatus", "missingetag"] {
            let api = try api(scenario), upload = ImageUploadModel(client: api, target: .init(kind: .devices, id: 301))
            await upload.prepare(NetBoxImageFixture.png); await upload.review(); await upload.upload(); XCTAssertTrue(upload.uploaded)
            let model = DeletionModel(client: api, target: .init(collection: .imageAttachments, id: 9901, imageParent: .init(kind: .devices, id: 301)))
            await model.load()
            if scenario == "missingetag" { XCTAssertNil(model.snapshot); XCTAssertNotNil(model.errorMessage) }
            else {
                model.confirmation = "9901"; await model.delete(); XCTAssertFalse(model.deleted); XCTAssertTrue(model.attempted); XCTAssertNotNil(model.errorMessage)
                await model.delete()
            }
            let catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil)
            XCTAssertEqual(catalog.attachmentCount, scenario == "deletedenied" || scenario == "missingetag" ? 1 : 0)
            await api.close()
        }
    }
    func testInvalidReviewAndCancelSendNoImage() async throws {
        let api = try api(), model = ImageUploadModel(client: api, target: .init(kind: .devices, id: 301))
        await model.prepare(NetBoxImageFixture.png); model.name = ""; await model.review(); XCTAssertNil(model.reviewed); XCTAssertFalse(model.attempted)
        model.name = "Photo"; await model.review(); model.back(); XCTAssertNil(model.reviewed)
        let catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil); XCTAssertEqual(catalog.attachmentCount, 0)
        await api.close()
    }
    func testFreshParentRenameBlocksUploadBeforePOST() async throws {
        let api = try api("renamed"), model = ImageUploadModel(client: api, target: .init(kind: .devices, id: 301))
        await model.prepare(NetBoxImageFixture.png); await model.review(); XCTAssertNotNil(model.reviewed)
        await model.upload(); XCTAssertFalse(model.uploaded); XCTAssertEqual(model.errorMessage, APIError.conflict.localizedDescription)
        let catalog = try await api.imageCatalog(kind: .devices, id: 301, deviceTypeID: nil); XCTAssertEqual(catalog.attachmentCount, 0)
        await api.close()
    }
}
private final class UploadProtocol: URLProtocol, @unchecked Sendable {
    private static let store = UploadStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let host = url.host ?? "", post = request.httpMethod == "POST"
        if request.httpMethod == "DELETE", host.hasPrefix("deletedenied-") { deliver(url, 403, "{}"); return }
        if post, host.hasPrefix("denied-") { deliver(url, 403, "{}"); return }
        guard var reply = Self.store.response(request) else { deliver(url, 404, "{}"); return }
        if request.httpMethod == "DELETE", host.hasPrefix("deletelost-") { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        if request.httpMethod == "DELETE", host.hasPrefix("deletewrongstatus-") { reply.0 = 200 }
        if post, host.hasPrefix("lost-") { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        if post, host.hasPrefix("wrongreply-"), var row = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] { row["object_id"] = 999; reply.1 = String(decoding: (try? JSONSerialization.data(withJSONObject: row)) ?? Data(), as: UTF8.self) }
        if post, host.hasPrefix("wrongstatus-") { reply.0 = 200 }
        deliver(url, reply.0, reply.1)
    }
    private func deliver(_ url: URL, _ status: Int, _ body: String) {
        guard let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: url.host?.hasPrefix("missingetag-") == true ? ["Content-Type":"application/json"] : ["Content-Type":"application/json", "ETag":"W/\"fixture-1\""]) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class UploadStore: @unchecked Sendable {
    private let lock = NSLock(); private var fixtures: [String: ImageUploadFixture] = [:]; private var reads: [String: Int] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let host = url.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        let fixture = fixtures[host] ?? ImageUploadFixture(); fixtures[host] = fixture
        if let reply = fixture.response(request) { return reply }
        if var reply = InventoryFixture.response(url) {
            reads[host, default: 0] += 1
            if host.hasPrefix("renamed-"), reads[host, default: 0] > 1, var row = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] {
                row["name"] = "Renamed"; row["display"] = "Renamed"; reply.1 = String(decoding: (try? JSONSerialization.data(withJSONObject: row)) ?? Data(), as: UTF8.self)
            }
            return reply
        }
        return nil
    }
}
