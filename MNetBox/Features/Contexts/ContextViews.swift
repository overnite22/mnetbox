import SwiftUI

struct ContextListView: View {
    let service: ContextService
    let allowsCreation: Bool
    @State private var creating = false
    @State private var needsDeletionRefresh = false
    @State private var model: PaginatedListModel<ContextRecord, ContextQuery>
    @State private var query = ContextQuery()
    @State private var refresh = UUID()
    @State private var page = 0
    private struct Request: Equatable { let query: ContextQuery; let refresh: UUID }
    init(service: ContextService, allowsCreation: Bool = true) {
        self.allowsCreation = allowsCreation
        self.service = service
        _model = State(initialValue: PaginatedListModel(query: ContextQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        List {
            if let scope = service.scope { Section { Label(scope.title, systemImage: service.kind.symbol) } }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { if model.failedLoadingMore { page += 1 } else { refresh = UUID() } }
            }
            Section {
                ForEach(model.objects) { row in
                    NavigationLink { ContextDetailView(service: service, id: row.id, onDeleted: { needsDeletionRefresh = true }) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                if let rd = row.rd { Text(rd).font(.caption).monospaced().foregroundStyle(.secondary) }
                                if let site = row.site ?? row.tenant ?? row.group { Text(site.text).font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: { Image(systemName: service.kind.symbol) }
                    }.accessibilityIdentifier("contextObject-\(service.kind.rawValue)-\(row.id)")
                }
                if model.hasLoaded, model.objects.isEmpty, !model.isLoading { ContentUnavailableView.search(text: query.search) }
                if model.next != nil {
                    if model.isLoadingMore { ProgressView("Loading more…") }
                    else { Button("Load more") { page += 1 }.disabled(model.isLoading).accessibilityIdentifier("contextLoadMore") }
                }
            } header: { if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)) } }
        }
        .navigationTitle(service.kind.title)
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search NetBox")
        .toolbar {
            if service.kind.writable && service.scope == nil && allowsCreation { Button("New context", systemImage: "plus") { creating = true }.accessibilityIdentifier("createContext") }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading)
        }
        .sheet(isPresented: $creating, onDismiss: { refresh = UUID() }) { ContextCreateView(client: service.client, kind: service.kind) }
        .task(id: Request(query: query, refresh: refresh)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: query)
            } catch { /* A newer query cancels the debounce. */ }
        }
        .onAppear { if needsDeletionRefresh { needsDeletionRefresh = false; refresh = UUID() } }
        .task(id: page) { if page > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: query) }
    }
}

