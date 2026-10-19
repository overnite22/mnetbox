import Foundation
import Observation

enum RackFace: String, CaseIterable, Sendable { case front, rear }

struct RackUnit: Codable, Sendable, Identifiable {
    let position: NetBoxQuantity
    let name: String
    let occupied: Bool
    let device: NetBoxLabel?
    var number: Decimal? { Decimal(string: position.text, locale: Locale(identifier: "en_US_POSIX")) }
    var id: String { number.map { NSDecimalNumber(decimal: $0).stringValue } ?? position.text }
    enum CodingKeys: String, CodingKey { case position = "id", name, occupied, device }
}

struct RackElevationService: Sendable {
    let client: APIClient
    let rackID: Int

    func units(face: RackFace) async throws -> [RackUnit] {
        guard rackID > 0 else { throw APIError.invalidURL }
        let path = "dcim/racks/\(rackID)/elevation/"
        let query = [URLQueryItem(name: "face", value: face.rawValue), URLQueryItem(name: "render", value: "json"),
                     URLQueryItem(name: "expand_devices", value: "true"), URLQueryItem(name: "limit", value: "100")]
        var reference: String? = path
        var visited: Set<String> = []
        var units: [RackUnit] = []
        var expectedCount: Int?
        while let current = reference {
            try Task.checkCancellation()
            guard visited.insert(current).inserted, visited.count <= 100 else { throw APIError.invalidResponse }
            if current != path {
                guard let parts = URLComponents(string: current), parts.path.hasSuffix("/api/" + path),
                      parts.queryItems?.filter({ $0.name == "face" }).map(\.value) == [face.rawValue],
                      parts.queryItems?.filter({ $0.name == "expand_devices" }).map(\.value) == ["true"] else { throw APIError.invalidURL }
            }
            let page: NetBoxPage<RackUnit> = try await client.get(current, query: current == path ? query : [])
            guard page.count >= 0, page.count <= 4096, expectedCount == nil || expectedCount == page.count else { throw APIError.invalidResponse }
            expectedCount = page.count
            units += page.results
            guard units.count <= page.count else { throw APIError.invalidResponse }
            reference = page.next
        }
        guard units.count == expectedCount, Set(units.map(\.id)).count == units.count,
              units.allSatisfy({ unit in
                  guard let number = unit.number else { return false }
                  return number >= 0 && number <= 100000 && number * 2 == Decimal(NSDecimalNumber(decimal: number * 2).intValue)
                      && (unit.device == nil || (unit.occupied && (unit.device?.id ?? 0) > 0))
              }) else { throw APIError.invalidResponse }
        return units
    }
}

@MainActor @Observable final class RackElevationModel {
    private(set) var units: [RackUnit] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?
    private var generation = UUID()
    private let service: RackElevationService
    init(service: RackElevationService) { self.service = service }
    func reload(face: RackFace) async {
        guard !Task.isCancelled else { return }
        generation = UUID()
        let current = generation
        // Never display a previous face or a partial elevation as the current face.
        units = []; hasLoaded = false; errorMessage = nil; isLoading = true
        defer { if generation == current { isLoading = false } }
        do {
            let units = try await service.units(face: face)
            try Task.checkCancellation()
            guard generation == current else { return }
            self.units = units; hasLoaded = true
        } catch {
            guard generation == current, !Task.isCancelled, !(error is CancellationError) else { return }
            errorMessage = readErrorMessage(error)
        }
    }
}
