import SwiftUI

struct IPAMDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var deleted = false
    var onDeleted: (() -> Void)?
    @State private var model: IPAMDetailModel
    @State private var refreshID = UUID()
    @State private var ipamField: IPAMEditField?
    @State private var structuredField: StructuredEditField?
    @State private var editingField: EditableTextField?
    @State private var allocating: NextAvailableMode?
    @State private var pendingCreation: IPAMCreationPrefill?
    @State private var creation: IPAMCreationPrefill?
    private let service: IPAMService
    private let kind: IPAMKind
    init(service: IPAMService, id: Int, onDeleted: (() -> Void)? = nil) {
        self.service = service
        self.onDeleted = onDeleted
        kind = service.kind
        _model = State(initialValue: IPAMDetailModel(service: service, id: id))
    }
    private struct Field: Identifiable { let id: String; let value: String }
    private func fields(_ object: IPAMObject) -> [Field] {
        var fields = [Field(id: "ID", value: String(object.id)),
                      Field(id: "Family", value: object.family?.text ?? "—"),
                      Field(id: "Status", value: object.status?.text ?? "—"),
                      Field(id: "VRF", value: object.vrf?.text ?? L10n.text("Global")),
                      Field(id: "Tenant", value: object.tenant?.text ?? "—"),
                      Field(id: "Role", value: object.role?.text ?? "—")]
        if kind == .prefixes {
            fields += [Field(id: "VLAN", value: object.vlan?.text ?? "—"),
                       Field(id: "Scope", value: object.scope?.text ?? "—")]
        } else {
            fields += [Field(id: "DNS name", value: object.dnsName ?? "—"),
                       Field(id: "Assigned object", value: object.assignedObject?.text ?? "—")]
        }
        return fields
    }
    private func editAction(_ field: String) -> (() -> Void)? {
        switch field {
        case "VRF": return { ipamField = .vrf }
        case "VLAN" where kind == .prefixes: return { ipamField = .vlan }
        case "Role" where kind == .prefixes: return { ipamField = .role }
        case "Scope" where kind == .prefixes: return { ipamField = .scope }
        case "Status": return { structuredField = .status }
        case "Tenant": return { structuredField = .tenant }
        case "DNS name" where kind == .ipAddresses: return { editingField = .dnsName }
        case "Assigned object" where kind == .ipAddresses: return { structuredField = .assignment }
        default: return nil
        }
    }
    @ViewBuilder private func related(_ object: IPAMObject) -> some View {
        Section("Explore") {
            if let vrf = object.vrf, let id = vrf.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .vrfs), id: id) } label: { Label(vrf.text, systemImage: ContextKind.vrfs.symbol) }.accessibilityIdentifier("ipamVRF")
            }
            if let tenant = object.tenant, let id = tenant.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: ContextKind.tenants.symbol) }
            }
            if kind == .prefixes, let role = object.role, let id = role.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .roles), id: id) } label: { Label(role.text, systemImage: ContextKind.roles.symbol) }
            }
            if kind == .prefixes, let vlan = object.vlan, let id = vlan.id, id > 0 {
                NavigationLink { VLANDetailView(service: VLANBrowseService(client: service.client, kind: .vlans), id: id) } label: { Label(vlan.text, systemImage: "square.stack.3d.up") }.accessibilityIdentifier("prefixVLAN")
            }
            if kind == .prefixes, let context = object.networkContext {
                NavigationLink {
                    IPAMListView(service: IPAMService(client: service.client, kind: .prefixes, context: context))
                } label: { Label("Contained prefixes", systemImage: "square.stack.3d.up") }
                .accessibilityIdentifier("prefixChildren")
                NavigationLink {
                    IPAMListView(service: IPAMService(client: service.client, kind: .ipAddresses, context: context))
                } label: { Label("Contained IP addresses", systemImage: "number") }
                .accessibilityIdentifier("prefixIPs")
            }
            if kind == .ipAddresses, let (interface, id) = object.interfaceAssignment {
                NavigationLink {
                    InterfaceDetailView(service: InterfaceService(client: service.client, kind: interface), id: id)
                } label: { Label(object.assignedObject?.text ?? L10n.text("Assigned interface"), systemImage: "network") }
                .accessibilityIdentifier("ipAssignedInterface")
            }
            if kind == .prefixes { ObjectScopeLink(client: service.client, type: object.scopeType, id: object.scope?.id, reference: object.scope) }
        }
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { refreshID = UUID() }
            }
            if let object = model.object {
                related(object)
                Section("Overview") {
                    Text(object.title).font(.title3.weight(.semibold)).monospaced().textSelection(.enabled)
                        .accessibilityIdentifier("ipamDetailTitle")
                    DetailField(title: kind == .prefixes ? "Prefix" : "IP address", value: object.title, action: { ipamField = .cidr }, identifier: "ipamField-CIDR")
                    ForEach(fields(object)) { field in
                        DetailField(title: field.id, value: field.value, action: editAction(field.id), identifier: field.id == "DNS name" ? "ipamDNSName" : "ipamField-\(field.id)").disabled(model.isLoading)
                    }
                }
                Section("Description") {
                    DetailField(title: "Description", value: object.description?.isEmpty == false ? object.description ?? "" : "—", action: { editingField = .description }, identifier: "ipamField-Description")
                        .disabled(model.isLoading)
                }
                if let tags = object.tags, !tags.isEmpty {
                    Section("Tags") { Text(tags.map(\.text).joined(separator: ", ")) }
                }
                Section("Comments") {
                    DetailField(title: "Comments", value: object.comments?.isEmpty == false ? object.comments ?? "" : "—", action: { editingField = .comments }, identifier: "ipamField-Comments")
                        .disabled(model.isLoading)
                }
            }
        }
        .navigationTitle(L10n.text(kind == .prefixes ? "Prefix" : "IP address"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $allocating, onDismiss: { creation = pendingCreation; pendingCreation = nil }) { mode in
            if let object = model.object, let text = object.prefix, let parent = try? IPAMCIDR(text, network: true) {
                NextAvailableView(client: service.client, prefixID: object.id, parent: parent, vrf: object.vrf, mode: mode) { pendingCreation = $0 }
            }
        }
        .sheet(item: $creation, onDismiss: { refreshID = UUID() }) { prefill in
            if let object = model.object {
                IPAMCreateView(client: service.client, kind: prefill.kind,
                               vrf: object.vrf.flatMap { vrf in vrf.id.map { ReferenceSelection(id: $0, title: vrf.text) } },
                               tenant: object.tenant.flatMap { tenant in tenant.id.map { ReferenceSelection(id: $0, title: tenant.text) } },
                               cidr: prefill.cidr)
            }
        }
        .sheet(item: $ipamField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object { IPAMEditView(client: service.client, kind: kind, id: object.id, field: field) }
        }
        .sheet(item: $editingField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object {
                TextEditView(client: service.client, target: TextEditTarget(collection: kind == .prefixes ? .prefixes : .ipAddresses, id: object.id), field: field)
            }
        }
        .sheet(item: $structuredField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object {
                StructuredEditView(client: service.client, target: StructuredEditTarget(collection: kind == .prefixes ? .prefixes : .ipAddresses, id: object.id), field: field)
            }
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss() } else { refreshID = UUID() } }) {
            if let object = model.object {
                DeletionView(client: service.client, target: DeletionTarget(collection: kind == .prefixes ? .prefixes : .ipAddresses, id: object.id)) { deleted = true; onDeleted?() }
            }
        }
        .toolbar {
            Menu {
                if kind == .prefixes {
                    Button("Next available IP", systemImage: "plus.circle") { allocating = .ip }.accessibilityIdentifier("nextAvailableIP")
                    Button("Next available prefix", systemImage: "plus.square.on.square") { allocating = .prefix }.accessibilityIdentifier("nextAvailablePrefix")
                    Divider()
                }
                Button("Delete object", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteObject")
                Button("Address / prefix") { ipamField = .cidr }
                Button("VRF") { ipamField = .vrf }
                if kind == .prefixes {
                    Button("VLAN") { ipamField = .vlan }; Button("Role") { ipamField = .role }; Button("Scope") { ipamField = .scope }
                }
                Button("Edit status") { structuredField = .status }.accessibilityIdentifier("editStatus")
                Button("Edit tenant") { structuredField = .tenant }.accessibilityIdentifier("editTenant")
                if kind == .ipAddresses { Button("Edit assignment") { structuredField = .assignment }.accessibilityIdentifier("editAssignment") }
                Button("Edit description") { editingField = .description }.accessibilityIdentifier("editDescription")
                Button("Edit comments") { editingField = .comments }.accessibilityIdentifier("editComments")
                if kind == .ipAddresses { Button("Edit DNS name") { editingField = .dnsName }.accessibilityIdentifier("editDNSName") }
            } label: { Label("Edit", systemImage: "square.and.pencil") }
            .disabled(model.object == nil || model.isLoading).accessibilityIdentifier("editObject")
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .disabled(model.isLoading)
        }
        .task(id: refreshID) { await model.reload() }
        .refreshable { await model.reload() }
    }
}
