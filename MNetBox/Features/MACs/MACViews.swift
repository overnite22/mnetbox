import SwiftUI

struct MACListView: View {
    let service: MACService
    let allowsCreation: Bool
    @State private var model: PaginatedListModel<MACRecord, String>
    @State private var search = ""
    @State private var refresh = UUID()
    @State private var page = 0
    @State private var creating = false
    private struct Request: Equatable { let search: String; let refresh: UUID }
    init(service: MACService, allowsCreation: Bool = true) {
        self.service = service; self.allowsCreation = allowsCreation
        _model = State(initialValue: PaginatedListModel(query: "", fetch: { try await service.page(search: $0, next: $1) }))
    }
    var body: some View {
        List {
            if let interface = service.interface { Section { Text(interface.title) } }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if !model.objects.isEmpty { Text("Previously loaded results").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { if model.failedLoadingMore { page += 1 } else { refresh = UUID() } }
            }
            ForEach(model.objects) { mac in
                NavigationLink { MACDetailView(client: service.client, id: mac.id, onDeleted: { refresh = UUID() }) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(mac.macAddress, systemImage: mac.isPrimary ? "star.circle" : "network").monospaced()
                        Text(mac.assignedObject?.text ?? (mac.assignedObjectID.map { "#\($0)" } ?? L10n.text("None"))).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("macObject-\(mac.id)")
            }
            if model.hasLoaded, model.objects.isEmpty, !model.isLoading { ContentUnavailableView.search(text: search) }
            if model.next != nil {
                if model.isLoadingMore { ProgressView("Loading more…") }
                else { Button("Load more") { page += 1 }.disabled(model.isLoading).accessibilityIdentifier("macLoadMore") }
            }
        }
        .navigationTitle("MAC addresses")
        .searchable(text: $search, prompt: "Search NetBox")
        .toolbar {
            if allowsCreation, let interface = service.interface, (interface.parentID ?? 0) > 0 {
                Button("New MAC address", systemImage: "plus") { creating = true }.accessibilityIdentifier("createMAC")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading)
        }
        .sheet(isPresented: $creating, onDismiss: { refresh = UUID() }) { NetworkCreateView(client: service.client, interface: service.interface) }
        .task(id: Request(search: search, refresh: refresh)) {
            do {
                if !search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation(); await model.reload(query: search)
            } catch { /* New searches cancel the debounce. */ }
        }
        .task(id: page) { if page > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: search) }
    }
}

struct MACDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var deleted = false
    let onDeleted: () -> Void
    let client: APIClient
    @State private var model: ReadDetailModel<MACRecord>
    @State private var refresh = UUID()
    @State private var field: EditableTextField?
    @State private var assigning = false
    init(client: APIClient, id: Int, onDeleted: @escaping () -> Void = {}) {
        self.onDeleted = onDeleted
        self.client = client
        _model = State(initialValue: ReadDetailModel(fetch: { try await MACService(client: client).detail(id: id) }))
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { refresh = UUID() }
            }
            if let mac = model.object {
                Section("Overview") {
                    Text(mac.macAddress).monospaced().font(.title3.bold()).accessibilityIdentifier("macDetailTitle")
                    DetailField(title: "ID", value: "#\(mac.id)")
                    DetailField(title: "Primary MAC", value: L10n.text(mac.isPrimary ? "Yes" : "No"))
                    DetailField(title: "Assignment", value: mac.assignedObject?.text ?? (mac.assignedObjectID.map { "#\($0)" } ?? L10n.text("None")), action: mac.assignment != nil || mac.assignedObjectType == nil ? { assigning = true } : nil, identifier: "macAssignment")
                    if let type = mac.assignedObjectType { DetailField(title: "Parent type", value: type) }
                }
                if let (kind, id) = mac.assignment {
                    Section("Explore") { NavigationLink { InterfaceDetailView(service: InterfaceService(client: client, kind: kind), id: id) } label: { Label("Interface", systemImage: "network") }.accessibilityIdentifier("macInterface") }
                }
                Section("Description") { DetailField(title: "Description", value: mac.description.isEmpty ? "—" : mac.description, action: { field = .description }, identifier: "macDescription") }
                Section("Comments") { DetailField(title: "Comments", value: mac.comments.isEmpty ? "—" : mac.comments, action: { field = .comments }, identifier: "macComments") }
            }
        }
        .disabled(model.isLoading)
        .navigationTitle("MAC address")
        .sheet(item: $field, onDismiss: { refresh = UUID() }) { field in
            if let mac = model.object { TextEditView(client: client, target: TextEditTarget(collection: .macAddresses, id: mac.id), field: field) }
        }
        .sheet(isPresented: $assigning, onDismiss: { refresh = UUID() }) {
            if let mac = model.object { StructuredEditView(client: client, target: StructuredEditTarget(collection: .macAddresses, id: mac.id), field: .assignment) }
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss(); onDeleted() } else { refresh = UUID() } }) {
            if let mac = model.object { DeletionView(client: client, target: .init(collection: .macAddresses, id: mac.id)) { deleted = true } }
        }
        .toolbar {
            if model.object != nil, !model.isLoading, model.errorMessage == nil {
                Button("Delete object", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteMAC")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) { await model.reload() }
        .refreshable { await model.reload() }
    }
}
