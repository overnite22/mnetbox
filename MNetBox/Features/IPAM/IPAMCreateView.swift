import SwiftUI

@MainActor @Observable final class IPAMCreateModel {
    var draft: IPAMCreationDraft
    private(set) var reviewed: IPAMCreationPlan?
    private(set) var created: IPAMObject?
    private(set) var isChecking = false
    private(set) var isSaving = false
    private(set) var attempted = false
    private(set) var errorMessage: String?
    let client: APIClient
    init(client: APIClient, kind: IPAMKind, vrf: ReferenceSelection? = nil, tenant: ReferenceSelection? = nil, assignment: InterfaceSelection? = nil, cidr: String = "") {
        self.client = client
        draft = IPAMCreationDraft(kind: kind, cidr: cidr, vrf: vrf?.id == 0 ? nil : vrf, tenant: tenant, assignment: assignment)
    }
    var isWorking: Bool { isChecking || isSaving }
    var canReview: Bool { !isWorking && !attempted && (try? draft.plan()) != nil }
    var validationMessage: String? {
        guard !draft.cidr.isEmpty else { return nil }
        do { _ = try draft.plan(); return nil } catch { return readErrorMessage(error) }
    }
    func review() async {
        guard canReview else { return }
        isChecking = true; errorMessage = nil
        defer { isChecking = false }
        do {
            let plan = try draft.plan()
            try await client.checkIPAMCreation(plan)
            try Task.checkCancellation()
            reviewed = plan
        } catch { if !(error is CancellationError) { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !isWorking else { return }; reviewed = nil; errorMessage = nil }
    func create() async {
        guard !attempted, !isWorking, let plan = reviewed else { return }
        attempted = true; isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do { created = try await client.createIPAM(plan) }
        catch {
            if case APIError.http(400, _) = error {
                errorMessage = L10n.text("NetBox rejected the creation. Check required fields and uniqueness rules in NetBox.")
            } else if error as? APIError == .conflict {
                errorMessage = L10n.text("NetBox reported a creation conflict. Check existing objects before trying again.")
            } else { errorMessage = readErrorMessage(error) }
        }
    }
}

struct IPAMCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: IPAMCreateModel
    private enum Field: Hashable { case cidr, description, comments, dns }
    @FocusState private var focused: Field?
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, kind: IPAMKind, vrf: ReferenceSelection? = nil, tenant: ReferenceSelection? = nil, assignment: InterfaceSelection? = nil, cidr: String = "") {
        _model = State(initialValue: IPAMCreateModel(client: client, kind: kind, vrf: vrf, tenant: tenant, assignment: assignment, cidr: cidr))
    }
    private var title: String { L10n.text(model.draft.kind == .prefixes ? "New prefix" : "New IP address") }
    private var verificationQuery: IPAMQuery {
        var query = IPAMQuery()
        query.search = model.reviewed?.cidr.text ?? model.draft.cidr
        query.vrf = model.draft.vrf ?? ReferenceSelection(id: 0, title: L10n.text("Global VRF"))
        return query
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption).textSelection(.enabled)
                    Text(model.draft.kind.title)
                    if let assignment = model.draft.assignment {
                        Text(assignment.kind.parentKind.title + " · " + assignment.title)
                        Text(verbatim: "#\(assignment.id) · " + L10n.identifier("Parent #%ld", assignment.parentID ?? 0))
                    }
                }
                if let error = model.errorMessage { Section { StatusMessage(message: error) } }
                if let object = model.created {
                    Section {
                        Label("Object created", systemImage: "checkmark.circle").accessibilityIdentifier("ipamCreated")
                        Text(object.title).monospaced()
                        Text(verbatim: "#\(object.id)")
                        NavigationLink("Open created object") {
                            IPAMDetailView(service: IPAMService(client: model.client, kind: model.draft.kind), id: object.id)
                        }.accessibilityIdentifier("openCreatedIPAM")
                        Button("Done") { dismiss() }
                    }
                } else if let plan = model.reviewed {
                    Section("Creation preview") {
                        DetailField(title: model.draft.kind == .prefixes ? "Prefix" : "IP address", value: plan.cidr.text)
                            .accessibilityIdentifier("creationCIDRPreview")
                        DetailField(title: "Status", value: L10n.text(plan.status.capitalized))
                        DetailField(title: "VRF", value: plan.vrf.map { "\($0.title) (#\($0.id))" } ?? L10n.text("Global VRF"))
                        DetailField(title: "Tenant", value: plan.tenant.map { "\($0.title) (#\($0.id))" } ?? L10n.text("No tenant"))
                        DetailField(title: "Description", value: plan.description.isEmpty ? L10n.text("Empty") : plan.description)
                        if !plan.comments.isEmpty { Text(plan.comments) }
                        if plan.kind == .ipAddresses { DetailField(title: "DNS name", value: plan.dnsName.isEmpty ? L10n.text("Empty") : plan.dnsName) }
                        if let assignment = plan.assignment {
                            DetailField(title: "Interface", value: assignment.title + " (#\(assignment.id))")
                            Text(L10n.identifier("Parent #%ld", assignment.parentID ?? 0))
                            Text("This creates one IP address assigned to the reviewed interface. No primary IP or device configuration is changed.")
                        } else { Text("This creates one object in NetBox. No interface assignment or DNS server change is made.") }
                        Text("The duplicate check covers visible objects only. NetBox permissions and uniqueness rules still apply.").font(.caption)
                        if !model.attempted {
                            Button("Confirm creation") { operation = .create(UUID()) }
                                .disabled(model.isWorking).accessibilityIdentifier("confirmIPAMCreation")
                            Button("Back to editing") { model.back() }.disabled(model.isWorking)
                        }
                    }
                } else {
                    Section("New object") {
                        TextField(model.draft.kind == .prefixes ? L10n.text("Prefix") : L10n.text("IP address"), text: $model.draft.cidr)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                            .focused($focused, equals: .cidr).submitLabel(.done)
                            .accessibilityIdentifier("creationCIDR")
                        Text("Include the prefix length (/24, /64, etc.). Prefixes must use the network address.").font(.caption)
                        Picker("Status", selection: $model.draft.status) {
                            ForEach(model.draft.kind.statuses, id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                        }.accessibilityIdentifier("creationStatus")
                        reference("VRF", path: "ipam/vrfs/", selection: $model.draft.vrf, empty: "Global VRF")
                        reference("Tenant", path: "tenancy/tenants/", selection: $model.draft.tenant, empty: "No tenant")
                        TextField("Description", text: $model.draft.description, axis: .vertical).lineLimit(2...5)
                            .focused($focused, equals: .description)
                            .accessibilityIdentifier("creationDescription")
                        if model.draft.kind == .ipAddresses {
                            TextField("DNS name", text: $model.draft.dnsName).textInputAutocapitalization(.never)
                                .autocorrectionDisabled().keyboardType(.asciiCapable).focused($focused, equals: .dns).submitLabel(.done)
                                .accessibilityIdentifier("creationDNSName")
                        }
                        Text("Comments").font(.subheadline)
                        TextEditor(text: $model.draft.comments).frame(minHeight: 120)
                            .focused($focused, equals: .comments)
                            .accessibilityLabel(L10n.text("Comments")).accessibilityIdentifier("creationComments")
                        if let error = model.validationMessage { StatusMessage(message: error) }
                        Button("Review creation") { focused = nil; operation = .review(UUID()) }
                            .disabled(!model.canReview).accessibilityIdentifier("reviewIPAMCreation")
                    }.disabled(model.isWorking || model.attempted)
                }
                if model.attempted && model.created == nil && !model.isSaving {
                    Section {
                        Text("Creation was not confirmed. Your draft is kept here. Check NetBox before starting another creation; a lost response may have saved the object.")
                        Text("Draft")
                        Text(model.draft.cidr).monospaced().textSelection(.enabled)
                        if !model.draft.description.isEmpty { Text(model.draft.description).textSelection(.enabled) }
                        if !model.draft.comments.isEmpty { Text(model.draft.comments).textSelection(.enabled) }
                        if !model.draft.dnsName.isEmpty { Text(model.draft.dnsName).textSelection(.enabled) }
                    }
                }
                if model.errorMessage != nil && !model.isWorking {
                    NavigationLink("Check existing objects") {
                        IPAMListView(service: IPAMService(client: model.client, kind: model.draft.kind), initialQuery: verificationQuery, allowsCreation: false)
                    }.accessibilityIdentifier("checkExistingIPAM")
                }
                if model.isChecking { ProgressView("Checking existing objects…") }
                if model.isSaving { ProgressView("Saving…") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .onSubmit { focused = nil }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.isSaving) }
                ToolbarItem(placement: .topBarLeading) {
                    if focused != nil {
                        Button("Done") { focused = nil }.accessibilityIdentifier("dismissCreationKeyboard")
                    }
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .task(id: operation) {
                switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() }
            }
        }
    }
    private func reference(_ title: String, path: String, selection: Binding<ReferenceSelection?>, empty: String) -> some View {
        NavigationLink {
            ReferencePickerView(client: model.client, path: path, title: title, selection: selection, emptyTitle: empty)
        } label: {
            HStack {
                Text(L10n.text(title)); Spacer()
                Text(selection.wrappedValue?.title ?? L10n.text(empty)).foregroundStyle(.secondary)
            }
        }
            .accessibilityIdentifier("creation-\(title)")
    }
}
