import Foundation
import Observation

@MainActor @Observable final class PaginatedListModel<Item: Codable & Sendable & Identifiable, Query: Equatable & Sendable> {
    private(set) var objects: [Item] = []
    private(set) var total = 0
    private(set) var next: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private(set) var failedLoadingMore = false
    private var query: Query
    private var generation = UUID()
    private var visited: Set<String> = []
    private let fetch: @Sendable (Query, String?) async throws -> NetBoxPage<Item>

    init(query: Query, fetch: @escaping @Sendable (Query, String?) async throws -> NetBoxPage<Item>) {
        self.query = query
        self.fetch = fetch
    }

    func reload(query newQuery: Query) async {
        guard !Task.isCancelled else { return }
        generation = UUID()
        let current = generation
        if query != newQuery {
            objects = []; total = 0; next = nil; hasLoaded = false
        }
        query = newQuery
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        failedLoadingMore = false
        defer { if generation == current { isLoading = false } }
        do {
            let page = try await fetch(newQuery, nil)
            try Task.checkCancellation()
            guard generation == current else { return }
            objects = unique(page.results)
            total = page.count
            next = page.next
            visited = []
            hasLoaded = true
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
        }
    }

    func loadMore() async {
        guard !Task.isCancelled, !isLoading, !isLoadingMore, let reference = next else { return }
        let current = generation
        isLoadingMore = true
        errorMessage = nil
        defer { if generation == current { isLoadingMore = false } }
        do {
            guard !visited.contains(reference) else { throw APIError.invalidResponse }
            let page = try await fetch(query, reference)
            try Task.checkCancellation()
            guard generation == current else { return }
            visited.insert(reference)
            objects = unique(objects + page.results)
            total = page.count
            next = page.next
            if let link = next, visited.contains(link) {
                next = nil
                errorMessage = APIError.invalidResponse.localizedDescription
            }
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
            failedLoadingMore = true
        }
    }

    private func unique(_ values: [Item]) -> [Item] {
        var seen: Set<Item.ID> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

