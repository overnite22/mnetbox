import SwiftUI
import PhotosUI

@MainActor @Observable final class ImageUploadModel {
    let client: APIClient
    let target: ImageUploadTarget
    var name = "Photo"
    var description = ""
    private(set) var image: PreparedUploadImage?
    private(set) var reviewed: ImageUploadPlan?
    private(set) var working = false
    private(set) var attempted = false
    private(set) var uploaded = false
    private(set) var errorMessage: String?
    init(client: APIClient, target: ImageUploadTarget) { self.client = client; self.target = target }
    func prepare(_ data: Data) async {
        guard !attempted else { return }; working = true; errorMessage = nil; reviewed = nil; image = nil
        defer { working = false }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) { try PreparedUploadImage.prepare(data) }.value
            try Task.checkCancellation(); image = prepared
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func beginSelection() { guard !attempted else { return }; working = true; image = nil; reviewed = nil; errorMessage = nil }
    func selectionFailed() { working = false; image = nil; errorMessage = APIError.invalidImage.localizedDescription }
    func review() async {
        guard !working, !attempted, let image else { return }; working = true; errorMessage = nil
        defer { working = false }
        do {
            let title = try await client.imageUploadTargetTitle(target)
            let plan = ImageUploadPlan(target: target, targetTitle: title, name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: EditableTextField.description.normalized(description), image: image)
            try plan.validate(); try Task.checkCancellation(); reviewed = plan
        } catch { errorMessage = readErrorMessage(error) }
    }
    func back() { guard !working, !attempted else { return }; reviewed = nil }
    func upload() async {
        guard !working, !attempted, let reviewed else { return }; attempted = true; working = true; errorMessage = nil
        defer { working = false }
        do { _ = try await client.uploadImage(reviewed); uploaded = true }
        catch { errorMessage = readErrorMessage(error) }
    }
}
struct ImageUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ImageUploadModel
    @State private var selection: PhotosPickerItem?
    @FocusState private var focused: Bool
    @State private var operation = 0
    init(client: APIClient, target: ImageUploadTarget) { _model = State(initialValue: ImageUploadModel(client: client, target: target)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") { Text(model.client.serverDisplay).font(.caption); Text(model.target.kind.singular); Text(verbatim: "#\(model.target.id)"); if let plan = model.reviewed { Text(plan.targetTitle).font(.headline) } }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if let image = model.image, let preview = UIImage(data: image.data) {
                    Section("Image preview") { Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240).background(ImageTransparencyBackground()).clipShape(RoundedRectangle(cornerRadius: 12)); Text(L10n.format("%ld × %ld pixels", image.width, image.height)).font(.caption); Text(verbatim: image.isPNG ? "PNG" : "JPEG").font(.caption).foregroundStyle(.secondary) }
                }
                if model.uploaded {
                    Label("Image uploaded", systemImage: "checkmark.circle").accessibilityIdentifier("imageUploaded")
                    Button("Done") { dismiss() }
                } else if model.attempted {
                    Text("Upload was not confirmed. Check this object's images in NetBox before starting another upload; the image may already exist.")
                    Button("Done") { dismiss() }
                } else if let plan = model.reviewed {
                    Section("Upload preview") { DetailField(title: "Name", value: plan.name); DetailField(title: "Description", value: plan.description); Text("This adds one image attachment to the selected object in NetBox.") }
                    Button("Confirm upload") { focused = false; operation = 2 }.disabled(model.working).accessibilityIdentifier("imageUploadConfirm")
                    Button("Back to editing") { model.back() }.disabled(model.working)
                } else {
                    Section {
                        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) { Label("Choose photo", systemImage: "photo.badge.plus") }.disabled(model.working)
                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("--ui-testing-image-upload") { Button("Use synthetic image") { operation = 3 }.accessibilityIdentifier("syntheticUploadImage") }
                        #endif
                        TextField("Name", text: $model.name).focused($focused).accessibilityIdentifier("imageUploadName")
                        TextField("Description", text: $model.description).focused($focused).accessibilityIdentifier("imageUploadDescription")
                        Text("PNG transparency is preserved. Photos are resized up to 2048 pixels and location metadata is removed. The original stays in Photos.").font(.caption).foregroundStyle(.secondary)
                    }.disabled(model.working)
                    Button("Review upload") { focused = false; operation = 1 }.disabled(model.image == nil || model.working).accessibilityIdentifier("imageUploadReview")
                }
                if model.working { ProgressView("Loading…") }
            }
            .navigationTitle("Add image").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
            }
            .interactiveDismissDisabled(model.working)
            .task(id: selection) {
                guard let selection else { return }
                model.beginSelection()
                do { if let data = try await selection.loadTransferable(type: Data.self) { await model.prepare(data) } else { model.selectionFailed() } }
                catch { if !Task.isCancelled { model.selectionFailed() } }
            }
            .task(id: operation) {
                switch operation {
                case 1: await model.review(); operation = 0
                case 2: await model.upload(); operation = 0
                #if DEBUG
                case 3: await model.prepare(NetBoxImageFixture.png); operation = 0
                #endif
                default: break
                }
            }
        }
    }
}
