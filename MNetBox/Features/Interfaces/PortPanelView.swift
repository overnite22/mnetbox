import SwiftUI

enum PortPanelFamily: String, CaseIterable, Sendable {
    case interfaces, front = "front-ports", rear = "rear-ports", console = "console-ports", consoleServer = "console-server-ports", power = "power-ports", outlet = "power-outlets"
    var portKind: DevicePortKind? { DevicePortKind(rawValue: rawValue) }
    var path: String { "dcim/\(rawValue)/" }
    var title: String { portKind?.title ?? L10n.text("Interfaces") }
}
enum PortPanelState: String, Codable, CaseIterable, Sendable {
    case cabled, disabled, unconnected, unknown
    var title: String { L10n.text([.cabled: "Cabled", .disabled: "Disabled", .unconnected: "No cable", .unknown: "Unknown"][self] ?? "Unknown") }
    var color: Color { switch self { case .cabled: .green; case .disabled: .secondary; case .unconnected: .blue; case .unknown: .orange } }
    var symbol: String { switch self { case .cabled: "link"; case .disabled: "pause.fill"; case .unconnected: "circle"; case .unknown: "questionmark" } }
}
struct PortPanelRecord: Codable, Identifiable, Sendable {
    let id: Int; let name: String; let device: NetBoxLabel
    let occupied: Bool?; let marked: Bool?
    let enabled: Bool?; let cable: NetBoxLabel?; let type: VLANBrowseChoice?
    let hasCableField: Bool
    enum CodingKeys: String, CodingKey { case id, name, device, enabled, cable, type; case occupied = "_occupied", marked = "mark_connected" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name); device = try c.decode(NetBoxLabel.self, forKey: .device)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled); cable = try c.decodeIfPresent(NetBoxLabel.self, forKey: .cable); type = try c.decodeIfPresent(VLANBrowseChoice.self, forKey: .type)
        occupied = try c.decodeIfPresent(Bool.self, forKey: .occupied); marked = try c.decodeIfPresent(Bool.self, forKey: .marked)
        hasCableField = c.contains(.cable)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(device, forKey: .device)
        try c.encodeIfPresent(enabled, forKey: .enabled); try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(occupied, forKey: .occupied); try c.encodeIfPresent(marked, forKey: .marked)
        if hasCableField { try c.encode(cable, forKey: .cable) }
    }
    var state: PortPanelState {
        if enabled == false { return .disabled }
        if cable != nil { return .cabled }
        return hasCableField ? .unconnected : .unknown
    }
    func cableCandidate(family: PortPanelFamily) -> Bool {
        CableEndpointSelection.families.contains(family) && hasCableField && cable == nil && occupied == false && marked == false && (family != .interfaces || CableEndpointSnapshot.connectableType(type?.value))
    }
    enum Connector { case copper, fiber, power, console, generic }
    func connector(family: PortPanelFamily) -> Connector {
        if family == .power || family == .outlet { return .power }
        if family == .console || family == .consoleServer { return .console }
        let type = self.type?.value?.lowercased() ?? ""
        if type.contains("base-t") || type == "8p8c" { return .copper }
        if type.contains("sfp") || type.contains("qsfp") || ["lc", "sc", "mpo", "mpo12", "mpo24"].contains(type) { return .fiber }
        return .generic
    }
    static func ordered(_ records: [Self]) -> [Self] {
        records.sorted { a, b in
            let order = a.name.compare(b.name, options: [.numeric, .caseInsensitive])
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
    func validate(deviceID: Int) throws {
        guard id > 0, !name.isEmpty, deviceID > 0, device.id == deviceID, (cable == nil || (cable?.id ?? 0) > 0) else { throw APIError.invalidResponse }
    }
}
struct PortPanelQuery: Equatable, Sendable {
    var family: PortPanelFamily = .interfaces
    var search = ""
}
struct PortPanelService: Sendable {
    let client: APIClient; let deviceID: Int
    func page(query: PortPanelQuery, next: String?) async throws -> NetBoxPage<PortPanelRecord> {
        guard deviceID > 0 else { throw APIError.invalidReference }
        let items = DevicePortQuery(search: query.search).items + [.init(name: "device_id", value: String(deviceID))]
        try CollectionLinks.validate(next, path: query.family.path, required: items)
        let page: NetBoxPage<PortPanelRecord> = try await client.get(next ?? query.family.path, query: next == nil ? items : [])
        guard page.count >= page.results.count, page.results.count <= 50, Set(page.results.map(\.id)).count == page.results.count,
              page.next == nil || !page.results.isEmpty else { throw APIError.invalidResponse }
        try CollectionLinks.validate(page.next, path: query.family.path, required: items)
        for port in page.results { try port.validate(deviceID: deviceID) }; return page
    }
}
private struct PortPanelTile: View {
    let port: PortPanelRecord; let family: PortPanelFamily; let selected: Bool
    private var symbol: String {
        switch port.connector(family: family) {
        case .copper: "network"
        case .fiber: "cable.connector.horizontal"
        case .power: "bolt.fill"
        case .console: "terminal.fill"
        case .generic: "cable.connector"
        }
    }
    private var shortName: String {
        let digits = String(port.name.reversed().prefix { $0.isNumber }.reversed())
        return digits.isEmpty ? port.name : digits
    }
    var body: some View {
        VStack(spacing: 5) {
            Text(shortName).font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle).frame(height: 16)
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(port.state.color.opacity(port.state == .disabled ? 0.25 : 0.85))
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).foregroundStyle(port.state == .disabled ? Color.secondary : .white)
            }.frame(width: 36, height: 36)
                .padding(3)
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 3) }
        }.frame(width: 44).contentShape(Rectangle())
    }
}
struct PortPanelView: View {
    let service: PortPanelService; let title: String
    let excluding: CableEndpointSelection?
    let onSelect: ((CableEndpointSelection) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var cableSource: CableEndpointSelection?
    @State private var loadedFamily = PortPanelFamily.interfaces
    @State private var model: PaginatedListModel<PortPanelRecord, PortPanelQuery>
    @State private var query = PortPanelQuery(); @State private var refresh = UUID(); @State private var more = 0
    @State private var filter = "all"
    @State private var selectedID: Int?
    @State private var availableFamilies: [PortPanelFamily] = []
    @State private var familyErrors = false
    @State private var discovering = true
    private struct Request: Equatable { let query: PortPanelQuery; let refresh: UUID }
    init(client: APIClient, deviceID: Int, title: String, excluding: CableEndpointSelection? = nil, onSelect: ((CableEndpointSelection) -> Void)? = nil) {
        self.excluding = excluding; self.onSelect = onSelect
        let service = PortPanelService(client: client, deviceID: deviceID); self.service = service; self.title = title
        _model = State(initialValue: PaginatedListModel(query: PortPanelQuery(), fetch: { try await service.page(query: $0, next: $1) }))
    }
    private var shown: [PortPanelRecord] { PortPanelRecord.ordered((loadedFamily == query.family ? model.objects : []).filter { filter == "all" || $0.state.rawValue == filter }) }
    @ViewBuilder private func destination(_ port: PortPanelRecord) -> some View {
        if query.family == .interfaces { InterfaceDetailView(service: .init(client: service.client, kind: .physical, parentID: service.deviceID), id: port.id) }
        else if let kind = query.family.portKind, let passive = kind.passive { PortDetailView(client: service.client, kind: passive, id: port.id, deviceID: service.deviceID) }
        else if let kind = query.family.portKind { DevicePortDetailView(service: .init(client: service.client, kind: kind, deviceID: service.deviceID), id: port.id) }
    }
    private func endpoint(_ port: PortPanelRecord) -> CableEndpointSelection {
        .init(family: query.family, id: port.id, deviceID: service.deviceID, deviceName: title, name: port.name)
    }
    private func selectable(_ port: PortPanelRecord) -> Bool {
        port.cableCandidate(family: query.family) && !(excluding?.family == query.family && excluding?.id == port.id)
            && (excluding.map { CableEndpointSelection.compatible($0.family, query.family) } ?? true)
    }
    private func portButton(_ port: PortPanelRecord) -> some View {
        Button { selectedID = port.id } label: { PortPanelTile(port: port, family: query.family, selected: selectedID == port.id) }
            .buttonStyle(.plain).accessibilityLabel(port.name + ", " + port.state.title)
            .accessibilityAddTraits(selectedID == port.id ? .isSelected : [])
            .accessibilityIdentifier("panelPort-\(query.family.rawValue)-\(port.id)")
    }
    private var portFace: some View {
        bank(shown).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
    private func bank(_ ports: [PortPanelRecord]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(Array(stride(from: 0, to: ports.count, by: 2)), id: \.self) { index in
                    portPair(ports[index], second: index + 1 < ports.count ? ports[index + 1] : nil)
                }
            }.padding(4)
        }
    }
    private func portPair(_ first: PortPanelRecord, second: PortPanelRecord?) -> some View {
        VStack(spacing: 8) {
            portButton(first)
            if let second { portButton(second) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "server.rack").font(.largeTitle).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) { Text(title).font(.title2.bold()); Text(query.family.title).font(.subheadline).foregroundStyle(.secondary) }
                    Spacer()
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                HStack {
                if availableFamilies.count > 1 {
                    Picker("Port family", selection: $query.family) { ForEach(availableFamilies, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("panelFamily")
                }
                    Spacer()
                    Picker("Documented state", selection: $filter) { Text("All").tag("all"); ForEach(PortPanelState.allCases, id: \.self) { Text($0.title).tag($0.rawValue) } }.accessibilityIdentifier("panelState")
                }
                if model.hasLoaded {
                    Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("panelCount")
                    HStack(spacing: 12) {
                        ForEach(PortPanelState.allCases, id: \.self) { state in
                            VStack(spacing: 3) { Text(String(model.objects.filter { $0.state == state }.count)).font(.headline.monospacedDigit()); Text(state.title).font(.caption2) }.foregroundStyle(state.color).frame(maxWidth: .infinity)
                        }
                    }.padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if model.isLoading { ProgressView("Loading…").frame(maxWidth: .infinity) }
                if let error = model.errorMessage { StatusMessage(message: error); Button("Retry") { if model.failedLoadingMore { more += 1 } else { refresh = UUID() } } }
                if discovering { ProgressView("Checking equipment ports…") }
                if familyErrors { StatusMessage(message: L10n.text("Some port families could not be checked. Refresh to retry.")) }
                if !shown.isEmpty { portFace }
                if let port = shown.first(where: { $0.id == selectedID }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: port.state.symbol).foregroundStyle(port.state.color).accessibilityHidden(true)
                            Text(port.name).font(.headline).accessibilityIdentifier("panelSelectedName")
                            Spacer()
                            Text(port.state.title).font(.caption).foregroundStyle(port.state.color)
                        }
                        if let type = port.type { Text(type.text).font(.subheadline).foregroundStyle(.secondary) }
                        if let cableID = port.cable?.id { Label(L10n.identifier("Cable #%ld", cableID), systemImage: "link").font(.subheadline) }
                        Divider()
                        if onSelect != nil {
                            Button("Choose this port") { onSelect?(endpoint(port)); dismiss() }.buttonStyle(.borderedProminent).disabled(!selectable(port)).accessibilityIdentifier("chooseCablePort")
                            if !selectable(port) { Text("Choose a free, compatible port different from the source.").font(.caption).foregroundStyle(.secondary) }
                        } else if selectable(port) {
                            Button("Connect a cable", systemImage: "cable.connector") { cableSource = endpoint(port) }.buttonStyle(.bordered).accessibilityIdentifier("connectCable")
                        }
                        NavigationLink { destination(port) } label: { Label("Open port details", systemImage: "arrow.up.forward.app") }
                            .accessibilityIdentifier("panelOpenDetails")
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                } else if !shown.isEmpty {
                    Text("Select a port to see its details.").font(.subheadline).foregroundStyle(.secondary)
                }
                if model.hasLoaded, shown.isEmpty, !model.isLoading { ContentUnavailableView("No matching ports", systemImage: "cable.connector") }
                if model.next != nil { Button("Load more") { more += 1 }.disabled(model.isLoading || model.isLoadingMore).frame(maxWidth: .infinity).accessibilityIdentifier("panelLoadMore") }
                Text("Logical layout by port name. Colors show NetBox documentation, not live link status. Counts describe loaded ports.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Port panel").navigationBarTitleDisplayMode(.inline).background(Color(.systemGroupedBackground))
        .searchable(text: $query.search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search NetBox")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading) }
        .task(id: refresh) {
            discovering = true
            var families: [PortPanelFamily] = []; var failed = false
            for family in (onSelect == nil ? PortPanelFamily.allCases : CableEndpointSelection.families.filter { family in excluding.map { CableEndpointSelection.compatible($0.family, family) } ?? true }) {
                do {
                    let page = try await service.page(query: .init(family: family), next: nil)
                    try Task.checkCancellation()
                    if page.count > 0 { families.append(family) }
                } catch {
                    if Task.isCancelled { return }
                    failed = true
                }
            }
            guard !Task.isCancelled else { return }
            availableFamilies = families; familyErrors = failed; discovering = false
            if !families.contains(query.family), let first = families.first { query.family = first }
        }
        .onChange(of: query) { selectedID = nil }
        .onChange(of: filter) { selectedID = nil }
        .task(id: Request(query: query, refresh: refresh)) {
            do { if !query.search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }; try Task.checkCancellation(); await model.reload(query: query); if !Task.isCancelled { loadedFamily = query.family } } catch { /* Superseded search. */ }
        }.task(id: more) { if more > 0 { await model.loadMore() } }
        .sheet(item: $cableSource, onDismiss: { refresh = UUID() }) { CableCreateView(client: service.client, source: $0) }
        .onAppear { refresh = UUID() }
        .refreshable { await model.reload(query: query) }
    }
}
