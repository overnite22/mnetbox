import SwiftUI

struct IPAMListView: View {
    let service: IPAMService
    @State private var model: IPAMListModel
    @State private var query = IPAMQuery()
    @State private var needsDeletionRefresh = false
    @State private var refreshID = UUID()
    @State private var pageRequest = 0
    @State private var creating = false
    let allowsCreation: Bool
    private struct Request: Equatable { let query: IPAMQuery; let refresh: UUID }

    init(service: IPAMService, initialQuery: IPAMQuery = IPAMQuery(), allowsCreation: Bool = true) {
        self.service = service
        self.allowsCreation = allowsCreation
        _query = State(initialValue: initialQuery)
        _model = State(initialValue: IPAMListModel(service: service))
    }

    private func reference(_ title: String, path: String, selection: Binding<ReferenceSelection?>, global: Bool = false) -> some View {
        NavigationLink {
            ReferencePickerView(client: service.client, path: path, title: title, selection: selection, allowsGlobal: global)
        } label: {
            HStack { Text(L10n.text(title)); Spacer(); Text(selection.wrappedValue?.title ?? L10n.text("All")).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("filter-\(title)")
    }

    var body: some View {
        List {
            if let context = service.context { Section { Label(context.title, systemImage: "network") } }
            Section("Filters") {
                Picker("IP family", selection: $query.family) {
                    Text("All").tag(""); Text("IPv4").tag("4"); Text("IPv6").tag("6")
                }.accessibilityIdentifier("ipamFamily")
                Picker("Status", selection: $query.status) {
                    Text("All").tag("")
                    ForEach(service.kind.statuses, id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                }.accessibilityIdentifier("ipamStatus")
                DisclosureGroup("More filters") {
                    if service.context?.locksVRF != true {
                        reference("VRF", path: "ipam/vrfs/", selection: $query.vrf, global: true)
                    }
                    reference("Tenant", path: "tenancy/tenants/", selection: $query.tenant)
                    if service.kind == .prefixes {
                        reference("Role", path: "ipam/roles/", selection: $query.role)
                        reference("Site scope", path: "dcim/sites/", selection: $query.site)
                    } else {
                        Picker("IP role", selection: $query.ipRole) {
                            Text("All").tag("")
                            ForEach(["loopback", "secondary", "anycast", "vip", "vrrp", "hsrp", "glbp", "carp"], id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                    }
                }
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                Section {
                    StatusMessage(message: error)
                    if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
                    Button("Retry") {
                        if model.failedLoadingMore, model.next != nil { pageRequest += 1 }
                        else { refreshID = UUID() }
                    }
                }
            }
            Section {
                ForEach(model.objects) { object in
                    NavigationLink {
                        IPAMDetailView(service: service, id: object.id, onDeleted: { needsDeletionRefresh = true })
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(object.title).font(.headline).monospaced()
                            HStack {
                                Text(object.status?.text ?? "—")
                                Text("·")
                                Text(object.vrf?.text ?? L10n.text("Global VRF"))
                            }.font(.caption).foregroundStyle(.secondary)
                            if let text = object.description, !text.isEmpty { Text(text).font(.subheadline).lineLimit(2) }
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("ipamObject-\(object.id)")
                }
                if model.hasLoaded, model.objects.isEmpty, !model.isLoading {
                    ContentUnavailableView.search(text: query.search)
                }
                if model.next != nil {
                    if model.isLoadingMore { ProgressView("Loading more…") }
                    else {
                        Button("Load more") { pageRequest += 1 }
                            .disabled(model.isLoading).accessibilityIdentifier("ipamLoadMore")
                    }
                }
            } header: {
                if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)) }
            }
        }
        .navigationTitle(service.kind.title)
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search NetBox")
        .sheet(isPresented: $creating, onDismiss: { refreshID = UUID() }) {
            IPAMCreateView(client: service.client, kind: service.kind, vrf: query.vrf, tenant: query.tenant)
        }
        .toolbar {
            if allowsCreation && service.context == nil {
                Button("Create", systemImage: "plus") { creating = true }
                    .accessibilityIdentifier("createIPAM")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .disabled(model.isLoading).accessibilityIdentifier("refreshIPAM")
        }
        .task(id: Request(query: query, refresh: refreshID)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: query)
            } catch { /* Search debounce cancellation is expected. */ }
        }
        .task(id: pageRequest) { if pageRequest > 0 { await model.loadMore() } }
        .onAppear {
            if needsDeletionRefresh { needsDeletionRefresh = false; refreshID = UUID() }
        }
        .refreshable { await model.reload(query: query) }
    }
}
