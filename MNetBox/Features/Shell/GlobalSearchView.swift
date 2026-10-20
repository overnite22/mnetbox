import SwiftUI

struct GlobalSearchView: View {
    @State private var scanning = false
    let client: APIClient
    @State private var search = ""
    @State private var committedSearch = ""
    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if trimmedSearch.isEmpty {
                ContentUnavailableView("Search NetBox", systemImage: "magnifyingglass",
                    description: Text("Search inventory, IPAM, VLANs, MAC addresses, VRFs, tenants, clusters and locations."))
            } else if committedSearch != trimmedSearch {
                ProgressView("Loading…")
            } else {
                ForEach(InventoryKind.allCases, id: \.self) { kind in
                    InventorySearchSection(service: InventoryService(client: client, kind: kind), search: committedSearch)
                        .id("\(kind.rawValue)-\(committedSearch)")
                }
                ForEach([IPAMKind.prefixes, .ipAddresses], id: \.self) { kind in
                    IPAMSearchSection(service: IPAMService(client: client, kind: kind), search: committedSearch)
                        .id("\(kind.rawValue)-\(committedSearch)")
                }
                ForEach(VLANBrowseKind.allCases, id: \.self) { kind in
                    VLANSearchSection(service: VLANBrowseService(client: client, kind: kind), search: committedSearch)
                        .id("vlan-\(kind.rawValue)-\(committedSearch)")
                }
                CableSearchSection(client: client, search: committedSearch).id("cables-\(committedSearch)")
                MACSearchSection(client: client, search: committedSearch).id("mac-\(committedSearch)")
                ForEach(ContextKind.allCases, id: \.self) { kind in
                    ContextSearchSection(service: ContextService(client: client, kind: kind), search: committedSearch).id("context-\(kind.rawValue)-\(committedSearch)")
                }
            }
        }
        .navigationTitle("Search")
        .toolbar { Button("Scan a label", systemImage: "qrcode.viewfinder") { scanning = true }.accessibilityIdentifier("openScanner") }
        .sheet(isPresented: $scanning) { ScanLookupView(client: client) }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all NetBox")
        .task(id: trimmedSearch) {
            guard !trimmedSearch.isEmpty else { committedSearch = ""; return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()
                committedSearch = trimmedSearch
            } catch { /* A newer query cancels the debounce. */ }
        }
    }
}

