import SwiftUI

struct ReferenceSelection: Equatable, Sendable { let id: Int; let title: String }
struct ReferenceObject: Codable, Sendable, Identifiable {
    let id: Int
    let name: String?
    let display: String?
    let address: String?
    let vmRole: Bool?
    enum CodingKeys: String, CodingKey { case id, name, display, address; case vmRole = "vm_role" }
    var title: String { display ?? name ?? address ?? "#\(id)" }
}

struct ReferencePickerView: View {
    let title: String
    let zeroTitle: String?
    let allowsGlobal: Bool
    let emptyTitle: String
    let allowsEmpty: Bool
    @Binding var selection: ReferenceSelection?
    @Environment(\.dismiss) private var dismiss
    @State private var model: PaginatedListModel<ReferenceObject, String>
    @State private var search = ""
    @State private var pageRequest = 0
    init(client: APIClient, path: String, title: String, selection: Binding<ReferenceSelection?>, allowsGlobal: Bool = false, emptyTitle: String = "All", allowsEmpty: Bool = true, required: [URLQueryItem] = [], zeroTitle: String? = nil) {
        self.zeroTitle = zeroTitle
        self.title = title; self.allowsGlobal = allowsGlobal; self.emptyTitle = emptyTitle; _selection = selection
        self.allowsEmpty = allowsEmpty
        _model = State(initialValue: PaginatedListModel(query: "", fetch: { search, next in
            try CollectionLinks.validate(next, path: path, required: required + (search.isEmpty ? [] : [URLQueryItem(name: "q", value: search)]))
            var items = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "ordering", value: "id")] + required
            if !search.isEmpty { items.append(URLQueryItem(name: "q", value: search)) }
            if path == "dcim/mac-addresses/" {
                try CollectionLinks.validate(next, path: path, required: required + [.init(name: "ordering", value: "id")] + (search.isEmpty ? [] : [.init(name: "q", value: search)]))
                let page: NetBoxPage<MACRecord> = try await client.get(next ?? path, query: next == nil ? items : [])
                guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count else { throw APIError.invalidResponse }
                for (key, kind) in [("interface_id", InterfaceKind.physical), ("vminterface_id", .virtual)] {
                    if let selected = required.first(where: { $0.name == key })?.value.flatMap(Int.init) {
                        guard selected > 0, page.results.allSatisfy({ $0.assignment?.0 == kind && $0.assignment?.1 == selected }) else { throw APIError.invalidResponse }
                    }
                }
                return NetBoxPage(count: page.count, next: page.next, previous: page.previous, results: page.results.map {
                    ReferenceObject(id: $0.id, name: nil, display: $0.macAddress, address: nil, vmRole: nil)
                })
            }
            let page: NetBoxPage<ReferenceObject> = try await client.get(next ?? path, query: next == nil ? items : [])
            guard page.count >= 0, page.results.allSatisfy({ $0.id > 0 }) else { throw APIError.invalidResponse }
            if required.contains(URLQueryItem(name: "vm_role", value: "true")), !page.results.allSatisfy({ $0.vmRole == true }) { throw APIError.invalidResponse }
            return page
        }))
    }
    var body: some View {
        List {
            if allowsEmpty { Button(L10n.text(emptyTitle)) { selection = nil; dismiss() } }
            if allowsGlobal { Button("Global VRF") { selection = ReferenceSelection(id: 0, title: L10n.text("Global")); dismiss() } }
            if let zeroTitle { Button(L10n.text(zeroTitle)) { selection = ReferenceSelection(id: 0, title: L10n.text(zeroTitle)); dismiss() } }
            if model.isLoading { ProgressView() }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                Button("Retry") { if model.failedLoadingMore { pageRequest += 1 } else { retryID = UUID() } }
            }
            ForEach(model.objects) { value in
                Button(value.title) { selection = ReferenceSelection(id: value.id, title: value.title); dismiss() }
                    .accessibilityIdentifier("reference-\(value.id)")
            }
            if model.next != nil {
                if model.isLoadingMore { ProgressView() }
                else { Button("Load more") { pageRequest += 1 }.disabled(model.isLoading) }
            }
        }
        .navigationTitle(L10n.text(title)).searchable(text: $search)
        .task(id: Request(search: search, retry: retryID)) {
            do {
                if !search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await model.reload(query: search)
            } catch { /* Debounce cancellation is expected. */ }
        }
        .task(id: pageRequest) { if pageRequest > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: search) }
    }
    @State private var retryID = UUID()
    private struct Request: Equatable { let search: String; let retry: UUID }
}
