import SwiftUI

@MainActor @Observable final class StructuredEditModel {
    let client: APIClient
    let target: StructuredEditTarget
    let field: StructuredEditField
    private(set) var snapshot: StructuredEditSnapshot?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    var text = ""
    var interfaceType = "virtual"
    var enabled = true
    var mtu = ""
    var reference: ReferenceSelection?
    var status = "active"
    var assignment: InterfaceSelection?
    var assignmentKind = InterfaceKind.physical
    var assignmentParent: ReferenceSelection?
    var assignmentReference: ReferenceSelection?
    init(client: APIClient, target: StructuredEditTarget, field: StructuredEditField) {
        self.client = client; self.target = target; self.field = field
    }
    func proposal() throws -> StructuredEditValue {
        let value: StructuredEditValue
        switch field {
        case .name: value = .text(try InterfaceCreationDraft.normalizedName(text))
        case .description: value = .text(EditableTextField.description.normalized(text))
        case .type: value = .interfaceType(interfaceType)
        case .status: value = .status(status)
        case .assignment: value = .assignment(assignment)
        case .enabled: value = .enabled(enabled)
        case .mtu:
            let text = mtu.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { value = .mtu(nil) }
            else {
                guard text.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(text) else { throw APIError.invalidMTU }
                value = .mtu(number)
            }
        default: value = .reference(reference)
        }
        try value.validate(field: field, target: target)
        return value
    }
    var validationMessage: String? {
        if field == .type, !InterfaceTypeOptions.values.contains(interfaceType) { return nil }
        do { _ = try proposal(); return nil } catch { return readErrorMessage(error) }
    }
    var canReview: Bool {
        guard let before = snapshot?.object.value(field), let after = try? proposal() else { return false }
        return !isLoading && !isSaving && !requiresReload && !saved && !before.matches(after)
    }
    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await client.structuredSnapshot(target: target, field: field)
            try Task.checkCancellation()
            if self.snapshot == nil, let initial = snapshot.object.value(field) {
                switch initial {
                case .text(let value): text = value
                case .interfaceType(let value): interfaceType = value
                case .status(let value): status = value
                case .assignment(let value): assignment = value; assignmentKind = value?.kind ?? .physical
                case .enabled(let value): enabled = value
                case .mtu(let value): mtu = value.map(String.init) ?? ""
                case .reference(let value): reference = value
                }
            }
            self.snapshot = snapshot; requiresReload = false
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func review() async -> StructuredEditValue? {
        guard canReview else { return nil }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let value = try proposal()
            try await client.checkStructuredReference(value, target: target, field: field)
            try Task.checkCancellation()
            return value
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) }; return nil }
    }
    func save(_ reviewed: StructuredEditValue) async {
        guard canReview, let snapshot, let current = try? proposal(), current.matches(reviewed) else { return }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            self.snapshot = try await client.updateStructured(snapshot, to: reviewed)
            saved = true
        } catch { requiresReload = true; errorMessage = readErrorMessage(error) }
    }
}

