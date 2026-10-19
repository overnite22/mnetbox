import SwiftUI

struct InterfaceListView: View {
    let service: InterfaceService
    let title: String
    let allowsCreation: Bool
    @State private var creating = false
    @State private var model: PaginatedListModel<InterfaceObject, InterfaceQuery>
    @State private var query = InterfaceQuery()
    @State private var needsDeletionRefresh = false
    @State private var refreshID = UUID()
    @State private var pageRequest = 0
    private struct Request: Equatable { let query: InterfaceQuery; let refresh: UUID }
    init(service: InterfaceService, title: String, allowsCreation: Bool = true) {
        self.service = service; self.title = title; self.allowsCreation = allowsCreation
        _model = State(initialValue: PaginatedListModel(query: InterfaceQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        List {
            Section { Label(title, systemImage: service.kind.parentKind.symbol) }
            Section("Filters") {
                Picker("Enabled", selection: $query.enabled) {
                    Text("All").tag(""); Text("Yes").tag("true"); Text("No").tag("false")
                }
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") {
                    if model.failedLoadingMore { pageRequest += 1 } else { refreshID = UUID() }
                }
            }
            Section {
                ForEach(model.objects) { object in
                    NavigationLink {
                        InterfaceDetailView(service: service, id: object.id, onDeleted: { needsDeletionRefresh = true })
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            if service.vlanID != nil { Text(service.parent(object)?.text ?? "—").font(.caption).foregroundStyle(.secondary) }
                            Label(object.name, systemImage: "network").font(.headline)
                            Text("\(object.type?.text ?? (service.kind == .virtual ? L10n.text("Virtual") : "—")) · \(L10n.text(object.enabled == true ? "Enabled" : object.enabled == false ? "Disabled" : "Unknown"))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let description = object.description, !description.isEmpty { Text(description).font(.subheadline) }
                        }
                    }.accessibilityIdentifier("interface-\(object.id)")
                }
                if model.hasLoaded, model.objects.isEmpty, !model.isLoading { ContentUnavailableView.search(text: query.search) }
                if model.next != nil {
                    if model.isLoadingMore { ProgressView() }
                    else { Button("Load more") { pageRequest += 1 }.disabled(model.isLoading).accessibilityIdentifier("interfaceLoadMore") }
                }
            } header: { if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)) } }
        }
        .navigationTitle("Interfaces")
        .searchable(text: $query.search, prompt: "Search interfaces")
        .sheet(isPresented: $creating, onDismiss: { refreshID = UUID() }) {
            if let parent = service.parentID, parent > 0 { InterfaceCreateView(client: service.client, kind: service.kind, parentID: parent) }
        }
        .toolbar {
            if allowsCreation, let parent = service.parentID, parent > 0 {
                Button("New interface", systemImage: "plus") { creating = true }.accessibilityIdentifier("newInterface")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }.disabled(model.isLoading) }
        .task(id: Request(query: query, refresh: refreshID)) {
            do {
                if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: query)
            } catch { /* Debounce cancellation is expected. */ }
        }
        .task(id: pageRequest) { if pageRequest > 0 { await model.loadMore() } }
        .onAppear {
            if needsDeletionRefresh { needsDeletionRefresh = false; refreshID = UUID() }
        }
        .refreshable { await model.reload(query: query) }
    }
}
