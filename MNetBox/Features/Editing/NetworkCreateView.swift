import SwiftUI

@MainActor @Observable final class NetworkCreateModel {
    enum Proposal: Sendable { case vlan(VLANCreationPlan), mac(MACCreationPlan) }
    let client: APIClient
    let interface: InterfaceSelection?
    var name = ""
    var vid = ""
    var address = ""
    var status = "active"
    var site: ReferenceSelection?
    var group: ReferenceSelection?
    var tenant: ReferenceSelection?
    var role: ReferenceSelection?
    var description = ""
    var comments = ""
    private(set) var reviewed: Proposal?
    private(set) var createdID: Int?
    private(set) var working = false
    private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, interface: InterfaceSelection? = nil) { self.client = client; self.interface = interface }
    func proposal() throws -> Proposal {
        let description = EditableTextField.description.normalized(description)
        let comments = EditableTextField.comments.normalized(comments)
        if let interface {
            let plan = MACCreationPlan(address: try MACValue(address), interface: interface, description: description, comments: comments)
            try plan.validate(); return .mac(plan)
        }
        let text = vid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let vid = Int(text) else { throw APIError.invalidVID }
        let plan = VLANCreationPlan(vid: vid, name: EditableTextField.name.normalized(name), status: status, site: site, group: group, tenant: tenant, role: role, description: description, comments: comments)
        try plan.validate(); return .vlan(plan)
    }
    var canReview: Bool { !working && !attempted && (try? proposal()) != nil }
    var validationMessage: String? {
        guard !(interface == nil ? vid.isEmpty && name.isEmpty : address.isEmpty) else { return nil }
        do { _ = try proposal(); return nil } catch { return readErrorMessage(error) }
    }
    func review() async {
        guard canReview else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do {
            let plan = try proposal()
            switch plan { case .vlan(let plan): try await client.checkVLANCreation(plan); case .mac(let plan): try await client.checkMACCreation(plan) }
            try Task.checkCancellation(); reviewed = plan
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working, !attempted else { return }; reviewed = nil; errorMessage = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil
        defer { working = false }
        do {
            switch reviewed {
            case .vlan(let plan): createdID = try await client.createVLAN(plan).id
            case .mac(let plan): createdID = try await client.createMAC(plan).id
            }
        } catch {
            if case APIError.http(400, _) = error { errorMessage = L10n.text("NetBox rejected the creation. Check required fields and uniqueness rules in NetBox.") }
            else { errorMessage = readErrorMessage(error) }
        }
    }
}

