import SwiftUI

@MainActor @Observable final class InterfaceCreateModel {
    let client: APIClient
    var draft: InterfaceCreationDraft
    private(set) var reviewed: InterfaceCreationPlan?
    private(set) var created: InterfaceObject?
    private(set) var working = false
    private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, kind: InterfaceKind, parentID: Int) {
        self.client = client; draft = InterfaceCreationDraft(kind: kind, parentID: parentID, type: kind == .physical ? "1000base-t" : "virtual")
    }
    var validationMessage: String? {
        guard !draft.name.isEmpty else { return nil }
        do { _ = try draft.plan(); return nil } catch { return readErrorMessage(error) }
    }
    var canReview: Bool { !working && !attempted && (try? draft.plan()) != nil }
    func review() async {
        guard canReview else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do {
            let plan = try draft.plan()
            try await client.checkInterfaceCreation(plan)
            try Task.checkCancellation()
            reviewed = plan
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil
        defer { working = false }
        do { created = try await client.createInterface(reviewed) }
        catch { errorMessage = readErrorMessage(error) }
    }
}
struct InterfaceCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var createdDeleted = false
    @State private var model: InterfaceCreateModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, kind: InterfaceKind, parentID: Int) {
        _model = State(initialValue: InterfaceCreateModel(client: client, kind: kind, parentID: parentID))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(L10n.identifier("Parent #%ld", model.draft.parentID))
                    Text(model.draft.kind.parentKind.title)
                }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if let object = model.created {
                    if createdDeleted {
                        Label("Object deleted", systemImage: "trash")
                    } else {
                        Label("Object created", systemImage: "checkmark.circle").accessibilityIdentifier("interfaceCreated")
                        NavigationLink("Open created object") {
                            InterfaceDetailView(service: InterfaceService(client: model.client, kind: model.draft.kind, parentID: model.draft.parentID), id: object.id, onDeleted: { createdDeleted = true })
                        }
                    }
                    Button("Done") { dismiss() }
                } else if let plan = model.reviewed {
                    Section("Creation preview") {
                        DetailField(title: "Name", value: plan.name)
                        if plan.kind == .physical { DetailField(title: "Type", value: plan.type) }
                        DetailField(title: "Enabled", value: L10n.text(plan.enabled ? "Yes" : "No"))
                        DetailField(title: "MTU", value: plan.mtu.map(String.init) ?? L10n.text("Empty"))
                        DetailField(title: "Description", value: plan.description)
                        Text("The duplicate check covers visible objects only. NetBox permissions and uniqueness rules still apply.").font(.caption)
                        if !model.attempted {
                            Button("Confirm creation") { operation = .create(UUID()) }.accessibilityIdentifier("confirmInterfaceCreation")
                            Button("Back to editing") { model.back() }
                        }
                    }.disabled(model.working)
                } else {
                    Section("New interface") {
                        TextField("Name", text: $model.draft.name).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused).accessibilityIdentifier("interfaceCreationName")
                        Text("Enter an interface name (1–64 characters).").font(.caption)
                        if model.draft.kind == .physical {
                            Picker("Type", selection: $model.draft.type) {
                                ForEach(InterfaceCreationDraft.types, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        Toggle("Enabled", isOn: $model.draft.enabled)
                        TextField("MTU", text: $model.draft.mtu).keyboardType(.numberPad).focused($focused)
                        Text("Enter 1 to 65536, or leave empty to clear MTU.").font(.caption)
                        TextField("Description", text: $model.draft.description, axis: .vertical).focused($focused)
                        if let error = model.validationMessage { StatusMessage(message: error) }
                        Button("Review creation") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("reviewInterfaceCreation")
                    }.disabled(model.working || model.attempted)
                }
                if model.attempted && model.created == nil && !model.working {
                    Text("Creation was not confirmed. Your draft is kept here. Check NetBox before starting another creation; a lost response may have saved the object.")
                    Text(model.draft.name).textSelection(.enabled)
                    Text(model.draft.description).textSelection(.enabled)
                }
                if model.errorMessage != nil && !model.working {
                    NavigationLink("Check existing objects") {
                        InterfaceListView(service: InterfaceService(client: model.client, kind: model.draft.kind, parentID: model.draft.parentID), title: L10n.identifier("Parent #%ld", model.draft.parentID), allowsCreation: false)
                    }
                }
                if model.working { ProgressView("Loading…") }
            }
            .navigationTitle("New interface").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
            }
            .interactiveDismissDisabled(model.working)
            .task(id: operation) {
                switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() }
            }
        }
    }
}
