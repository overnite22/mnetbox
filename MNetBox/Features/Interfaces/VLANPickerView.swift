import SwiftUI

struct VLANPickerQuery: Equatable, Sendable {
    var siteID: Int?
    var search = ""
    var items: [URLQueryItem] {
        [.init(name: "site_id", value: siteID.map(String.init) ?? "null"), .init(name: "ordering", value: "id"), .init(name: "limit", value: "50")]
        + (search.isEmpty ? [] : [.init(name: "q", value: search)])
    }
}
struct VLANPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let siteID: Int?
    let allowsEmpty: Bool
    @Binding var selection: ReferenceSelection?
    @State private var global = false
    @State private var search = ""
    @State private var retryID = UUID()
    @State private var pageRequest = 0
    @State private var model: PaginatedListModel<VLANReference, VLANPickerQuery>
    init(client: APIClient, siteID: Int?, selection: Binding<ReferenceSelection?>, allowsEmpty: Bool) {
        self.siteID = siteID; _selection = selection; self.allowsEmpty = allowsEmpty
        _model = State(initialValue: PaginatedListModel(query: VLANPickerQuery(siteID: siteID), fetch: { query, next in
            let required = query.items.filter { $0.name != "limit" }
            try CollectionLinks.validate(next, path: "ipam/vlans/", required: required)
            let page: NetBoxPage<VLANReference> = try await client.get(next ?? "ipam/vlans/", query: next == nil ? query.items : [])
            guard page.count >= page.results.count, page.results.count <= 50,
                  Set(page.results.map(\.id)).count == page.results.count,
                  page.results.allSatisfy({ $0.site?.id == query.siteID }) else { throw APIError.invalidResponse }
            return page
        }))
    }
    private var query: VLANPickerQuery { VLANPickerQuery(siteID: global ? nil : siteID, search: search.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var body: some View {
        List {
            if let siteID {
                Picker("Scope", selection: $global) {
                    Text(L10n.identifier("Parent site #%ld", siteID)).tag(false)
                    Text("Global").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("vlanScope")
            } else { Text("Global VLANs only: this parent has no site.").font(.caption) }
            if allowsEmpty { Button("None") { selection = nil; dismiss() }.accessibilityIdentifier("vlanNone") }
            if model.isLoading { ProgressView() }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                Button("Retry") { if model.failedLoadingMore { pageRequest += 1 } else { retryID = UUID() } }
            }
            ForEach(model.objects) { vlan in
                Button(vlan.title) { selection = ReferenceSelection(id: vlan.id, title: vlan.title); dismiss() }
                    .accessibilityIdentifier("vlan-\(vlan.id)")
            }
            if model.hasLoaded && model.objects.isEmpty { Text("No results").foregroundStyle(.secondary) }
            if model.next != nil {
                if model.isLoadingMore { ProgressView() } else { Button("Load more") { pageRequest += 1 }.disabled(model.isLoading) }
            }
        }.navigationTitle("VLAN").searchable(text: $search)
            .task(id: Request(query: query, retry: retryID)) {
                do {
                    if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                    try Task.checkCancellation()
                    await model.reload(query: query)
                } catch { /* Replaced search requests are cancelled. */ }
            }
            .task(id: pageRequest) { if pageRequest > 0 { await model.loadMore() } }
            .refreshable { await model.reload(query: query) }
    }
    private struct Request: Equatable { let query: VLANPickerQuery; let retry: UUID }
}
