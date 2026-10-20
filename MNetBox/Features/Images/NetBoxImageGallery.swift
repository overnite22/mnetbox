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
struct NetBoxImageCard: View {
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
                if catalog.attachmentCount > 4 {
                    NavigationLink { NetBoxAllImagesView(client: client, kind: kind, id: id, onDelete: onDelete) } label: {
                        Label(L10n.format("All images (%ld)", catalog.attachmentCount), systemImage: "photo.stack")
                    }.accessibilityIdentifier("allNetBoxImages")
                }
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

/// Every image attachment of one object, newest first, loaded twelve at a time.
struct NetBoxAllImagesView: View {
    let client: APIClient; let kind: InventoryKind; let id: Int
    let onDelete: (Int) -> Void
    @State private var images: [NetBoxImageReference] = []
    @State private var loader: NetBoxImageLoader?
    @State private var total = 0
    @State private var next: String?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var refresh = UUID()
    private func load(more: Bool) async {
        guard !loading else { return }
        loading = true; errorMessage = nil; defer { loading = false }
        do {
            if loader == nil { loader = await client.imageLoader() }
            let page = try await client.imageAttachments(kind: kind, id: id, next: more ? next : nil)
            let known = Set(images.map(\.id))
            images = (more ? images : []) + page.images.filter { !more || !known.contains($0.id) }
            total = page.count; next = page.next
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    var body: some View {
        List {
            if let error = errorMessage { StatusMessage(message: error); Button("Retry") { refresh = UUID() } }
            if let loader {
                ForEach(images) { image in
                    NetBoxImageCard(reference: image, loader: loader)
                    if let attachmentID = image.attachmentID {
                        Button("Delete image", systemImage: "trash", role: .destructive) { onDelete(attachmentID) }
                            .accessibilityIdentifier("deleteNetBoxImage-\(attachmentID)")
                    }
                }
            }
            if !images.isEmpty { Text(L10n.format("%ld loaded · %ld total", images.count, total)).font(.caption).foregroundStyle(.secondary) }
            if next != nil, !loading { Button("Load more") { Task { await load(more: true) } }.accessibilityIdentifier("allImagesLoadMore") }
            if loading { ProgressView("Loading…") }
        }
        .navigationTitle("All images").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(loading) }
        .task(id: refresh) { await load(more: false) }
    }
}
