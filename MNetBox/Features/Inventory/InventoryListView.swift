import SwiftUI

struct InventoryListView: View {
    let service: InventoryService
    @State private var model: InventoryListModel
    @State private var query = InventoryQuery()
    @State private var refreshID = UUID()
    @State private var pageRequest = 0
    @State private var creating = false
    private struct Request: Equatable { let query: InventoryQuery; let refresh: UUID }

    init(service: InventoryService) {
        self.service = service
        _model = State(initialValue: InventoryListModel(service: service))
    }

    var body: some View {
        List {
            if let scope = service.scope {
                Section { Label(scope.title, systemImage: scope.parent == .site ? InventoryKind.sites.symbol : InventoryKind.racks.symbol) }
            }
            Section("Filters") {
                Picker("Status", selection: $query.status) {
                    Text("All").tag("")
                    ForEach(service.kind.statuses, id: \.self) { Text(L10n.text($0.capitalized)).tag($0) }
                }.accessibilityIdentifier("inventoryStatus")
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
                        InventoryDetailView(service: service, id: object.id)
                    } label: {
                        HStack(spacing: 12) {
                            InventoryIllustration(kind: service.kind).frame(width: 44, height: 54)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(object.title).font(.headline)
                                HStack {
                                    Text(object.status?.text ?? "—")
                                    if !object.subtitle.isEmpty { Text("·"); Text(object.subtitle) }
                                }.font(.caption).foregroundStyle(.secondary)
                                if let text = object.description, !text.isEmpty { Text(text).font(.subheadline).lineLimit(2) }
                            }
                        }.padding(.vertical, 3)
                    }.accessibilityIdentifier("inventoryObject-\(object.id)")
                }
                if model.hasLoaded, model.objects.isEmpty, !model.isLoading {
                    ContentUnavailableView.search(text: query.search)
                }
                if model.next != nil {
                    if model.isLoadingMore { ProgressView("Loading more…") }
                    else {
                        Button("Load more") { pageRequest += 1 }
                            .disabled(model.isLoading).accessibilityIdentifier("inventoryLoadMore")
                    }
                }
            } header: {
                if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)) }
            }
        }
        .navigationTitle(service.kind.title)
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search NetBox")
        .toolbar {
            if service.kind == .devices {
                Button("New device", systemImage: "plus") { creating = true }.accessibilityIdentifier("createDevice")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .disabled(model.isLoading).accessibilityIdentifier("refreshInventory")
        }
        .sheet(isPresented: $creating, onDismiss: { refreshID = UUID() }) {
            DeviceCreateView(client: service.client, site: service.scope.flatMap { $0.parent == .site ? ReferenceSelection(id: $0.id, title: $0.title) : nil })
        }
        .task(id: Request(query: query, refresh: refreshID)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: query)
            } catch { /* Search debounce cancellation is expected. */ }
        }
        .task(id: pageRequest) { if pageRequest > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: query) }
    }
}
