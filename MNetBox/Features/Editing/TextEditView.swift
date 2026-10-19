import SwiftUI

@MainActor @Observable final class TextEditModel {
    private(set) var snapshot: TextEditSnapshot?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    var draft = ""
    private let client: APIClient
    let target: TextEditTarget
    let field: EditableTextField
    init(client: APIClient, target: TextEditTarget, field: EditableTextField = .description) {
        self.client = client; self.target = target; self.field = field
    }
    var proposedValue: String { field.normalized(draft) }
    var canSave: Bool {
        snapshot != nil && !isLoading && !isSaving && !requiresReload && !saved
            && proposedValue != snapshot?.object.value(for: field) && validationMessage == nil
    }
    var validationMessage: String? {
        do { try field.validate(proposedValue, for: target.collection); return nil }
        catch { return readErrorMessage(error) }
    }
    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let value = try await client.textSnapshot(for: target, field: field)
            try Task.checkCancellation()
            let initial = snapshot == nil
            snapshot = value; requiresReload = false
            if initial { draft = value.object.value(for: field) ?? "" }
        } catch {
            if !(error is CancellationError) { errorMessage = readErrorMessage(error) }
        }
    }
    func save() async {
        guard canSave, let snapshot else { return }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            let value = try await client.updateText(snapshot, to: proposedValue)
            self.snapshot = value; saved = true
        } catch {
            requiresReload = true
            errorMessage = readErrorMessage(error)
        }
    }
}

struct TextEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: TextEditModel
    @State private var operation = Operation.load(UUID())
    @State private var reviewing = false
    @FocusState private var nameFocused: Bool
    private let server: String
    private enum Operation: Equatable { case load(UUID), save(UUID) }
    init(client: APIClient, target: TextEditTarget, field: EditableTextField = .description) {
        server = client.serverDisplay
        _model = State(initialValue: TextEditModel(client: client, target: target, field: field))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(server).font(.caption).textSelection(.enabled)
                    if let snapshot = model.snapshot { Text(snapshot.object.title).font(.headline) }
                    Text(verbatim: "#\(model.target.id)").font(.caption)
                }
                if model.isLoading { ProgressView("Loading…") }
                if let message = model.errorMessage { Section { StatusMessage(message: message) } }
                if model.saved {
                    Section { Label(model.field.savedTitle, systemImage: "checkmark.circle").accessibilityIdentifier("\(model.field.rawValue)Saved") }
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if reviewing {
                        Section("Before") { Text(model.field.displayValue(snapshot.object.value(for: model.field) ?? "")) }
                        Section("After") { Text(model.field.displayValue(model.proposedValue)) }
                        Section {
                            if model.field == .status || (model.field == .name && (model.target.collection == .virtualMachines || model.target.collection == .vlans)) {
                                Text("This changes only the selected field on the server.")
                            } else {
                                Text("This changes only the selected field on the server. An empty value clears the existing value.")
                            }
                            Button("Confirm change") { operation = .save(UUID()); reviewing = false }
                                .disabled(!model.canSave).accessibilityIdentifier("\(model.field.rawValue)Confirm")
                            Button("Back to editing") { reviewing = false }.disabled(model.isSaving)
                        }
                    } else {
                        Section(model.field.title) {
                            Group {
                                if model.field == .status {
                                    Picker(model.field.title, selection: $model.draft) {
                                        let choices = model.field.statusChoices(for: model.target.collection)
                                        if !choices.contains(model.draft) {
                                            Text(snapshot.object.status?.label ?? model.draft).tag(model.draft)
                                        }
                                        ForEach(choices, id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                                    }.pickerStyle(.menu)
                                } else if model.field == .name {
                                    TextField(model.field.title, text: $model.draft)
                                        .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                                } else if model.field == .comments {
                                    TextEditor(text: $model.draft).frame(minHeight: 180)
                                        .accessibilityLabel(model.field.title)
                                } else {
                                    TextField(model.field.title, text: $model.draft, axis: .vertical).lineLimit(3...8)
                                }
                            }
                                .textInputAutocapitalization(model.field == .dnsName || model.field == .name ? .never : .sentences)
                                .autocorrectionDisabled(model.field == .dnsName || model.field == .name)
                                .disabled(model.isSaving).accessibilityIdentifier("\(model.field.rawValue)Draft")
                            if model.field != .status {
                                Text(L10n.format("Maximum %ld characters", model.target.collection == .vlanGroups && model.field == .name ? 100 : model.field.limit)).font(.caption).foregroundStyle(.secondary)
                            }
                            if model.field == .name {
                                Text(model.target.collection == .devices
                                     ? L10n.text("An empty name makes this device unnamed.")
                                     : L10n.text(model.target.collection == .vlanGroups ? "A VLAN group must have a name." : model.target.collection == .vlans ? "A VLAN must have a name." : "A virtual machine must have a name.")).font(.caption)
                            }
                            if model.field == .comments { Text("Plain text and Markdown are supported. Only surrounding whitespace is removed.").font(.caption) }
                            if model.field == .dnsName { Text("DNS names are stored in lowercase. This updates NetBox only; it does not change your DNS server.").font(.caption) }
                            if let message = model.validationMessage { StatusMessage(message: message) }
                            Button("Review change") { nameFocused = false; reviewing = true }
                                .disabled(!model.canSave).accessibilityIdentifier("\(model.field.rawValue)Review")
                        }
                    }
                }
                if model.requiresReload {
                    Section {
                        Text("Reload before trying again. Your draft is kept. If the connection failed, check the current value: the change may already have been saved.")
                        Button("Reload current value") { reviewing = false; operation = .load(UUID()) }
                            .accessibilityIdentifier("\(model.field.rawValue)Reload")
                    }
                } else if model.snapshot == nil && !model.isLoading {
                    Button("Retry") { operation = .load(UUID()) }
                }
                if model.isSaving { ProgressView("Saving…") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.field.editTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if nameFocused {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { nameFocused = false } }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.isSaving) }
            }
            .interactiveDismissDisabled(model.isSaving)
            .task(id: operation) {
                switch operation { case .load: await model.load(); case .save: await model.save() }
            }
        }
    }
}