struct NetworkCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NetworkCreateModel
    @State private var operation = Operation.idle
    private enum Field: Hashable { case vid, name, address, description, comments }
    @FocusState private var focused: Field?
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    init(client: APIClient, interface: InterfaceSelection? = nil) { _model = State(initialValue: NetworkCreateModel(client: client, interface: interface)) }
    private func reference(_ title: String, path: String, binding: Binding<ReferenceSelection?>) -> some View {
        NavigationLink { ReferencePickerView(client: model.client, path: path, title: title, selection: binding, emptyTitle: "None") } label: {
            HStack { Text(L10n.text(title)); Spacer(); Text(binding.wrappedValue?.title ?? L10n.text("None")).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("creationReference-\(title)")
    }
    private func selected(_ value: ReferenceSelection?) -> String { value.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None") }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    if let interface = model.interface {
                        Text(interface.title)
                        Text("#\(interface.id) · \(interface.kind.parentKind.singular) #\(interface.parentID ?? 0)").font(.caption)
                    }
                }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if let id = model.createdID {
                    Label("Object created", systemImage: "checkmark.circle").accessibilityIdentifier("networkCreated")
                    NavigationLink("Open created object") {
                        if model.interface == nil { VLANDetailView(service: VLANBrowseService(client: model.client, kind: .vlans), id: id) }
                        else { MACDetailView(client: model.client, id: id) }
                    }.accessibilityIdentifier("openCreatedNetwork")
                    Button("Done") { dismiss() }
                } else if let reviewed = model.reviewed {
                    Section("Creation preview") {
                        switch reviewed {
                        case .vlan(let plan):
                            DetailField(title: "VLAN ID", value: String(plan.vid))
                            DetailField(title: "Name", value: plan.name)
                            DetailField(title: "Status", value: L10n.text(plan.status.capitalized))
                            DetailField(title: "Site", value: selected(plan.site)); DetailField(title: "VLAN group", value: selected(plan.group))
                            DetailField(title: "Tenant", value: selected(plan.tenant)); DetailField(title: "Role", value: selected(plan.role))
                            DetailField(title: "Description", value: plan.description.isEmpty ? L10n.text("Empty") : plan.description)
                            if !plan.comments.isEmpty { Text(plan.comments) }
                        case .mac(let plan):
                            DetailField(title: "MAC address", value: plan.address.text)
                            DetailField(title: "Interface", value: "\(plan.interface.title) (#\(plan.interface.id))")
                            DetailField(title: "Description", value: plan.description.isEmpty ? L10n.text("Empty") : plan.description)
                            if !plan.comments.isEmpty { Text(plan.comments) }
                            Text("The MAC is assigned to this interface. Setting it primary is a separate reviewed change.")
                        }
                        Text("The duplicate check covers visible objects only. NetBox permissions and uniqueness rules still apply.").font(.caption)
                        if !model.attempted {
                            Button("Confirm creation") { operation = .create(UUID()) }.accessibilityIdentifier("networkCreateConfirm")
                            Button("Back to editing") { model.back() }
                        }
                    }.disabled(model.working)
                } else {
                    Section(model.interface == nil ? "VLAN" : "MAC address") {
                        if model.interface == nil {
                            TextField("VLAN ID", text: $model.vid).keyboardType(.numberPad).focused($focused, equals: .vid).accessibilityIdentifier("vlanVIDDraft")
                            TextField("Name", text: $model.name).focused($focused, equals: .name).accessibilityIdentifier("vlanNameDraft")
                            Picker("Status", selection: $model.status) { ForEach(["active", "reserved", "deprecated"], id: \.self) { Text(L10n.text($0.capitalized)).tag($0) } }
                            reference("Site", path: "dcim/sites/", binding: $model.site)
                            reference("VLAN group", path: "ipam/vlan-groups/", binding: $model.group)
                            reference("Tenant", path: "tenancy/tenants/", binding: $model.tenant)
                            reference("Role", path: "ipam/roles/", binding: $model.role)
                        } else { TextField("MAC address", text: $model.address).focused($focused, equals: .address).accessibilityIdentifier("macAddressDraft") }
                        TextField("Description", text: $model.description, axis: .vertical).focused($focused, equals: .description)
                        TextField("Comments", text: $model.comments, axis: .vertical).focused($focused, equals: .comments)
                    }.textInputAutocapitalization(.never).autocorrectionDisabled().disabled(model.working)
                    if let message = model.validationMessage { StatusMessage(message: message) }
                    Button("Review creation") { focused = nil; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("networkCreateReview")
                }
                if model.attempted && model.createdID == nil {
                    Text("Creation was attempted. Check existing objects before starting again; the response may have been lost.")
                    NavigationLink("Check existing objects") {
                        if model.interface == nil { VLANListView(service: VLANBrowseService(client: model.client, kind: .vlans), allowsCreation: false) }
                        else { MACListView(service: MACService(client: model.client, interface: model.interface), allowsCreation: false) }
                    }
                }
                if model.working { ProgressView("Loading…") }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.interface == nil ? "New VLAN" : "New MAC address").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if focused != nil { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = nil } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(model.working) } }
            .interactiveDismissDisabled(model.working)
            .task(id: operation) {
                switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() }
            }
        }
    }
}
