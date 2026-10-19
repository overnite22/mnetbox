import Foundation
import Observation

typealias IPAMListModel = PaginatedListModel<IPAMObject, IPAMQuery>

extension PaginatedListModel where Item == IPAMObject, Query == IPAMQuery {
    convenience init(service: IPAMService) {
        self.init(query: IPAMQuery(), fetch: { try await service.page(query: $0, next: $1) })
    }
    convenience init(fetch: @escaping @Sendable (IPAMQuery, String?) async throws -> NetBoxPage<IPAMObject>) {
        self.init(query: IPAMQuery(), fetch: fetch)
    }
}

@MainActor @Observable final class IPAMDetailModel {
    private(set) var object: IPAMObject?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private let service: IPAMService
    private let id: Int
    init(service: IPAMService, id: Int) { self.service = service; self.id = id }

    func reload() async {
        generation = UUID()
        let current = generation
        isLoading = true
        errorMessage = nil
        defer { if generation == current { isLoading = false } }
        do {
            let value = try await service.detail(id: id)
            try Task.checkCancellation()
            guard generation == current else { return }
            object = value
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
        }
    }
}
