import SwiftUI

struct CableTraceEndpoint: Decodable, Sendable {
    let id: Int
    let url: String
    let name: String
    let device: NetBoxLabel?
    private(set) var kind: String? = nil
    enum CodingKeys: String, CodingKey { case id, url, name, display, device }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); url = try c.decode(String.self, forKey: .url)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decode(String.self, forKey: .display)
        device = try c.decodeIfPresent(NetBoxLabel.self, forKey: .device)
    }
    mutating func validate(apiURL: URL) throws {
        guard id > 0, !name.isEmpty, device == nil || (device?.id ?? 0) > 0 else { throw APIError.invalidResponse }
        let paths = ["interfaces", "front-ports", "rear-ports", "console-ports", "console-server-ports", "power-ports", "power-outlets"]
        guard let root = URL(string: "dcim/", relativeTo: apiURL)?.absoluteURL else { throw APIError.invalidResponse }
        kind = paths.first { URL(string: "\($0)/\(id)/", relativeTo: root)?.absoluteURL.absoluteString == url }
        if kind != nil { guard (device?.id ?? 0) > 0 else { throw APIError.invalidResponse }; return }
        // Native non-device trace terminations have display labels and no device.
        for (path, value) in [("circuits/circuit-terminations/", "circuit-terminations"), ("circuits/provider-networks/", "provider-networks"), ("dcim/sites/", "sites"), ("dcim/power-feeds/", "power-feeds")] {
            if URL(string: "\(path)\(id)/", relativeTo: apiURL)?.absoluteURL.absoluteString == url { kind = value; return }
        }
        throw APIError.invalidResponse
    }
}
// Trace uses BaseModelSerializer: status is a raw string, not the detail choice object.
struct TracedCable: Decodable, Sendable {
    let id: Int
    let label: String?
    let status: VLANBrowseChoice?
    enum CodingKeys: String, CodingKey { case id, label, status }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        if let raw = try? c.decode(String.self, forKey: .status) { status = .init(value: raw, label: nil) }
        else { status = try c.decodeIfPresent(VLANBrowseChoice.self, forKey: .status) }
    }
}
struct CableTraceSegment: Decodable, Sendable {
    var near: [CableTraceEndpoint]
    let cable: TracedCable?
    var far: [CableTraceEndpoint]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        near = try c.decode([CableTraceEndpoint].self)
        if try c.decodeNil() { cable = nil }
        else if let absent = try? c.decode([Int].self) {
            guard absent.isEmpty else { throw APIError.invalidResponse }; cable = nil
        } else { cable = try c.decode(TracedCable.self) }
        far = try c.decodeIfPresent([CableTraceEndpoint].self) ?? []
        guard c.isAtEnd, !near.isEmpty, near.count <= 32, far.count <= 32,
              cable == nil || (cable?.id ?? 0) > 0 else { throw APIError.invalidResponse }
    }
}
struct CableTrace: Decodable, Sendable {
    var segments: [CableTraceSegment]
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer(); segments = []
        while !c.isAtEnd {
            guard segments.count < 64 else { throw APIError.invalidResponse }
            segments.append(try c.decode(CableTraceSegment.self))
        }
    }
    mutating func validate(apiURL: URL, interfaceID: Int, sourceKind: String = "interfaces") throws {
        guard interfaceID > 0 else { throw APIError.invalidURL }
        var cables = Set<Int>()
        for i in segments.indices {
            for j in segments[i].near.indices { try segments[i].near[j].validate(apiURL: apiURL) }
            for j in segments[i].far.indices { try segments[i].far[j].validate(apiURL: apiURL) }
            for endpoints in [segments[i].near, segments[i].far] {
                guard Set(endpoints.map(\.url)).count == endpoints.count else { throw APIError.invalidResponse }
            }
            if let cable = segments[i].cable { guard cables.insert(cable.id).inserted else { throw APIError.invalidResponse } }
        }
        guard segments.isEmpty || segments[0].near.contains(where: { $0.kind == sourceKind && $0.id == interfaceID }) else { throw APIError.invalidResponse }
    }
}

