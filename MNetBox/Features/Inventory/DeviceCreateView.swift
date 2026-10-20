import SwiftUI

@MainActor @Observable final class DeviceCreateModel {
    let client: APIClient
    var draft = DeviceCreationPlan()
    var positionText = ""
    private(set) var reviewed: DeviceCreationPlan?
    private(set) var created: DeviceCreationReply?
    private(set) var working = false; private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, site: ReferenceSelection? = nil, rack: ReferenceSelection? = nil) {
        self.client = client; draft.site = site; draft.rack = rack
    }
    var plan: DeviceCreationPlan? {
        var value = draft
        let text = positionText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { value.position = nil } else if let number = Int(text) { value.position = number } else { return nil }
        return try? value.validated()
    }
    var validationMessage: String? {
        guard draft.deviceType != nil, draft.role != nil, draft.site != nil, plan == nil else { return nil }
        var value = draft; value.position = Int(positionText.trimmingCharacters(in: .whitespaces))
        do { _ = try value.validated(); return L10n.text("Enter a whole number for the position.") } catch { return readErrorMessage(error) }
    }
    func review() async {
        guard !working, !attempted, let plan else { return }
        working = true; errorMessage = nil; defer { working = false }
        do { try await client.checkDeviceCreation(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil; defer { working = false }
        do { created = try await client.createDevice(reviewed) } catch { errorMessage = readErrorMessage(error) }
    }
}

struct DeviceCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeviceCreateModel
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, site: ReferenceSelection? = nil, rack: ReferenceSelection? = nil) {
        _model = State(initialValue: DeviceCreateModel(client: client, site: site, rack: rack))
    }
    private func picker(_ title: String, path: String, selection: Binding<ReferenceSelection?>, required: [URLQueryItem] = [], allowsEmpty: Bool = false, identifier: String) -> some View {
        NavigationLink {
            ReferencePickerView(client: model.client, path: path, title: title, selection: selection, emptyTitle: "None", allowsEmpty: allowsEmpty, required: required)
        } label: { HStack { Text(L10n.text(title)); Spacer(); Text(selection.wrappedValue?.title ?? L10n.text(allowsEmpty ? "None" : "Choose")).foregroundStyle(.secondary) } }
            .accessibilityIdentifier(identifier)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(model.client.serverDisplay).font(.caption) }
                if let created = model.created {
                    Section {
                        Label("Device created", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("deviceCreated")
                        NavigationLink("Open created device") { InventoryDetailView(service: InventoryService(client: model.client, kind: .devices), id: created.id) }
                            .accessibilityIdentifier("openCreatedDevice")
                        Button("Done") { dismiss() }
                    }
                } else if let plan = model.reviewed {
                    Section("Device review") {
                        DetailField(title: "Name", value: plan.name.isEmpty ? L10n.text("Unnamed device") : plan.name)
                        DetailField(title: "Device type", value: plan.deviceType?.title ?? "—")
                        DetailField(title: "Role", value: plan.role?.title ?? "—")
                        DetailField(title: "Site", value: plan.site?.title ?? "—")
                        DetailField(title: "Rack", value: plan.rack.map { $0.title + (plan.position.map { " · U\($0)" } ?? "") + (plan.face.isEmpty ? "" : " · " + L10n.text(plan.face.capitalized)) } ?? "—")
                        DetailField(title: "Status", value: L10n.text(plan.status.capitalized))
                        if !plan.serial.isEmpty { DetailField(title: "Serial", value: plan.serial) }
                        if !plan.assetTag.isEmpty { DetailField(title: "Asset tag", value: plan.assetTag) }
                        if let tenant = plan.tenant { DetailField(title: "Tenant", value: tenant.title) }
                        if !plan.description.isEmpty { DetailField(title: "Description", value: plan.description) }
                    }
                    Section {
                        Text("This creates one device record in NetBox. Nothing is configured on the equipment; NetBox checks rack space and uniqueness again.").font(.caption)
                        if !model.attempted {
                            Button("Confirm creation") { operation = .create(UUID()) }.accessibilityIdentifier("confirmDeviceCreation")
                            Button("Back to editing") { model.back() }
                        }
                    }
                } else {
                    Section("Identity") {
                        TextField("Name (optional)", text: $model.draft.name).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("deviceCreationName")
                        picker("Device type", path: "dcim/device-types/", selection: $model.draft.deviceType, identifier: "deviceCreationType")
                        picker("Role", path: "dcim/device-roles/", selection: $model.draft.role, identifier: "deviceCreationRole")
                        Picker("Status", selection: $model.draft.status) { ForEach(InventoryKind.devices.statuses, id: \.self) { Text(L10n.text($0.capitalized)).tag($0) } }
                    }
                    Section("Location") {
                        picker("Site", path: "dcim/sites/", selection: $model.draft.site, identifier: "deviceCreationSite")
                        if let site = model.draft.site {
                            picker("Rack", path: "dcim/racks/", selection: $model.draft.rack, required: [.init(name: "site_id", value: String(site.id))], allowsEmpty: true, identifier: "deviceCreationRack")
                        }
                        if model.draft.rack != nil {
                            TextField("Position (U, optional)", text: $model.positionText).keyboardType(.numberPad).accessibilityIdentifier("deviceCreationPosition")
                            Picker("Face", selection: $model.draft.face) { Text("None").tag(""); Text("Front").tag("front"); Text("Rear").tag("rear") }
                        }
                    }
                    Section("Details") {
                        TextField("Serial", text: $model.draft.serial).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Asset tag", text: $model.draft.assetTag).textInputAutocapitalization(.never).autocorrectionDisabled()
                        picker("Tenant", path: "tenancy/tenants/", selection: $model.draft.tenant, allowsEmpty: true, identifier: "deviceCreationTenant")
                        TextField("Description", text: $model.draft.description, axis: .vertical).lineLimit(2...5)
                    }
                    Section {
                        if let message = model.validationMessage { Text(message).font(.caption).foregroundStyle(.red) }
                        Button("Review device") { operation = .review(UUID()) }.disabled(model.plan == nil || model.working).accessibilityIdentifier("reviewDeviceCreation")
                    }
                }
                if let error = model.errorMessage { Section { StatusMessage(message: error) } }
                if model.attempted && model.created == nil && !model.working {
                    Section { Text("Creation was not confirmed. Check the devices in NetBox before trying again; the request may have succeeded.").font(.callout) }
                }
                if model.working { ProgressView("Loading…") }
            }
            .disabled(model.working || (model.attempted && model.created == nil))
            .navigationTitle("New device").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
            .interactiveDismissDisabled(model.working)
            .onChange(of: model.draft.site) { model.draft.rack = nil; model.positionText = "" }
            .task(id: operation) { switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() } }
        }
    }
}