private struct InventorySearchSection: View {
    let service: InventoryService
    let search: String
    @State private var model: InventoryListModel
    @State private var refresh = UUID()
    @State private var page = 0
    init(service: InventoryService, search: String) {
        self.service = service; self.search = search
        _model = State(initialValue: InventoryListModel(service: service))
    }
    var body: some View {
        Section {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { object in
                NavigationLink {
                    InventoryDetailView(service: service, id: object.id)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(object.title)
                            if let description = object.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    } icon: { Image(systemName: service.kind.symbol) }
                }.accessibilityIdentifier("global-\(service.kind.rawValue)-\(object.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        } header: {
            Text(service.kind.title)
        }
        .task(id: refresh) { await model.reload(query: InventoryQuery(search: search)) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}

private struct IPAMSearchSection: View {
    let service: IPAMService
    let search: String
    @State private var model: IPAMListModel
    @State private var refresh = UUID()
    @State private var page = 0
    init(service: IPAMService, search: String) {
        self.service = service; self.search = search
        _model = State(initialValue: IPAMListModel(service: service))
    }
    var body: some View {
        Section {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { object in
                NavigationLink {
                    IPAMDetailView(service: service, id: object.id)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(object.title).monospaced()
                            if let description = object.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    } icon: { Image(systemName: service.kind == .prefixes ? "square.stack.3d.up.fill" : "network") }
                }.accessibilityIdentifier("global-\(service.kind.rawValue)-\(object.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        } header: { Text(service.kind.title) }
        .task(id: refresh) { await model.reload(query: IPAMQuery(search: search)) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}

private struct SearchSectionStatus<Item: Codable & Sendable & Identifiable, Query: Equatable & Sendable>: View {
    let model: PaginatedListModel<Item, Query>
    let retry: () -> Void
    let more: () -> Void
    var body: some View {
        if let error = model.errorMessage {
            StatusMessage(message: error)
            if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
            Button("Retry", action: model.failedLoadingMore ? more : retry).disabled(model.isLoading || model.isLoadingMore)
        }
        if model.hasLoaded {
            Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total))
                .font(.caption).foregroundStyle(.secondary)
        }
        if model.next != nil {
            if model.isLoadingMore { ProgressView("Loading more…") }
            else { Button("Load more", action: more).disabled(model.isLoading) }
        }
    }
}


private struct VLANSearchSection: View {
    let service: VLANBrowseService
    let search: String
    @State private var model: PaginatedListModel<VLANBrowseRecord, VLANBrowseQuery>
    @State private var refresh = UUID()
    @State private var page = 0
    init(service: VLANBrowseService, search: String) {
        self.service = service; self.search = search
        _model = State(initialValue: PaginatedListModel(query: VLANBrowseQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        Section {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { object in
                NavigationLink { VLANDetailView(service: service, id: object.id, onDeleted: { refresh = UUID() }) } label: {
                    Label(object.title, systemImage: service.kind == .vlans ? "square.stack.3d.up" : "folder")
                }.accessibilityIdentifier("global-vlan-\(service.kind.rawValue)-\(object.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        } header: { Text(service.kind.title) }
        .task(id: refresh) { await model.reload(query: VLANBrowseQuery(search: search)) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}


private struct ContextSearchSection: View {
    let service: ContextService
    let search: String
    @State private var model: PaginatedListModel<ContextRecord, ContextQuery>
    @State private var refresh = UUID()
    @State private var page = 0
    init(service: ContextService, search: String) {
        self.service = service; self.search = search
        _model = State(initialValue: PaginatedListModel(query: ContextQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        Section {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { row in
                NavigationLink { ContextDetailView(service: service, id: row.id) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                            if let rd = row.rd { Text(rd).font(.caption).monospaced().foregroundStyle(.secondary) }
                            if let tenant = row.tenant { Text(tenant.text).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: service.kind.symbol) }
                }.accessibilityIdentifier("global-context-\(service.kind.rawValue)-\(row.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        } header: { Text(service.kind.title) }
        .task(id: refresh) { await model.reload(query: ContextQuery(search: search)) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}

private struct MACSearchSection: View {
    let client: APIClient
    let search: String
    @State private var model: PaginatedListModel<MACRecord, String>
    @State private var refresh = UUID()
    @State private var page = 0
    init(client: APIClient, search: String) {
        self.client = client; self.search = search
        _model = State(initialValue: PaginatedListModel(query: "", fetch: { try await MACService(client: client).page(search: $0, next: $1) }))
    }
    var body: some View {
        Section("MAC addresses") {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { mac in
                NavigationLink { MACDetailView(client: client, id: mac.id, onDeleted: { refresh = UUID() }) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(mac.macAddress, systemImage: "network").monospaced()
                        if let assignment = mac.assignedObject { Text(assignment.text).font(.caption).foregroundStyle(.secondary) }
                    }
                }.accessibilityIdentifier("global-mac-\(mac.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        }
        .task(id: refresh) { await model.reload(query: search) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}

private struct CableSearchSection: View {
    let client: APIClient
    let search: String
    @State private var model: PaginatedListModel<CableObject, CableQuery>
    @State private var refresh = UUID()
    @State private var page = 0
    init(client: APIClient, search: String) {
        self.client = client; self.search = search
        let service = CableService(client: client)
        _model = State(initialValue: PaginatedListModel(query: CableQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        Section("Cables") {
            if model.isLoading { ProgressView("Loading…") }
            ForEach(model.objects) { cable in
                NavigationLink { CableDetailView(client: client, id: cable.id) } label: { Label(cable.title, systemImage: "cable.connector") }.accessibilityIdentifier("global-cable-\(cable.id)")
            }
            SearchSectionStatus(model: model, retry: { refresh = UUID() }, more: { page += 1 })
        }.task(id: refresh) { await model.reload(query: .init(search: search)) }
        .task(id: page) { if page > 0 { await model.loadMore() } }
    }
}