struct CableTraceView: View {
    let client: APIClient
    let title: String
    @State private var model: ReadDetailModel<CableTrace>
    @State private var refresh = UUID()
    init(client: APIClient, interfaceID: Int, title: String, portKind: DevicePortKind? = nil) {
        self.client = client; self.title = title
        _model = State(initialValue: ReadDetailModel(fetch: { try await client.cableTrace(id: interfaceID, portKind: portKind) }))
    }
    var body: some View {
        List {
            Section {
                Label(title, systemImage: "point.topleft.down.curvedto.point.bottomright.up").font(.title3.bold())
                Text("Physical cable path returned by NetBox. This does not describe IP routing or VM networking.").font(.caption).foregroundStyle(.secondary)
            }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage { StatusMessage(message: error); Button("Retry") { refresh = UUID() } }
            if let trace = model.object {
                if trace.segments.isEmpty { ContentUnavailableView("No visible cable path", systemImage: "cable.connector.slash") }
                ForEach(trace.segments.indices, id: \.self) { index in
                    Section(L10n.format("Step %ld", index + 1)) {
                        endpoints(trace.segments[index].near, color: .blue)
                        if let cable = trace.segments[index].cable {
                            NavigationLink { CableDetailView(client: client, id: cable.id) } label: {
                                Label(cable.label?.isEmpty == false ? cable.label ?? "" : L10n.format("Cable #%ld", cable.id), systemImage: "cable.connector").font(.headline).foregroundStyle(.orange)
                            }.accessibilityIdentifier("traceCable-\(cable.id)")
                            if let status = cable.status { DetailField(title: "Status", value: status.text) }
                        } else { Label(trace.segments[index].far.isEmpty ? "No visible cable" : "Internal port connection", systemImage: "arrow.down").foregroundStyle(.secondary) }
                        endpoints(trace.segments[index].far, color: .green)
                        if trace.segments[index].far.isEmpty { Label("No visible endpoint", systemImage: "questionmark.circle").foregroundStyle(.secondary) }
                    }
                }
                Text("The returned path may stop at a split, missing connection or restricted object. It is not proof of a complete connection.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cable trace").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) { await model.reload() }
        .refreshable { await model.reload() }
    }
    @ViewBuilder private func endpoints(_ values: [CableTraceEndpoint], color: Color) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, endpoint in
            Group {
                if endpoint.kind == "interfaces" {
                    NavigationLink { InterfaceDetailView(service: InterfaceService(client: client, kind: .physical), id: endpoint.id) } label: { Label(endpoint.name, systemImage: "network").foregroundStyle(color) }
                        .accessibilityIdentifier("traceInterface-\(endpoint.id)")
                } else if let kind = PassivePortKind(rawValue: endpoint.kind ?? "") {
                    NavigationLink { PortDetailView(client: client, kind: kind, id: endpoint.id, deviceID: endpoint.device?.id ?? 0) } label: { Label(endpoint.name, systemImage: "cable.connector").foregroundStyle(color) }.accessibilityIdentifier("tracePort-\(kind.rawValue)-\(endpoint.id)")
                } else if let kind = DevicePortKind(rawValue: endpoint.kind ?? ""), let deviceID = endpoint.device?.id, kind.traceable {
                    NavigationLink { DevicePortDetailView(service: .init(client: client, kind: kind, deviceID: deviceID), id: endpoint.id) } label: { Label(endpoint.name, systemImage: kind.symbol).foregroundStyle(color) }.accessibilityIdentifier("traceDevicePort-\(endpoint.id)")
                } else { Label(endpoint.name, systemImage: "cable.connector").foregroundStyle(color) }
                Text(L10n.text(endpoint.kind == "front-ports" ? "Front port" : endpoint.kind == "rear-ports" ? "Rear port" : endpoint.kind == "interfaces" ? "Physical interface" : "Port")).font(.caption).foregroundStyle(.secondary)
                if let device = endpoint.device {
                    NavigationLink { InventoryDetailView(service: InventoryService(client: client, kind: .devices), id: device.id ?? 0) } label: { Label(device.text, systemImage: "server.rack").font(.subheadline) }
                }
            }
        }
    }
}
