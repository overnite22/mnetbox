import Foundation
import Observation

// Collection confinement is checked here; HTTPS origin/API confinement stays in APIClient.
enum CollectionLinks {
    static func validate(_ next: String?, path: String, required: [URLQueryItem] = []) throws {
        guard let next else { return }
        guard let parts = URLComponents(string: next), parts.path == path || parts.path.hasSuffix("/api/" + path) else { throw APIError.invalidURL }
        let items = parts.queryItems ?? []
        for item in required {
            guard items.filter({ $0.name == item.name }).map(\.value) == [item.value] else { throw APIError.invalidURL }
        }
    }
}

@MainActor @Observable final class ReadDetailModel<Item: Sendable> {
    private(set) var object: Item?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private let fetch: @Sendable () async throws -> Item
    init(fetch: @escaping @Sendable () async throws -> Item) { self.fetch = fetch }
    func reload() async {
        guard !Task.isCancelled else { return }
        generation = UUID()
        let current = generation
        isLoading = true; errorMessage = nil
        defer { if generation == current { isLoading = false } }
        do {
            let object = try await fetch()
            try Task.checkCancellation()
            guard generation == current else { return }
            self.object = object
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
        }
    }
}
