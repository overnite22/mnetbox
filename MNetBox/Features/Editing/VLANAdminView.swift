import SwiftUI

@MainActor @Observable final class VLANAdminModel {
    let client: APIClient
    let kind: VLANBrowseKind
    let id: Int
    let field: VLANAdminField
    var reference: ReferenceSelection?
    var scope = VLANGroupScope.global
    var text = ""
    private(set) var snapshot: VLANAdminSnapshot?
    private(set) var reviewed: VLANAdminValue?
    private(set) var working = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    init(client: APIClient, kind: VLANBrowseKind, id: Int, field: VLANAdminField) { self.client = client; self.kind = kind; self.id = id; self.field = field }
    func proposal() throws -> VLANAdminValue {
        let value: VLANAdminValue
        switch field {
        case .vid:
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(text) else { throw APIError.invalidVID }
            value = .vid(n)
        case .slug: value = .slug(text)
        case .ranges: value = .ranges(try VLANGroupCreationPlan.parseRanges(text))
        case .scope: value = .scope(scope, reference)
        default: value = .reference(reference)
        }
        try value.validate(field: field, kind: kind); return value
    }
    var canReview: Bool {
        guard !working, !requiresReload, !saved, let snapshot, let before = try? snapshot.record.value(field), let after = try? proposal() else { return false }
        return !before.matches(after)
    }
    var validationMessage: String? { do { _ = try proposal(); return nil } catch { return readErrorMessage(error) } }
    func load() async {
        guard !working else { return }
        working = true; errorMessage = nil; reviewed = nil
        defer { working = false }
        do {
            let current = try await client.vlanAdminSnapshot(kind: kind, id: id, field: field)
            try Task.checkCancellation()
            if snapshot == nil {
                switch try current.record.value(field) {
                case .reference(let value): reference = value
                case .scope(let type, let value): scope = type; reference = value
                case .vid(let value): text = String(value)
                case .slug(let value): text = value
                case .ranges(let values): text = values.map { "\($0[0])-\($0[1])" }.joined(separator: ", ")
                }
            }
            snapshot = current; requiresReload = false
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func review() async {
        guard canReview, let snapshot else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { let value = try proposal(); try await client.checkVLANAdministration(snapshot, value: value); try Task.checkCancellation(); reviewed = value }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func save() async {
        guard canReview, let snapshot, let reviewed, let current = try? proposal(), current.matches(reviewed) else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { self.snapshot = try await client.updateVLANAdministration(snapshot, value: reviewed); saved = true }
        catch { requiresReload = true; errorMessage = readErrorMessage(error) }
    }
}

struct VLANAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: VLANAdminModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case load(UUID), review(UUID), save(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, kind: VLANBrowseKind, id: Int, field: VLANAdminField) { _model = State(initialValue: VLANAdminModel(client: client, kind: kind, id: id, field: field)) }
    private var scopeBinding: Binding<VLANGroupScope> { Binding(get: { model.scope }, set: { model.scope = $0; model.reference = nil }) }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.snapshot?.record.row.title ?? "#\(String(model.id))").font(.headline).monospaced()
                    Text("#" + String(model.id)).font(.caption)
                }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if model.saved {
                    Label("Change saved", systemImage: "checkmark.circle").accessibilityIdentifier("vlanAdminSaved")
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if let reviewed = model.reviewed {
                        Section("Before") { Text((try? snapshot.record.value(model.field).display) ?? "—") }
                        Section("After") { Text(reviewed.display) }
                        Text("This changes only the selected field on the server.")
                        Button("Confirm change") { operation = .save(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("vlanAdminConfirm")
                        Button("Back to editing") { model.back() }.disabled(model.working)
                    } else {
                        Section(model.field.title) {
                            if [.vid, .slug, .ranges].contains(model.field) {
                                TextField(model.field.title, text: $model.text).focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("vlanAdminDraft")
                                if model.field == .ranges { Text("Example: 1-99, 200-299, 400. Every member VLAN must remain in range.").font(.caption) }
                            } else {
                                if model.field == .scope { Picker("Scope", selection: scopeBinding) { ForEach(VLANGroupScope.allCases) { Text(L10n.text($0.title)).tag($0) } }.accessibilityIdentifier("vlanAdminScope") }
                                if model.field != .scope || model.scope != .global {
                                    NavigationLink {
                                        ReferencePickerView(client: model.client, path: model.field == .scope ? model.scope.path : model.field.path, title: model.field == .scope ? model.scope.title : model.field.title, selection: $model.reference, emptyTitle: "None", allowsEmpty: model.field != .scope)
                                    } label: {
                                        HStack { Text(model.field == .scope ? L10n.text(model.scope.title) : model.field.title); Spacer(); Text(model.reference?.title ?? L10n.text("None")).foregroundStyle(.secondary) }
                                    }.id(model.scope).accessibilityIdentifier("vlanAdminReference")
                                }
                            }
                            if model.kind == .vlans { Text("VLAN identity changes require no visible dependencies. Switch configuration is never changed.").font(.caption) }
                            if model.field == .scope { Text("Changing scope requires an empty group. Member VLANs are never moved automatically.").font(.caption) }
                            if let error = model.validationMessage { StatusMessage(message: error) }
                            Button("Review change") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("vlanAdminReview")
                        }.disabled(model.working)
                    }
                }
                if model.requiresReload {
                    Text("Reload before trying again. Your draft is kept. If the connection failed, check the current value: the change may already have been saved.")
                    Button("Reload current value") { operation = .load(UUID()) }.accessibilityIdentifier("vlanAdminReload")
                } else if model.snapshot == nil && !model.working { Button("Retry") { operation = .load(UUID()) } }
                if model.working { ProgressView("Loading…") }
            }.navigationTitle(model.field.title).navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar {
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(model.working) }
            }.interactiveDismissDisabled(model.working)
            .task(id: operation) { switch operation { case .load: await model.load(); case .review: await model.review(); case .save: await model.save() } }
        }
    }
}
