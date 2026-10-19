import SwiftUI

@MainActor @Observable final class VLANGroupCreateModel {
    let client: APIClient
    var name = ""
    var slug = ""
    var ranges = "1-4094"
    var description = ""
    var comments = ""
    var scope = VLANGroupScope.global
    var reference: ReferenceSelection?
    var tenant: ReferenceSelection?
    private(set) var reviewed: VLANGroupCreationPlan?
    private(set) var createdID: Int?
    private(set) var working = false
    private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient) { self.client = client }
    func proposal() throws -> VLANGroupCreationPlan {
        let plan = VLANGroupCreationPlan(name: EditableTextField.name.normalized(name), slug: slug.trimmingCharacters(in: .whitespacesAndNewlines), scope: scope, reference: reference, ranges: try VLANGroupCreationPlan.parseRanges(ranges), tenant: tenant, description: EditableTextField.description.normalized(description), comments: EditableTextField.comments.normalized(comments))
        try plan.validate(); return plan
    }
    var canReview: Bool { !working && !attempted && (try? proposal()) != nil }
    var validationMessage: String? {
        guard !name.isEmpty || !slug.isEmpty else { return nil }
        do { _ = try proposal(); return nil } catch { return readErrorMessage(error) }
    }
    func review() async {
        guard canReview else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { let plan = try proposal(); try await client.checkVLANGroupCreation(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working, !attempted else { return }; reviewed = nil; errorMessage = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        working = true; attempted = true; errorMessage = nil
        defer { working = false }
        do { createdID = try await client.createVLANGroup(reviewed).id }
        catch { errorMessage = readErrorMessage(error) }
    }
}

struct VLANGroupCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: VLANGroupCreateModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient) { _model = State(initialValue: VLANGroupCreateModel(client: client)) }
    private func reference(_ title: String, path: String, selection: Binding<ReferenceSelection?>) -> some View {
        NavigationLink { ReferencePickerView(client: model.client, path: path, title: title, selection: selection, emptyTitle: "None") } label: {
            HStack { Text(L10n.text(title)); Spacer(); Text(selection.wrappedValue?.title ?? L10n.text("None")).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("groupReference-\(title)")
    }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") { Text(model.client.serverDisplay).font(.caption) }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if let id = model.createdID {
                    Label("Object created", systemImage: "checkmark.circle").accessibilityIdentifier("groupCreated")
                    NavigationLink("Open created object") { VLANDetailView(service: VLANBrowseService(client: model.client, kind: .groups), id: id) }.accessibilityIdentifier("openCreatedGroup")
                    Button("Done") { dismiss() }
                } else if let plan = model.reviewed {
                    Section("Creation preview") {
                        DetailField(title: "Name", value: plan.name); DetailField(title: "Slug", value: plan.slug)
                        DetailField(title: "Scope", value: L10n.text(plan.scope.title) + (plan.reference.map { " · \($0.title) (#\($0.id))" } ?? ""))
                        DetailField(title: "VLAN ID ranges", value: plan.ranges.map { "\($0[0])–\($0[1])" }.joined(separator: ", "))
                        DetailField(title: "Tenant", value: plan.tenant.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None"))
                        DetailField(title: "Description", value: plan.description.isEmpty ? L10n.text("Empty") : plan.description)
                        if !plan.comments.isEmpty { Text(plan.comments) }
                        Text("The duplicate check covers visible objects only. NetBox permissions and uniqueness rules still apply.").font(.caption)
                        if !model.attempted {
                            Button("Confirm creation") { operation = .create(UUID()) }.accessibilityIdentifier("groupCreateConfirm")
                            Button("Back to editing") { model.back() }
                        }
                    }.disabled(model.working)
                } else {
                    Section("VLAN group") {
                        TextField("Name", text: $model.name).accessibilityIdentifier("groupNameDraft")
                        TextField("Slug", text: $model.slug).accessibilityIdentifier("groupSlugDraft")
                        TextField("VLAN ID ranges", text: $model.ranges).accessibilityIdentifier("groupRangesDraft")
                        Text("Ranges example: 1-100,200,300-399. Values must be 1–4094 without overlap.").font(.caption)
                        Picker("Scope", selection: $model.scope) { ForEach(VLANGroupScope.allCases) { Text(L10n.text($0.title)).tag($0) } }
                            .onChange(of: model.scope) { _, _ in model.reference = nil }
                        if model.scope != .global { reference(model.scope.title, path: model.scope.path, selection: $model.reference).id(model.scope) }
                        reference("Tenant", path: "tenancy/tenants/", selection: $model.tenant)
                        TextField("Description", text: $model.description, axis: .vertical)
                        TextField("Comments", text: $model.comments, axis: .vertical)
                    }.focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.working)
                    if let error = model.validationMessage { StatusMessage(message: error) }
                    Button("Review creation") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("groupCreateReview")
                }
                if model.attempted && model.createdID == nil {
                    Text("Creation was attempted. Check existing objects before starting again; the response may have been lost.")
                    NavigationLink("Check existing objects") { VLANListView(service: VLANBrowseService(client: model.client, kind: .groups), allowsCreation: false) }
                }
                if model.working { ProgressView("Loading…") }
            }.scrollDismissesKeyboard(.interactively)
            .navigationTitle("New VLAN group").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(model.working) }
            }.interactiveDismissDisabled(model.working)
            .task(id: operation) { switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() } }
        }
    }
}
