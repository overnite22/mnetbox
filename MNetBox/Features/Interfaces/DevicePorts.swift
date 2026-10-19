import SwiftUI

enum DevicePortKind: String, CaseIterable, Sendable {
    case front = "front-ports", rear = "rear-ports", console = "console-ports", consoleServer = "console-server-ports", power = "power-ports", outlet = "power-outlets"
    var path: String { "dcim/\(rawValue)/" }
    var title: String { L10n.text([.front: "Front ports", .rear: "Rear ports", .console: "Console ports", .consoleServer: "Console server ports", .power: "Power ports", .outlet: "Power outlets"][self] ?? "Ports") }
    var symbol: String { self == .power || self == .outlet ? "bolt.fill" : self == .console || self == .consoleServer ? "terminal.fill" : "cable.connector" }
    var traceable: Bool { self != .front && self != .rear }
    var passive: PassivePortKind? { self == .front ? .front : self == .rear ? .rear : nil }
}
struct DevicePortRecord: Codable, Identifiable, Sendable {
    let id: Int; let name: String; let device: NetBoxLabel
    let type: NetBoxLabel?; let description: String; let cable: NetBoxLabel?
    let label: String?; let speed: NetBoxLabel?; let maximumDraw: NetBoxQuantity?; let allocatedDraw: NetBoxQuantity?
    let powerPort: NetBoxLabel?; let feedLeg: NetBoxLabel?; let status: NetBoxLabel?
    enum CodingKeys: String, CodingKey {
        case id, name, device, type, description, cable, label, speed, status
        case maximumDraw = "maximum_draw", allocatedDraw = "allocated_draw", powerPort = "power_port", feedLeg = "feed_leg"
    }
    func validate(deviceID: Int, id: Int? = nil) throws {
        guard self.id > 0, id == nil || self.id == id, deviceID > 0, device.id == deviceID, !name.isEmpty,
              (cable?.id ?? 1) > 0, (powerPort?.id ?? 1) > 0 else { throw APIError.invalidResponse }
    }
}
struct DevicePortQuery: Equatable, Sendable {
    var search = ""
    var items: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: "50"), .init(name: "ordering", value: "name,id")]
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { items.append(.init(name: "q", value: q)) }; return items
    }
}
struct DevicePortService: Sendable {
    let client: APIClient; let kind: DevicePortKind; let deviceID: Int
    func page(query: DevicePortQuery, next: String?) async throws -> NetBoxPage<DevicePortRecord> {
        guard deviceID > 0 else { throw APIError.invalidReference }
        let items = query.items + [.init(name: "device_id", value: String(deviceID))]
        try CollectionLinks.validate(next, path: kind.path, required: items)
        let page: NetBoxPage<DevicePortRecord> = try await client.get(next ?? kind.path, query: next == nil ? items : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count,
              page.next == nil || !page.results.isEmpty else { throw APIError.invalidResponse }
        try CollectionLinks.validate(page.next, path: kind.path, required: items)
        for port in page.results { try port.validate(deviceID: deviceID) }; return page
    }
    func detail(id: Int) async throws -> DevicePortRecord {
        guard id > 0, deviceID > 0 else { throw APIError.invalidReference }
        let row: DevicePortRecord = try await client.get(kind.path + "\(id)/")
        try row.validate(deviceID: deviceID, id: id); return row
    }
}
struct DevicePortDetailView: View {
    let service: DevicePortService
    @State private var model: ReadDetailModel<DevicePortRecord>; @State private var refresh = UUID()
    init(service: DevicePortService, id: Int) { self.service = service; _model = State(initialValue: ReadDetailModel(fetch: { try await service.detail(id: id) })) }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage { StatusMessage(message: error); Button("Retry") { refresh = UUID() } }
            if let row = model.object {
                Section { Label(row.name, systemImage: service.kind.symbol).font(.title2.bold()).foregroundStyle(.orange).accessibilityIdentifier("devicePortTitle") }
                Section("Explore") {
                    NavigationLink { InventoryDetailView(service: InventoryService(client: service.client, kind: .devices), id: service.deviceID) } label: { Label(row.device.text, systemImage: "server.rack") }
                    if let cableID = row.cable?.id { NavigationLink { CableDetailView(client: service.client, id: cableID) } label: { Label("Cable", systemImage: "cable.connector") } }
                    if service.kind.traceable {
                        NavigationLink { CableTraceView(client: service.client, interfaceID: row.id, title: row.name, portKind: service.kind) } label: { Label("Cable trace", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.accessibilityIdentifier("devicePortTrace")
                    }
                    if let powerID = row.powerPort?.id, service.kind == .outlet {
                        NavigationLink { DevicePortDetailView(service: .init(client: service.client, kind: .power, deviceID: service.deviceID), id: powerID) } label: { Label(row.powerPort?.text ?? "—", systemImage: "bolt.fill") }
                    }
                }
                Section("Overview") {
                    DetailField(title: "Type", value: row.type?.text ?? "—")
                    DetailField(title: "Label", value: row.label ?? "—")
                    DetailField(title: "Description", value: row.description)
                    if let speed = row.speed { DetailField(title: "Speed", value: speed.text) }
                    if let status = row.status { DetailField(title: "Status", value: status.text) }
                    if let watts = row.maximumDraw { DetailField(title: "Maximum draw (W)", value: watts.text) }
                    if let watts = row.allocatedDraw { DetailField(title: "Allocated draw (W)", value: watts.text) }
                    if let leg = row.feedLeg { DetailField(title: "Feed leg", value: leg.text) }
                }
            }
        }.navigationTitle(service.kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) { await model.reload() }.refreshable { await model.reload() }
    }
}
