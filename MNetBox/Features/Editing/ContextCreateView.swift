import SwiftUI

@MainActor @Observable final class ContextCreateModel {
    let client: APIClient; let kind: ContextKind
    var name = ""
    var slug = ""
    var rd = ""
    var weight = "1000"
    var description = ""
    var comments = ""
    var unique = true; var tenant: ReferenceSelection?; var group: ReferenceSelection?
    private(set) var reviewed: ContextCreationPlan?; private(set) var created: ContextAdminRecord?
    private(set) var working = false; private(set) var attempted = false; private(set) var errorMessage: String?
    init(client: APIClient, kind: ContextKind) { self.client = client; self.kind = kind }
    func proposal() throws -> ContextCreationPlan {
        guard !weight.isEmpty, weight.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(weight) else { throw APIError.invalidWeight }
        let plan = ContextCreationPlan(kind: kind, name: name.trimmingCharacters(in: .whitespacesAndNewlines), slug: slug, rd: rd.trimmingCharacters(in: .whitespacesAndNewlines), unique: unique, tenant: tenant, group: group, weight: n, description: description.trimmingCharacters(in: .whitespacesAndNewlines), comments: comments.trimmingCharacters(in: .whitespacesAndNewlines))
        try plan.validate(); return plan
    }
    var canReview: Bool { !working && !attempted && (try? proposal()) != nil }
    var validationMessage: String? { do { _ = try proposal(); return nil } catch { return readErrorMessage(error) } }
    func review() async {
        guard canReview else { return }; working = true; errorMessage = nil; defer { working = false }
        do { let plan = try proposal(); try await client.checkContextCreation(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func save() async {
        guard !working, !attempted, let reviewed else { return }; working = true; attempted = true; errorMessage = nil; defer { working = false }
        do { created = try await client.createContext(reviewed) } catch { errorMessage = readErrorMessage(error) }
    }
}

struct ContextCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ContextCreateModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case idle, review(UUID), save(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, kind: ContextKind) { _model = State(initialValue: ContextCreateModel(client: client, kind: kind)) }
    private func reference(_ title: String, path: String, binding: Binding<ReferenceSelection?>) -> some View {
        NavigationLink { ReferencePickerView(client: model.client, path: path, title: title, selection: binding, emptyTitle: "None") } label: { DetailField(title: title, value: binding.wrappedValue?.title ?? L10n.text("None")) }
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") { Text(model.client.serverDisplay).font(.caption); Label(model.kind.title, systemImage: model.kind.symbol) }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if let created = model.created {
                    Label("Object created", systemImage: "checkmark.circle").accessibilityIdentifier("contextCreated")
                    NavigationLink("Open created object") { ContextDetailView(service: ContextService(client: model.client, kind: model.kind), id: created.row.id) }.accessibilityIdentifier("openCreatedContext")
                    Button("Done") { dismiss() }
                } else if let plan = model.reviewed {
                    Section("Review creation") {
                        DetailField(title: "Name", value: plan.name)
                        if plan.kind == .vrfs {
                            DetailField(title: "Route distinguisher", value: plan.rd.isEmpty ? L10n.text("None") : plan.rd)
                            DetailField(title: "Enforce unique", value: L10n.text(plan.unique ? "Yes" : "No"))
                            DetailField(title: "Tenant", value: plan.tenant.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None"))
                        } else {
                            DetailField(title: "Slug", value: plan.slug)
                            if plan.kind == .tenants { DetailField(title: "Tenant group", value: plan.group.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None")) }
                            else { DetailField(title: "Weight", value: String(plan.weight)) }
                        }
                        DetailField(title: "Description", value: plan.description); DetailField(title: "Comments", value: plan.comments)
                        Text("This creates one context in NetBox. Existing objects and network configuration are not changed.").font(.caption)
                        Button("Confirm creation") { operation = .save(UUID()) }.disabled(model.working || model.attempted).accessibilityIdentifier("contextCreateConfirm")
                        Button("Back to editing") { model.back() }.disabled(model.working || model.attempted)
                    }
                } else {
                    Section(model.kind.title) {
                        TextField("Name", text: $model.name).focused($focused).accessibilityIdentifier("contextNameDraft")
                        if model.kind == .vrfs {
                            TextField("Route distinguisher", text: $model.rd).focused($focused).accessibilityIdentifier("contextRDDraft")
                            Toggle("Enforce unique", isOn: $model.unique)
                            reference("Tenant", path: "tenancy/tenants/", binding: $model.tenant)
                        } else {
                            TextField("Slug", text: $model.slug).focused($focused).accessibilityIdentifier("contextSlugDraft")
                            if model.kind == .tenants { reference("Tenant group", path: "tenancy/tenant-groups/", binding: $model.group) }
                            else { TextField("Weight", text: $model.weight).focused($focused).accessibilityIdentifier("contextWeightDraft") }
                        }
                        TextField("Description", text: $model.description, axis: .vertical).focused($focused)
                        TextField("Comments", text: $model.comments, axis: .vertical).focused($focused)
                        if let error = model.validationMessage { StatusMessage(message: error) }
                        Button("Review creation") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("contextCreateReview")
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.working || model.attempted)
                }
                if model.attempted && model.created == nil {
                    Text("Creation was attempted. Check existing objects before starting again; the response may have been lost.")
                    NavigationLink("Check existing objects") { ContextListView(service: ContextService(client: model.client, kind: model.kind), allowsCreation: false) }
                }
                if model.working { ProgressView("Loading…") }
            }.navigationTitle("New context").navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar {
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.working) }
            }.interactiveDismissDisabled(model.working)
            .task(id: operation) { switch operation { case .idle: break; case .review: await model.review(); case .save: await model.save() } }
        }
    }
}
