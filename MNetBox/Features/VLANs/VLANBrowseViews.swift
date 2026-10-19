import SwiftUI

struct VLANListView: View {
    let service: VLANBrowseService
    let allowsCreation: Bool
    @State private var creating = false
    @State private var model: PaginatedListModel<VLANBrowseRecord, VLANBrowseQuery>
    @State private var query = VLANBrowseQuery()
    @State private var refresh = UUID()
    @State private var page = 0
    private struct Request: Equatable { let query: VLANBrowseQuery; let refresh: UUID }
    init(service: VLANBrowseService, allowsCreation: Bool = true) {
        self.service = service; self.allowsCreation = allowsCreation
        _model = State(initialValue: PaginatedListModel(query: VLANBrowseQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    private func reference(_ title: String, path: String, selection: Binding<ReferenceSelection?>, zero: String? = nil) -> some View {
        NavigationLink {
            ReferencePickerView(client: service.client, path: path, title: title, selection: selection, zeroTitle: zero)
        } label: {
            HStack { Text(L10n.text(title)); Spacer(); Text(selection.wrappedValue?.title ?? L10n.text("All")).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("vlanFilter-\(title)")
    }
    var body: some View {
        List {
            if let context = service.fixedGroup ?? service.fixedSite ?? service.fixedTenant ?? service.fixedRole { Section { Label(context.title, systemImage: "square.stack.3d.up") } }
            Section("Filters") {
                if service.kind == .vlans {
                    Picker("Status", selection: $query.status) {
                        Text("All").tag("")
                        ForEach(["active", "reserved", "deprecated"], id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                    }
                    if service.fixedSite == nil { reference("Site", path: "dcim/sites/", selection: $query.site, zero: "No direct site") }
                    if service.fixedGroup == nil { reference("VLAN group", path: "ipam/vlan-groups/", selection: $query.group, zero: "Ungrouped") }
                    if service.fixedRole == nil { reference("Role", path: "ipam/roles/", selection: $query.role) }
                }
                if service.fixedTenant == nil { reference("Tenant", path: "tenancy/tenants/", selection: $query.tenant) }
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { if model.failedLoadingMore { page += 1 } else { refresh = UUID() } }
            }
            Section {
                ForEach(model.objects) { object in
                    NavigationLink { VLANDetailView(service: service, id: object.id, onDeleted: { refresh = UUID() }) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(object.title, systemImage: service.kind == .vlans ? "square.stack.3d.up" : "folder")
                            Text(service.kind == .vlans ? [object.site?.text ?? L10n.text("No direct site"), object.group?.text ?? L10n.text("Ungrouped")].joined(separator: " · ") : object.scopeText)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("vlanObject-\(service.kind.rawValue)-\(object.id)")
                }
                if model.hasLoaded, model.objects.isEmpty, !model.isLoading { ContentUnavailableView.search(text: query.search) }
                if model.next != nil {
                    if model.isLoadingMore { ProgressView("Loading more…") }
                    else { Button("Load more") { page += 1 }.disabled(model.isLoading).accessibilityIdentifier("vlanLoadMore") }
                }
            } header: { if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)) } }
        }
        .navigationTitle(service.kind.title)
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search NetBox")
         .toolbar {
            if allowsCreation, service.fixedGroup == nil, service.fixedSite == nil, service.fixedTenant == nil, service.fixedRole == nil {
                Button(service.kind == .vlans ? "New VLAN" : "New VLAN group", systemImage: "plus") { creating = true }.accessibilityIdentifier(service.kind == .vlans ? "createVLAN" : "createVLANGroup")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading)
        }
        .sheet(isPresented: $creating, onDismiss: { refresh = UUID() }) { if service.kind == .vlans { NetworkCreateView(client: service.client) } else { VLANGroupCreateView(client: service.client) } }
        .task(id: Request(query: query, refresh: refresh)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: query)
            } catch { /* A newer query cancels the debounce. */ }
        }
        .task(id: page) { if page > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: query) }
    }
}

struct VLANDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var deleted = false
    let onDeleted: () -> Void
    @State private var textField: EditableTextField?
    @State private var adminField: VLANAdminField?
    @State private var relationField: StructuredEditField?
    let service: VLANBrowseService
    @State private var model: ReadDetailModel<VLANBrowseRecord>
    @State private var refresh = UUID()
    init(service: VLANBrowseService, id: Int, onDeleted: @escaping () -> Void = {}) {
        self.onDeleted = onDeleted
        self.service = service
        _model = State(initialValue: ReadDetailModel(fetch: { try await service.detail(id: id) }))
    }
    private func vlanLink(_ reference: NetBoxLabel) -> some View {
        NavigationLink { VLANDetailView(service: VLANBrowseService(client: service.client, kind: .vlans), id: reference.id ?? 0) } label: {
            Label(reference.text, systemImage: "square.stack.3d.up")
        }
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { refresh = UUID() }
            }
            if let object = model.object {
                Section("Overview") {
                    Label(object.title, systemImage: service.kind == .vlans ? "square.stack.3d.up" : "folder").font(.title3.bold()).accessibilityIdentifier("vlanDetailTitle")
                    DetailField(title: "ID", value: "#\(object.id)")
                    DetailField(title: "Tenant", value: object.tenant?.text ?? "—", action: { if service.kind == .vlans { relationField = .tenant } else { adminField = .tenant } }, identifier: "vlanTenant")
                    if service.kind == .vlans {
                        DetailField(title: "VLAN ID", value: object.vid.map(String.init) ?? "—", action: { adminField = .vid }, identifier: "vlanVID")
                        DetailField(title: "Name", value: object.name, action: { textField = .name }, identifier: "vlanName")
                        DetailField(title: "Status", value: object.status?.text ?? "—", action: { textField = .status }, identifier: "vlanStatus")
                        DetailField(title: "Role", value: object.role?.text ?? "—", action: { relationField = .role }, identifier: "vlanRole")
                        DetailField(title: "Site", value: object.site?.text ?? (object.knownFields.contains("site") ? L10n.text("No direct site") : "—"), action: { adminField = .site }, identifier: "vlanSite")
                        DetailField(title: "VLAN group", value: object.group?.text ?? (object.knownFields.contains("group") ? L10n.text("Ungrouped") : "—"), action: { adminField = .group }, identifier: "vlanGroupField")
                        DetailField(title: "QinQ role", value: object.qinqRole?.text ?? "—")
                        DetailField(title: "Prefixes", value: object.prefixCount.map(String.init) ?? "—")
                    } else {
                        DetailField(title: "Name", value: object.name, action: { textField = .name }, identifier: "groupName")
                        DetailField(title: "Slug", value: object.slug ?? "—", action: { adminField = .slug }, identifier: "groupSlug")
                        DetailField(title: "Scope", value: object.scopeText.isEmpty ? "—" : object.scopeText, action: { adminField = .scope }, identifier: "groupScope")
                        DetailField(title: "VLAN ID ranges", value: object.vidRanges?.map { "\($0[0])–\($0[1])" }.joined(separator: ", ") ?? "—", action: { adminField = .ranges }, identifier: "groupRanges")
                        DetailField(title: "VLANs", value: object.vlanCount.map(String.init) ?? "—")
                        DetailField(title: "Total VLAN IDs", value: object.totalVLANIDs.map(String.init) ?? "—")
                        DetailField(title: "Utilization", value: object.utilization?.text ?? "—")
                    }
                }
                Section("Explore") {
                    if let tenant = object.tenant, let id = tenant.id, id > 0 {
                        NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: ContextKind.tenants.symbol) }
                    }
                    if let role = object.role, let id = role.id, id > 0 {
                        NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .roles), id: id) } label: { Label(role.text, systemImage: ContextKind.roles.symbol) }
                    }
                    if service.kind == .groups {
                        NavigationLink { VLANListView(service: VLANBrowseService(client: service.client, kind: .vlans, fixedGroup: ReferenceSelection(id: object.id, title: object.title))) } label: { Label("VLANs", systemImage: "square.stack.3d.up") }
                            .accessibilityIdentifier("groupVLANs")
                        ObjectScopeLink(client: service.client, type: object.scopeType, id: object.scopeID, reference: object.scope)
                    } else {
                        if let site = object.site, let id = site.id, id > 0 {
                            NavigationLink { InventoryDetailView(service: InventoryService(client: service.client, kind: .sites), id: id) } label: { Label(site.text, systemImage: InventoryKind.sites.symbol) }
                        }
                        if let group = object.group, let id = group.id, id > 0 {
                            NavigationLink { VLANDetailView(service: VLANBrowseService(client: service.client, kind: .groups), id: id) } label: { Label(group.text, systemImage: "folder") }.accessibilityIdentifier("vlanGroup")
                        }
                        if let svlan = object.qinqSVLAN, (svlan.id ?? 0) > 0 { vlanLink(svlan) }
                        NavigationLink { IPAMListView(service: IPAMService(client: service.client, kind: .prefixes, context: .vlan(id: object.id, title: object.title)), allowsCreation: false) } label: { Label("Prefixes", systemImage: "square.stack.3d.up.fill") }.accessibilityIdentifier("vlanPrefixes")
                        ForEach([InterfaceKind.physical, .virtual], id: \.rawValue) { kind in
                            NavigationLink { InterfaceListView(service: InterfaceService(client: service.client, kind: kind, vlanID: object.id), title: object.title, allowsCreation: false) } label: { Label(L10n.text(kind == .physical ? "Device interfaces" : "VM interfaces"), systemImage: kind.parentKind.symbol) }.accessibilityIdentifier("vlanInterfaces-\(kind.rawValue)")
                        }
                        Text("Only explicit VLAN assignments are listed. Tagged-all interfaces may carry other VLANs.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Description") { DetailField(title: "Description", value: object.description?.isEmpty == false ? object.description ?? "" : "—", action: { textField = .description }, identifier: "vlanDescription") }
                Section("Comments") { DetailField(title: "Comments", value: object.comments?.isEmpty == false ? object.comments ?? "" : "—", action: { textField = .comments }, identifier: "vlanComments") }
                if let tags = object.tags, !tags.isEmpty { Section("Tags") { Text(tags.map(\.text).joined(separator: ", ")) } }
            }
        }
        .navigationTitle(service.kind.singular)
        .sheet(item: $textField, onDismiss: { refresh = UUID() }) { field in
            if let object = model.object { TextEditView(client: service.client, target: TextEditTarget(collection: service.kind == .vlans ? .vlans : .vlanGroups, id: object.id), field: field) }
        }
        .sheet(item: $adminField, onDismiss: { refresh = UUID() }) { field in
            if let object = model.object { VLANAdminView(client: service.client, kind: service.kind, id: object.id, field: field) }
        }
        .sheet(item: $relationField, onDismiss: { refresh = UUID() }) { field in
            if let object = model.object { StructuredEditView(client: service.client, target: StructuredEditTarget(collection: .vlans, id: object.id), field: field) }
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss(); onDeleted() } else { refresh = UUID() } }) {
            if let object = model.object { DeletionView(client: service.client, target: .init(collection: service.kind == .vlans ? .vlans : .vlanGroups, id: object.id)) { deleted = true } }
        }
        .toolbar {
            if let object = model.object, !model.isLoading, model.errorMessage == nil {
                Menu("Edit", systemImage: "square.and.pencil") {
                    ForEach(VLANAdminField.allCases.filter { $0.supports(service.kind) }) { field in Button(field.title) { adminField = field } }
                    Button("Name") { textField = .name }
                    Button("Description") { textField = .description }
                    Button("Comments") { textField = .comments }
                    if service.kind == .vlans { Button("Status") { textField = .status }; Button("Tenant") { relationField = .tenant }; Button("Role") { relationField = .role } }
                }.accessibilityIdentifier("vlanEditMenu-\(object.id)")
            }
            if model.object != nil, !model.isLoading, model.errorMessage == nil {
                Button("Delete object", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier(service.kind == .vlans ? "deleteVLAN" : "deleteVLANGroup")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) { await model.reload() }
        .refreshable { await model.reload() }
    }
}