struct ContextDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var wasDeleted = false
    @State private var editing: ContextEditField?
    let service: ContextService
    let onDeleted: () -> Void
    @State private var model: ReadDetailModel<ContextRecord>
    @State private var refresh = UUID()
    init(service: ContextService, id: Int, onDeleted: @escaping () -> Void = {}) {
        self.onDeleted = onDeleted
        self.service = service
        _model = State(initialValue: ReadDetailModel(fetch: { try await service.detail(id: id) }))
    }
    private func inventory(_ kind: InventoryKind, parent: InventoryScope.Parent, row: ContextRecord) -> some View {
        NavigationLink { InventoryListView(service: InventoryService(client: service.client, kind: kind, scope: InventoryScope(parent: parent, id: row.id, title: row.title))) } label: { Label(kind.title, systemImage: kind.symbol) }.accessibilityIdentifier("contextInventory-\(kind.rawValue)")
    }
    private func ipam(_ kind: IPAMKind, context: IPAMContext) -> some View {
        NavigationLink { IPAMListView(service: IPAMService(client: service.client, kind: kind, context: context), allowsCreation: false) } label: { Label(kind.title, systemImage: "network") }.accessibilityIdentifier("contextIPAM-\(kind.rawValue)")
    }
    private func contexts(_ kind: ContextKind, scope: ContextScope) -> some View {
        NavigationLink { ContextListView(service: ContextService(client: service.client, kind: kind, scope: scope)) } label: { Label(kind.title, systemImage: kind.symbol) }.accessibilityIdentifier("contextRelated-\(kind.rawValue)")
    }
    @ViewBuilder private func explore(_ row: ContextRecord) -> some View {
        Section("Explore") {
            switch service.kind {
            case .vrfs:
                ipam(.prefixes, context: .vrf(id: row.id, title: row.title))
                ipam(.ipAddresses, context: .vrf(id: row.id, title: row.title))
            case .tenants:
                ForEach(InventoryKind.allCases, id: \.self) { inventory($0, parent: .tenant, row: row) }
                ipam(.prefixes, context: .tenant(id: row.id, title: row.title))
                ipam(.ipAddresses, context: .tenant(id: row.id, title: row.title))
                contexts(.vrfs, scope: .init(relation: .tenant, id: row.id, title: row.title))
                contexts(.clusters, scope: .init(relation: .tenant, id: row.id, title: row.title))
                contexts(.locations, scope: .init(relation: .tenant, id: row.id, title: row.title))
                NavigationLink { VLANListView(service: VLANBrowseService(client: service.client, kind: .vlans, fixedTenant: .init(id: row.id, title: row.title))) } label: { Label("VLANs", systemImage: "square.stack.3d.up") }
            case .roles:
                ipam(.prefixes, context: .role(id: row.id, title: row.title))
                NavigationLink { VLANListView(service: VLANBrowseService(client: service.client, kind: .vlans, fixedRole: .init(id: row.id, title: row.title))) } label: { Label("VLANs", systemImage: "square.stack.3d.up") }
            case .clusters:
                inventory(.virtualMachines, parent: .cluster, row: row)
                if let group = row.group, let id = group.id, id > 0 {
                    NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .clusterGroups), id: id) } label: { Label(group.text, systemImage: ContextKind.clusterGroups.symbol) }
                }
                ObjectScopeLink(client: service.client, type: row.scopeType, id: row.scopeID, reference: row.scope)
            case .locations:
                inventory(.racks, parent: .location, row: row)
                inventory(.devices, parent: .location, row: row)
                ipam(.prefixes, context: .scope(type: "dcim.location", id: row.id, title: row.title))
            case .regions:
                inventory(.sites, parent: .region, row: row)
                ipam(.prefixes, context: .scope(type: "dcim.region", id: row.id, title: row.title))
            case .siteGroups:
                inventory(.sites, parent: .siteGroup, row: row)
                ipam(.prefixes, context: .scope(type: "dcim.sitegroup", id: row.id, title: row.title))
            case .rackGroups: inventory(.racks, parent: .rackGroup, row: row)
            case .clusterGroups: contexts(.clusters, scope: .init(relation: .clusterGroup, id: row.id, title: row.title))
            }
            if let tenant = row.tenant, let id = tenant.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: ContextKind.tenants.symbol) }
            }
            if let site = row.site, let id = site.id, id > 0 {
                NavigationLink { InventoryDetailView(service: InventoryService(client: service.client, kind: .sites), id: id) } label: { Label(site.text, systemImage: InventoryKind.sites.symbol) }
            }
            if service.kind.hierarchical, let parent = row.parent, let id = parent.id, id > 0, id != row.id {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: service.kind), id: id) } label: { Label(parent.text, systemImage: service.kind.symbol) }.accessibilityIdentifier("contextParent")
            }
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
            if let row = model.object {
                Section { ContextGraphicHeader(kind: service.kind, row: row) }
                explore(row)
                Section("Overview") {
                    Label(row.title, systemImage: service.kind.symbol).font(.title3.bold()).accessibilityIdentifier("contextDetailTitle")
                    DetailField(title: "ID", value: "#\(row.id)")
                    if service.kind.writable {
                        DetailField(title: "Name", value: row.name, action: { editing = .name }, identifier: "contextField-name")
                        if service.kind != .vrfs { DetailField(title: "Slug", value: row.slug ?? "—", action: { editing = .slug }, identifier: "contextField-slug") }
                        if service.kind == .roles { DetailField(title: "Weight", value: row.weight.map(String.init) ?? "—", action: { editing = .weight }, identifier: "contextField-weight") }
                        if service.kind == .vrfs { DetailField(title: "Tenant", value: row.tenant?.text ?? L10n.text("None"), action: { editing = .tenant }, identifier: "contextField-tenant") }
                        if service.kind == .tenants { DetailField(title: "Tenant group", value: row.group?.text ?? L10n.text("None"), action: { editing = .group }, identifier: "contextField-group") }
                    }
                    if service.kind == .vrfs {
                        DetailField(title: "Route distinguisher", value: row.rd ?? "—")
                        DetailField(title: "Enforce unique", value: row.enforceUnique.map { L10n.text($0 ? "Yes" : "No") } ?? "—")
                        DetailField(title: "Import targets", value: row.importTargets?.map(\.text).joined(separator: ", ") ?? "—")
                        DetailField(title: "Export targets", value: row.exportTargets?.map(\.text).joined(separator: ", ") ?? "—")
                    }
                    if service.kind == .clusters {
                        DetailField(title: "Type", value: row.type?.text ?? "—")
                        DetailField(title: "Scope", value: row.scopeText.isEmpty ? "—" : row.scopeText)
                        DetailField(title: "Allocated vCPUs", value: row.allocatedVCPUs?.text ?? "—")
                    }
                    if let status = row.status { DetailField(title: "Status", value: status.text) }
                    if let tenant = row.tenant { DetailField(title: "Tenant", value: tenant.text) }
                    if let group = row.group { DetailField(title: "Group", value: group.text) }
                    if let site = row.site { DetailField(title: "Site", value: site.text) }
                    if service.kind.hierarchical { Text("Linked inventory includes descendants. Prefix scope links use the exact selected scope.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Description") { DetailField(title: "Description", value: row.description?.isEmpty == false ? row.description ?? "" : "—", action: service.kind.writable ? { editing = .description } : nil, identifier: "contextField-description") }
                Section("Comments") { DetailField(title: "Comments", value: row.comments?.isEmpty == false ? row.comments ?? "" : "—", action: service.kind.writable ? { editing = .comments } : nil, identifier: "contextField-comments") }
                if let tags = row.tags, !tags.isEmpty { Section("Tags") { Text(tags.map(\.text).joined(separator: ", ")) } }
            }
        }
        .navigationTitle(service.kind.title)
        .toolbar {
            if (service.kind == .vrfs || service.kind == .roles), model.object != nil, !model.isLoading, model.errorMessage == nil {
                Button("Delete object", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteContext")
            }
            if service.kind.writable, model.object != nil, !model.isLoading, model.errorMessage == nil {
                Menu("Edit", systemImage: "square.and.pencil") { ForEach(ContextEditField.allCases.filter { $0.supports(service.kind) }) { field in Button(field.title) { editing = field } } }.accessibilityIdentifier("contextEditMenu")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading)
        }
        .sheet(isPresented: $deleting, onDismiss: { if wasDeleted { dismiss() } else { refresh = UUID() } }) {
            if let row = model.object { DeletionView(client: service.client, target: .init(collection: service.kind == .vrfs ? .vrfs : .ipamRoles, id: row.id), onDeleted: { wasDeleted = true; onDeleted() }) }
        }
        .sheet(item: $editing, onDismiss: { refresh = UUID() }) { field in
            if let row = model.object { ContextEditView(client: service.client, kind: service.kind, id: row.id, field: field) }
        }
        .task(id: refresh) { await model.reload() }
        .refreshable { await model.reload() }
    }
}

struct ObjectScopeLink: View {
    let client: APIClient
    let type: String?
    let id: Int?
    let reference: NetBoxLabel?
    var body: some View {
        if let id, id > 0, reference?.id == id {
            if type == "dcim.site" || type == "dcim.rack" {
                let kind: InventoryKind = type == "dcim.site" ? .sites : .racks
                NavigationLink { InventoryDetailView(service: InventoryService(client: client, kind: kind), id: id) } label: { Label(reference?.text ?? "#\(id)", systemImage: kind.symbol) }.accessibilityIdentifier("objectScope")
            } else if let kind = ContextKind.scope(type) {
                NavigationLink { ContextDetailView(service: ContextService(client: client, kind: kind), id: id) } label: { Label(reference?.text ?? "#\(id)", systemImage: kind.symbol) }.accessibilityIdentifier("objectScope")
            }
        }
    }
}
