import Foundation
import Observation

enum DashboardMetric: String, CaseIterable, Identifiable, Sendable {
    case sites, racks, devices, virtualMachines, prefixes, ipAddresses

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sites: L10n.text("Sites")
        case .racks: L10n.text("Racks")
        case .devices: L10n.text("Devices")
        case .virtualMachines: L10n.text("Virtual machines")
        case .prefixes: L10n.text("Prefixes")
        case .ipAddresses: L10n.text("IP addresses")
        }
    }
    var symbol: String {
        switch self {
        case .sites: "building.2"
        case .racks: "cabinet"
        case .devices: "server.rack"
        case .virtualMachines: "square.stack.3d.up"
        case .prefixes: "network"
        case .ipAddresses: "number"
        }
    }
    var path: String {
        switch self {
        case .sites: "dcim/sites/"
        case .racks: "dcim/racks/"
        case .devices: "dcim/devices/"
        case .virtualMachines: "virtualization/virtual-machines/"
        case .prefixes: "ipam/prefixes/"
        case .ipAddresses: "ipam/ip-addresses/"
        }
    }
}

struct DashboardCount: Decodable, Sendable {
    let count: Int
}

@MainActor @Observable final class DashboardModel {
    enum Value: Equatable, Sendable {
        case count(Int)
        case failed(String)
    }

    private(set) var values: [DashboardMetric: Value] = [:]
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private let fetchCount: @Sendable (DashboardMetric) async throws -> Int

    init(client: APIClient) {
        fetchCount = { metric in
            let page: DashboardCount = try await client.get(metric.path, query: [
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "brief", value: "true")
            ])
            guard page.count >= 0 else { throw APIError.invalidResponse }
            return page.count
        }
    }

    init(fetchCount: @escaping @Sendable (DashboardMetric) async throws -> Int) {
        self.fetchCount = fetchCount
    }

    func refresh() async {
        guard !isLoading, !Task.isCancelled else { return }
        isLoading = true
        defer { isLoading = false }
        let fetch = fetchCount
        let updated = await withTaskGroup(of: (DashboardMetric, Value?).self) { group in
            for metric in DashboardMetric.allCases {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let count = try await fetch(metric)
                        try Task.checkCancellation()
                        return (metric, .count(count))
                    } catch {
                        if Task.isCancelled || error is CancellationError { return (metric, nil) }
                        // Only display our known error messages; never echo arbitrary response data.
                        let message = (error as? APIError)?.localizedDescription ?? APIError.transport.localizedDescription
                        return (metric, .failed(message))
                    }
                }
            }
            var result: [DashboardMetric: Value] = [:]
            for await (metric, value) in group { result[metric] = value }
            return result
        }
        // A cancelled refresh must not replace the previous snapshot with partial data.
        guard !Task.isCancelled else { return }
        values = updated
        lastUpdated = Date()
    }
}
