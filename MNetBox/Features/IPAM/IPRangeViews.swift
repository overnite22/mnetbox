import SwiftUI

struct IPRangeListView: View {
    let service: IPRangeService
    @State private var query = IPRangeQuery()
    @State private var model: PaginatedListModel<IPRangeObject, IPRangeQuery>
    @State private var refresh = UUID()
    @State private var more = 0
    private struct Request: Equatable { let query: IPRangeQuery; let refresh: UUID }
    init(client: APIClient) {
        let service = IPRangeService(client: client)
        self.service = service
        _model = State(initialValue: PaginatedListModel(query: IPRangeQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        List {
            Section("Filters") {
                Picker("IP family", selection: $query.family) {
                    Text("All").tag(""); Text("IPv4").tag("4"); Text("IPv6").tag("6")
                }
                NavigationLink {
                    ReferencePickerView(client: service.client, path: "ipam/vrfs/", title: "VRF", selection: $query.vrf, allowsGlobal: true)
                } label: { HStack { Text("VRF"); Spacer(); Text(query.vrf?.title ?? L10n.text("All")).foregroundStyle(.secondary) } }
                NavigationLink {
                    ReferencePickerView(client: service.client, path: "tenancy/tenants/", title: "Tenant", selection: $query.tenant)
                } label: { HStack { Text("Tenant"); Spacer(); Text(query.tenant?.title ?? L10n.text("All")).foregroundStyle(.secondary) } }
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                Button("Retry") { if model.failedLoadingMore { more += 1 } else { refresh = UUID() } }
            }
            Section {
                ForEach(model.objects) { object in
                    NavigationLink { IPRangeDetailView(service: service, id: object.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(object.title).font(.headline).monospaced()
                            Text([object.status?.text, object.vrf?.text].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            if let description = object.description, !description.isEmpty { Text(description).font(.subheadline) }
                        }
                    }.accessibilityIdentifier("ipRange-\(object.id)")
                }
                if model.hasLoaded {
                    Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)).font(.caption).foregroundStyle(.secondary)
                    if model.objects.isEmpty { Text("No results") }
                }
                if model.next != nil {
                    Button("Load more") { more += 1 }.disabled(model.isLoading || model.isLoadingMore).accessibilityIdentifier("ipRangesLoadMore")
                }
                if model.isLoadingMore { ProgressView("Loading…") }
            }
        }
        .navigationTitle("IP ranges").searchable(text: $query.search, prompt: "Search")
        .task(id: Request(query: query, refresh: refresh)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation(); await model.reload(query: query)
            } catch { /* Superseded search. */ }
        }
        .task(id: more) { if more > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: query) }
    }
}

struct IPRangeDetailView: View {
    let service: IPRangeService
    @State private var model: ReadDetailModel<IPRangeObject>
    @State private var refresh = UUID()
    init(service: IPRangeService, id: Int) {
        self.service = service
        _model = State(initialValue: ReadDetailModel { try await service.detail(id: id) })
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage { StatusMessage(message: error); Button("Retry") { refresh = UUID() } }
            if let object = model.object, model.errorMessage == nil {
                Section {
                    Text(object.title).font(.headline).monospaced().textSelection(.enabled)
                    Text(verbatim: "#\(object.id)").font(.caption)
                    DetailField(title: "IP family", value: object.family.text)
                    DetailField(title: "Status", value: object.status?.text ?? "—")
                    DetailField(title: "VRF", value: object.vrf?.text ?? L10n.text("Global VRF"))
                    DetailField(title: "Tenant", value: object.tenant?.text ?? L10n.text("No tenant"))
                    DetailField(title: "Role", value: object.role?.text ?? "—")
                }
                if let vrf = object.vrf, let id = vrf.id {
                    NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .vrfs), id: id) } label: { Label(vrf.text, systemImage: "network") }
                }
                if let tenant = object.tenant, let id = tenant.id {
                    NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: "person.2") }
                }
                Section("Description") { Text(object.description?.isEmpty == false ? object.description ?? "" : "—").textSelection(.enabled) }
                Section("Comments") { Text(object.comments?.isEmpty == false ? object.comments ?? "" : "—").textSelection(.enabled) }
                if let tags = object.tags, !tags.isEmpty { Section("Tags") { Text(tags.map(\.text).joined(separator: ", ")) } }
                if object.markPopulated == true || object.markUtilized == true {
                    Section { Text("This range is marked populated or utilized in NetBox. These marks do not measure live network activity.").font(.caption) }
                }
            }
        }.navigationTitle("IP range").navigationBarTitleDisplayMode(.inline)
            .task(id: refresh) { await model.reload() }
            .refreshable { await model.reload() }
    }
}
