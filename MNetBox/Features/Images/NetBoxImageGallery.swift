import SwiftUI
import ImageIO

@MainActor @Observable final class NetBoxImageModel {
    private(set) var image: UIImage?; private(set) var failed = false; private(set) var working = false
    func load(_ reference: NetBoxImageReference, loader: NetBoxImageLoader) async {
        guard !working, image == nil else { return }; working = true; failed = false; defer { working = false }
        do {
            let data = try await loader.data(reference.url); try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw APIError.invalidImage }
            image = UIImage(cgImage: thumbnail)
        } catch { if !Task.isCancelled { failed = true } }
    }
}
// A neutral checkerboard makes transparent image edges visible in either color scheme.
struct ImageTransparencyBackground: View {
    var body: some View {
        Canvas { context, size in
            for row in 0...Int(size.height / 16) {
                for column in 0...Int(size.width / 16) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: column * 16, y: row * 16, width: 16, height: 16)), with: .color(.secondary.opacity(0.12)))
                }
            }
        }.background(.background).accessibilityHidden(true)
    }
}
private struct NetBoxImageCard: View {
    let reference: NetBoxImageReference; let loader: NetBoxImageLoader
    @State private var model = NetBoxImageModel()
    @State private var expanded = false
    @State private var refresh = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = model.image {
                Button { expanded = true } label: { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 180).background(ImageTransparencyBackground()).clipShape(RoundedRectangle(cornerRadius: 16)) }
                    .buttonStyle(.plain).accessibilityLabel(reference.title).accessibilityIdentifier("netboxImage-\(reference.id)")
            } else if model.failed {
                ContentUnavailableView { Label("Image unavailable", systemImage: "photo.badge.exclamationmark") } actions: { Button("Retry") { refresh = UUID() } }.frame(height: 180)
            } else { ProgressView("Loading…").frame(maxWidth: .infinity).frame(height: 180) }
            Text(reference.title).font(.caption).foregroundStyle(.secondary)
        }.task(id: refresh) { await model.load(reference, loader: loader) }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                Group { if let image = model.image { Image(uiImage: image).resizable().scaledToFit().background(ImageTransparencyBackground()).padding().accessibilityLabel(reference.title) } }
                    .navigationTitle(reference.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { expanded = false } } }
            }
        }
    }
}
struct NetBoxImageGallery: View {
    let client: APIClient; let kind: InventoryKind; let id: Int; let deviceTypeID: Int?
    let onAdd: () -> Void
    let onDelete: (Int) -> Void
    @State private var catalog: NetBoxImageCatalog?
    @State private var loader: NetBoxImageLoader?
    @State private var failed = false
    @State private var refresh = UUID()
    var body: some View {
        Section {
            Text("NetBox images").font(.headline).accessibilityIdentifier("netboxImages")
            Button("Add image", systemImage: "photo.badge.plus") { onAdd() }.accessibilityIdentifier("addNetBoxImage")
            if let catalog, let loader {
                if catalog.images.isEmpty {
                    Label(catalog.unavailable ? "Images unavailable" : "No NetBox images", systemImage: "photo.on.rectangle.angled").foregroundStyle(.secondary)
                } else {
                    ForEach(catalog.images) { image in
                        NetBoxImageCard(reference: image, loader: loader)
                        if let attachmentID = image.attachmentID {
                            Button("Delete image", systemImage: "trash", role: .destructive) { onDelete(attachmentID) }
                                .accessibilityIdentifier("deleteNetBoxImage-\(attachmentID)")
                        }
                    }
                }
                if catalog.attachmentCount > 4 { Text("The four newest image attachments are shown. Additional images remain available in NetBox.").font(.caption).foregroundStyle(.secondary) }
                if catalog.unavailable && !catalog.images.isEmpty { Text("Some NetBox images are unavailable.").font(.caption).foregroundStyle(.secondary) }
                if catalog.unavailable { Button("Retry") { refresh = UUID() } }
            } else if failed { Label("Images unavailable", systemImage: "photo.badge.exclamationmark"); Button("Retry") { refresh = UUID() } }
            else { ProgressView("Loading…") }
            Text("Images come from NetBox attachments and device types. External media may be unavailable.").font(.caption).foregroundStyle(.secondary)
        }
        .task(id: refresh) {
            failed = false
            do {
                loader = await client.imageLoader()
                catalog = try await client.imageCatalog(kind: kind, id: id, deviceTypeID: deviceTypeID)
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
