import SwiftUI

@MainActor @Observable final class ContextEditModel {
    let client: APIClient
    let kind: ContextKind
    let id: Int
    let field: ContextEditField
    var reference: ReferenceSelection?
    var text = ""
    private(set) var snapshot: ContextEditSnapshot?
    private(set) var reviewed: ContextEditValue?
    private(set) var working = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    init(client: APIClient, kind: ContextKind, id: Int, field: ContextEditField) { self.client = client; self.kind = kind; self.id = id; self.field = field }
    func proposal() throws -> ContextEditValue {
        let value: ContextEditValue
        if [.tenant, .group].contains(field) { value = .reference(reference) }
        else if field == .weight {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(text) else { throw APIError.invalidWeight }; value = .number(n)
        } else { value = .text(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
            let current = try await client.contextEditSnapshot(kind: kind, id: id, field: field)
            try Task.checkCancellation()
            if snapshot == nil {
                switch try current.record.value(field) {
                case .reference(let value): reference = value
                case .text(let value): text = value
                case .number(let value): text = String(value)
                }
            }
            snapshot = current; requiresReload = false
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func review() async {
        guard canReview, let snapshot else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { let value = try proposal(); try await client.checkContextEdit(snapshot, value: value); try Task.checkCancellation(); reviewed = value }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func save() async {
        guard canReview, let snapshot, let reviewed, let current = try? proposal(), current.matches(reviewed) else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { self.snapshot = try await client.updateContext(snapshot, value: reviewed); saved = true }
        catch { requiresReload = true; errorMessage = readErrorMessage(error) }
    }
}

struct ContextEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ContextEditModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case load(UUID), review(UUID), save(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, kind: ContextKind, id: Int, field: ContextEditField) { _model = State(initialValue: ContextEditModel(client: client, kind: kind, id: id, field: field)) }
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
                    Label("Change saved", systemImage: "checkmark.circle").accessibilityIdentifier("contextEditSaved")
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if let reviewed = model.reviewed {
                        Section("Before") { Text((try? snapshot.record.value(model.field).display) ?? "—") }
                        Section("After") { Text(reviewed.display) }
                        Text("This changes only the selected field on the server.")
                        Button("Confirm change") { operation = .save(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("contextEditConfirm")
                        Button("Back to editing") { model.back() }.disabled(model.working)
                    } else {
                        Section(model.field.title) {
                            if [.tenant, .group].contains(model.field) {
                                NavigationLink { ReferencePickerView(client: model.client, path: model.field.path, title: model.field.title, selection: $model.reference, emptyTitle: "None") } label: {
                                    DetailField(title: model.field.title, value: model.reference?.title ?? L10n.text("None"))
                                }.accessibilityIdentifier("contextEditReference")
                            } else {
                                TextField(model.field.title, text: $model.text, axis: model.field == .comments || model.field == .description ? .vertical : .horizontal).focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("contextEditDraft")
                                if model.field == .weight { Text("Weight controls display ordering, not network routing.").font(.caption) }
                            }
                            if let error = model.validationMessage { StatusMessage(message: error) }
                            Button("Review change") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("contextEditReview")
                        }.disabled(model.working)
                    }
                }
                if model.requiresReload {
                    Text("Reload before trying again. Your draft is kept. If the connection failed, check the current value: the change may already have been saved.")
                    Button("Reload current value") { operation = .load(UUID()) }.accessibilityIdentifier("contextEditReload")
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