struct StructuredEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: StructuredEditModel
    @State private var reviewed: StructuredEditValue?
    @State private var operation = Operation.load(UUID())
    @FocusState private var mtuFocused: Bool
    private enum Operation: Equatable { case load(UUID), review(UUID), save(UUID) }
    init(client: APIClient, target: StructuredEditTarget, field: StructuredEditField) {
        _model = State(initialValue: StructuredEditModel(client: client, target: target, field: field))
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.snapshot?.object.title ?? "#\(model.target.id)").font(.headline)
                    Text("#\(model.target.id)").font(.caption)
                    if let parentID = model.target.parentID { Text(L10n.format("Parent #%ld", parentID)).font(.caption) }
                }
                if model.isLoading { ProgressView("Loading…") }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if model.saved {
                    Label("Change saved", systemImage: "checkmark.circle").accessibilityIdentifier("structuredSaved")
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if let reviewed {
                        Section("Before") { Text(snapshot.object.value(model.field)?.display ?? "—") }
                        Section("After") { Text(reviewed.display) }
                        Section {
                            Text("This changes only the selected field on the server.")
                            Button("Confirm change") { operation = .save(UUID()) }
                                .disabled(!model.canReview).accessibilityIdentifier("structuredConfirm")
                            Button("Back to editing") { self.reviewed = nil }.disabled(model.isSaving)
                        }
                    } else {
                        Section(model.field.title) {
                            if model.field.isText {
                                TextField(model.field.title, text: $model.text, axis: model.field == .description ? .vertical : .horizontal)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($mtuFocused)
                                    .accessibilityIdentifier("interfaceTextDraft")
                                Text(model.field == .name ? "Enter an interface name (1–64 characters)." : "Description: up to 200 characters; empty clears it.").font(.caption)
                                if model.field == .description {
                                    Button("Clear description") { model.text = "" }.accessibilityIdentifier("clearInterfaceDescription")
                                }
                            } else if model.field == .type {
                                Picker("Type", selection: $model.interfaceType) {
                                    if !InterfaceTypeOptions.values.contains(model.interfaceType) {
                                        Text(model.interfaceType).tag(model.interfaceType)
                                    }
                                    ForEach(InterfaceTypeOptions.values, id: \.self) { Text(InterfaceTypeOptions.title($0)).tag($0) }
                                }.accessibilityIdentifier("interfaceTypeDraft")
                                Text("Common interface types are offered here. Other types can be configured in NetBox.").font(.caption)
                            } else if model.field == .status {
                                Picker("Status", selection: $model.status) {
                                    ForEach(model.field.statuses(model.target.collection), id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                                }.accessibilityIdentifier("statusDraft")
                            } else if model.field == .assignment {
                                Text(StructuredEditValue.assignment(model.assignment).display)
                                Button("Remove assignment") { model.assignment = nil }.accessibilityIdentifier("clearAssignment")
                                Picker("Parent type", selection: $model.assignmentKind) {
                                    Text("Device").tag(InterfaceKind.physical); Text("Virtual machine").tag(InterfaceKind.virtual)
                                }.accessibilityIdentifier("assignmentKind")
                                NavigationLink("Select parent") {
                                    ReferencePickerView(client: model.client, path: model.assignmentKind.parentKind.path, title: "Parent", selection: $model.assignmentParent, allowsEmpty: false)
                                }.accessibilityIdentifier("assignmentParent")
                                if let parent = model.assignmentParent {
                                    NavigationLink("Select interface") {
                                        ReferencePickerView(client: model.client, path: model.assignmentKind.path, title: "Interface", selection: $model.assignmentReference, allowsEmpty: false, required: [.init(name: model.assignmentKind.parentFilter, value: String(parent.id))])
                                    }.accessibilityIdentifier("assignmentInterface")
                                }
                            } else if model.field == .enabled {
                                Toggle("Enabled", isOn: $model.enabled).accessibilityIdentifier("enabledDraft")
                                Text("These values describe the interface in NetBox.").font(.caption)
                            } else if model.field == .mtu {
                                TextField("MTU", text: $model.mtu).keyboardType(.numberPad).focused($mtuFocused)
                                    .accessibilityIdentifier("mtuDraft")
                                Text("Enter 1 to 65536, or leave empty to clear MTU.").font(.caption)
                            } else {
                                NavigationLink {
                                    ReferencePickerView(client: model.client, path: model.target.collection == .vlans && model.field == .role ? "ipam/roles/" : model.field.referencePath, title: model.field.title,
                                        selection: $model.reference, emptyTitle: "None",
                                        allowsEmpty: model.field.allowsEmpty(model.target.collection),
                                        required: model.field.filters(model.target.collection, id: model.target.id))
                                } label: {
                                    HStack { Text(model.field.title); Spacer(); Text(model.reference?.title ?? L10n.text("None")).foregroundStyle(.secondary) }
                                }.accessibilityIdentifier("structuredReference")
                            }
                            if let message = model.validationMessage { StatusMessage(message: message) }
                            Button("Review change") { mtuFocused = false; operation = .review(UUID()) }
                                .disabled(!model.canReview).accessibilityIdentifier("structuredReview")
                        }.disabled(model.isSaving || model.isLoading)
                    }
                }
                if model.requiresReload {
                    Text("Reload before trying again. Your draft is kept. If the connection failed, check the current value: the change may already have been saved.")
                    Button("Reload current value") { reviewed = nil; operation = .load(UUID()) }.accessibilityIdentifier("structuredReload")
                } else if model.snapshot == nil && !model.isLoading {
                    Button("Retry") { operation = .load(UUID()) }
                }
                if model.isSaving { ProgressView("Saving…") }
            }
            .onChange(of: model.assignmentKind) { model.assignmentParent = nil; model.assignmentReference = nil }
            .onChange(of: model.assignmentParent) { model.assignmentReference = nil }
            .onChange(of: model.assignmentReference) {
                if let reference = model.assignmentReference, let parent = model.assignmentParent {
                    model.assignment = InterfaceSelection(kind: model.assignmentKind, id: reference.id, title: reference.title, parentID: parent.id)
                }
            }
            .navigationTitle(model.field.editTitle).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if mtuFocused { ToolbarItem(placement: .topBarLeading) { Button("Done") { mtuFocused = false } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.isSaving) }
            }
            .interactiveDismissDisabled(model.isSaving)
            .task(id: operation) {
                switch operation {
                case .load: await model.load()
                case .review: reviewed = await model.review()
                case .save: if let reviewed { await model.save(reviewed) }
                }
            }
        }
    }
}
