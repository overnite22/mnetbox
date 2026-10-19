import Foundation
import Observation

typealias InventoryListModel = PaginatedListModel<InventoryObject, InventoryQuery>

extension PaginatedListModel where Item == InventoryObject, Query == InventoryQuery {
    convenience init(service: InventoryService) {
        self.init(query: InventoryQuery(), fetch: { try await service.page(query: $0, next: $1) })
    }
}

@MainActor @Observable final class InventoryDetailModel {
    private(set) var object: InventoryObject?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let service: InventoryService
    private let id: Int
    private var generation = UUID()
    init(service: InventoryService, id: Int) { self.service = service; self.id = id }
    func reload() async {
        guard !Task.isCancelled else { return }
        generation = UUID()
        let current = generation
        isLoading = true
        errorMessage = nil
        defer { if generation == current { isLoading = false } }
        do {
            let object = try await service.detail(id: id)
            try Task.checkCancellation()
            guard generation == current else { return }
            self.object = object
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
        }
    }
}
