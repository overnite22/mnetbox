import SwiftUI

extension CableObject {
    var title: String { label?.isEmpty == false ? label ?? "" : display ?? L10n.identifier("Cable #%ld", id) }
    func validate() throws {
        guard id > 0, let aTerminations, let bTerminations else { throw APIError.invalidResponse }
        for side in [aTerminations, bTerminations] {
            guard side.count <= 256, Set(side.map { "\($0.objectType)-\($0.objectID)" }).count == side.count,
                  side.allSatisfy({ !$0.objectType.isEmpty && $0.objectID > 0 && ($0.object == nil || $0.object?.id == $0.objectID) }) else { throw APIError.invalidResponse }
        }
        guard [tenant, bundle].compactMap({ $0 }).allSatisfy({ ($0.id ?? 0) > 0 }) else { throw APIError.invalidResponse }
    }
}
struct CableQuery: Equatable, Sendable {
    var search = ""
    var status = ""
    var unterminated = false
    var items: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50"), .init(name: "ordering", value: "id")]
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { items.append(.init(name: "q", value: text)) }
        if !status.isEmpty { items.append(.init(name: "status", value: status)) }
        if unterminated { items.append(.init(name: "unterminated", value: "true")) }
        return items
    }
}
struct CableService: Sendable {
    let client: APIClient
    var deviceID: Int? = nil
    func page(query: CableQuery, next: String?) async throws -> NetBoxPage<CableObject> {
        guard (deviceID ?? 1) > 0, query.status.isEmpty || ["connected", "planned", "decommissioning"].contains(query.status) else { throw APIError.invalidURL }
        var items = query.items
        if let deviceID { items.append(.init(name: "device_id", value: String(deviceID))) }
        try CollectionLinks.validate(next, path: "dcim/cables/", required: items.filter { $0.name != "limit" })
        let page: NetBoxPage<CableObject> = try await client.get(next ?? "dcim/cables/", query: next == nil ? items : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count else { throw APIError.invalidResponse }
        for row in page.results {
            try row.validate()
            // The common label reader retains labels. Validate status through its
            // localized-independent choice value in CableObject's typed decoder.
            guard query.status.isEmpty || row.statusValue == query.status,
                  !query.unterminated || row.aTerminations?.isEmpty == true || row.bTerminations?.isEmpty == true else { throw APIError.invalidResponse }
            if let deviceID {
                guard ((row.aTerminations ?? []) + (row.bTerminations ?? [])).contains(where: { $0.object?.device?.id == deviceID }) else { throw APIError.invalidResponse }
            }
        }
        return page
    }
}

struct CableListView: View {
    let service: CableService
    @State private var query = CableQuery()
    @State private var model: PaginatedListModel<CableObject, CableQuery>
    @State private var refresh = UUID()
    @State private var page = 0
    private struct Request: Equatable { let query: CableQuery; let refresh: UUID }
    init(service: CableService, search: String = "") {
        self.service = service
        _query = State(initialValue: CableQuery(search: search))
        _model = State(initialValue: PaginatedListModel(query: CableQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    var body: some View {
        List {
            Section("Filters") {
                Picker("Status", selection: $query.status) { Text("All").tag(""); ForEach(["connected", "planned", "decommissioning"], id: \.self) { Text(L10n.text($0.capitalized)).tag($0) } }
                Toggle("Unterminated cables only", isOn: $query.unterminated).accessibilityIdentifier("cableUnterminated")
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if !model.objects.isEmpty { Text("Previously loaded results").font(.caption) }
                Button("Retry") { if model.failedLoadingMore { page += 1 } else { refresh = UUID() } }
            }
            ForEach(model.objects) { cable in
                NavigationLink { CableDetailView(client: service.client, id: cable.id) { refresh = UUID() } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(cable.title, systemImage: "cable.connector").font(.headline)
                        Text([cable.status?.text, cable.type].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        Text("A: \(cable.aTerminations?.count ?? 0) ↔ B: \(cable.bTerminations?.count ?? 0)").font(.caption.monospacedDigit())
                    }
                }.accessibilityIdentifier("cableObject-\(cable.id)")
            }
            if model.hasLoaded, model.objects.isEmpty, !model.isLoading { ContentUnavailableView.search(text: query.search) }
            if model.next != nil { if model.isLoadingMore { ProgressView("Loading more…") } else { Button("Load more") { page += 1 }.accessibilityIdentifier("cableLoadMore") } }
        }.navigationTitle("Cables").searchable(text: $query.search, prompt: "Search NetBox")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: Request(query: query, refresh: refresh)) {
            do { if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await model.reload(query: query) } catch { /* Replaced queries cancel the debounce. */ }
        }.task(id: page) { if page > 0 { await model.loadMore() } }.refreshable { await model.reload(query: query) }
    }
}

struct CableDiagram: View {
    let client: APIClient
    let cable: CableObject
    @Environment(\.dynamicTypeSize) private var textSize
    private func endpoint(_ value: CableTermination) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(value.object?.title ?? "#\(value.objectID)", systemImage: value.objectType == "dcim.interface" ? "network" : "point.3.connected.trianglepath.dotted")
            if let device = value.object?.device { Text(device.text).font(.caption).foregroundStyle(.secondary) }
            Text(verbatim: "\(value.objectType) · #\(value.objectID)").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }
    private func side(_ title: String, values: [CableTermination]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title)).font(.headline)
            if values.isEmpty { Label("No visible terminations", systemImage: "questionmark.circle").font(.caption) }
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                if let kind = InterfaceKind(rawValue: value.objectType), value.object?.id == value.objectID {
                    NavigationLink { InterfaceDetailView(service: InterfaceService(client: client, kind: kind), id: value.objectID) } label: { endpoint(value) }.buttonStyle(.plain)
                        .accessibilityIdentifier("diagram-\(title)-\(value.objectID)")
                } else { endpoint(value) }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("A ↔ B").font(.caption.bold()).foregroundStyle(.secondary).accessibilityIdentifier("cableDiagram")
            if textSize.isAccessibilitySize {
                side("Side A", values: cable.aTerminations ?? [])
                Image(systemName: "arrow.down").foregroundStyle(.tint).accessibilityHidden(true)
                side("Side B", values: cable.bTerminations ?? [])
            } else {
                HStack(alignment: .top, spacing: 10) {
                    side("Side A", values: cable.aTerminations ?? [])
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.tint).padding(.top, 42).accessibilityHidden(true)
                    side("Side B", values: cable.bTerminations ?? [])
                }
            }
            Text("This shows this cable's visible terminations, not a traced end-to-end network path.").font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
    }
}
