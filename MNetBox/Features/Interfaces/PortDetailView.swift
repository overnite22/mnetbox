import SwiftUI

enum PassivePortKind: String, Sendable { case front = "front-ports", rear = "rear-ports"; var title: String { L10n.text(self == .front ? "Front port" : "Rear port") } }
struct PassivePort: Decodable, Sendable {
    let id: Int; let name: String; let device: NetBoxLabel; let type: NetBoxLabel?; let positions: Int
    let description: String; let cable: NetBoxLabel?; let mappings: [Mapping]
    let mappingKind: PassivePortKind
    struct Mapping: Decodable, Sendable {
        let position: Int; let frontPort: Int?; let rearPort: Int?; let otherPosition: Int
        enum CodingKeys: String, CodingKey { case position, frontPort = "front_port", rearPort = "rear_port", frontPosition = "front_port_position", rearPosition = "rear_port_position" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            position = try c.decode(Int.self, forKey: .position); frontPort = try c.decodeIfPresent(Int.self, forKey: .frontPort); rearPort = try c.decodeIfPresent(Int.self, forKey: .rearPort)
            otherPosition = try c.decode(Int.self, forKey: frontPort != nil ? .frontPosition : .rearPosition)
        }
    }
    enum CodingKeys: String, CodingKey { case id, name, device, type, positions, description, cable, front = "front_ports", rear = "rear_ports" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name); device = try c.decode(NetBoxLabel.self, forKey: .device); type = try c.decodeIfPresent(NetBoxLabel.self, forKey: .type)
        positions = try c.decode(Int.self, forKey: .positions); description = try c.decode(String.self, forKey: .description)
        guard c.contains(.cable), c.contains(.front) != c.contains(.rear) else { throw APIError.invalidResponse }
        mappingKind = c.contains(.front) ? .rear : .front
        cable = try c.decodeIfPresent(NetBoxLabel.self, forKey: .cable); mappings = try c.decode([Mapping].self, forKey: c.contains(.front) ? .front : .rear)
    }
    func validate(kind: PassivePortKind, id: Int, deviceID: Int) throws {
        guard id > 0, self.id == id, deviceID > 0, device.id == deviceID, mappingKind == kind, !name.isEmpty, (1...65535).contains(positions), (cable?.id ?? 1) > 0, mappings.count <= 1024,
              mappings.allSatisfy({ (1...positions).contains($0.position) && $0.otherPosition > 0 && (kind == .rear ? ($0.frontPort ?? 0) > 0 && $0.rearPort == nil : ($0.rearPort ?? 0) > 0 && $0.frontPort == nil) }) else { throw APIError.invalidResponse }
    }
}
struct PortDetailView: View {
    let client: APIClient; let kind: PassivePortKind; let deviceID: Int
    @State private var model: ReadDetailModel<PassivePort>
    @State private var refresh = UUID()
    init(client: APIClient, kind: PassivePortKind, id: Int, deviceID: Int) {
        self.client = client; self.kind = kind; self.deviceID = deviceID
        _model = State(initialValue: ReadDetailModel(fetch: {
            guard id > 0, deviceID > 0 else { throw APIError.invalidURL }
            let port: PassivePort = try await client.get("dcim/\(kind.rawValue)/\(id)/")
            try port.validate(kind: kind, id: id, deviceID: deviceID); return port
        }))
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage { StatusMessage(message: error); Button("Retry") { refresh = UUID() } }
            if let port = model.object {
                Section("Overview") {
                    Label(port.name, systemImage: "cable.connector").font(.title2.bold()).accessibilityIdentifier("passivePortTitle")
                    DetailField(title: "Type", value: port.type?.text ?? "—")
                    DetailField(title: "Positions", value: String(port.positions))
                    DetailField(title: "Description", value: port.description)
                }
                Section("Explore") {
                    NavigationLink { InventoryDetailView(service: InventoryService(client: client, kind: .devices), id: deviceID) } label: { Label(port.device.text, systemImage: "server.rack") }
                    if let cable = port.cable, let id = cable.id { NavigationLink { CableDetailView(client: client, id: id) { refresh = UUID() } } label: { Label(cable.text, systemImage: "cable.connector") } }
                }
                Section("Port mappings") {
                    if port.mappings.isEmpty { Text("No visible port mappings") }
                    ForEach(Array(port.mappings.enumerated()), id: \.offset) { index, mapping in
                        let otherID = kind == .rear ? mapping.frontPort ?? 0 : mapping.rearPort ?? 0
                        NavigationLink { PortDetailView(client: client, kind: kind == .rear ? .front : .rear, id: otherID, deviceID: deviceID) } label: {
                            Label("\(mapping.position) → #\(String(otherID)) · \(mapping.otherPosition)", systemImage: "arrow.triangle.branch")
                        }.accessibilityIdentifier("portMapping-\(index)")
                    }
                }
            }
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) { await model.reload() }.refreshable { await model.reload() }
    }
}
