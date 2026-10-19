import SwiftUI

struct RackElevationView: View {
    let client: APIClient
    let title: String
    @State private var model: RackElevationModel
    @State private var face = RackFace.front
    @State private var refreshID = UUID()
    private struct Request: Equatable { let face: RackFace; let refresh: UUID }

    init(client: APIClient, rackID: Int, title: String) {
        self.client = client; self.title = title
        _model = State(initialValue: RackElevationModel(service: RackElevationService(client: client, rackID: rackID)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    InventoryIllustration(kind: .racks).frame(width: 64, height: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.title2.bold())
                        Text("Tap an equipment to view its details.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker("Face", selection: $face) {
                    Text("Front").tag(RackFace.front)
                    Text("Rear").tag(RackFace.rear)
                }.pickerStyle(.segmented).accessibilityIdentifier("rackFace")
                if model.isLoading { ProgressView("Loading elevation…").frame(maxWidth: .infinity) }
                if let error = model.errorMessage {
                    StatusMessage(message: error)
                    Button("Retry") { refreshID = UUID() }
                }
                if model.hasLoaded {
                    if model.units.isEmpty { ContentUnavailableView("No rack units", systemImage: "cabinet") }
                    else {
                        HStack {
                            Label(L10n.format("%ld occupied half-units", model.units.filter(\.occupied).count), systemImage: "server.rack")
                            Spacer()
                            Text(L10n.format("%ld total", model.units.count)).foregroundStyle(.secondary)
                        }.font(.caption)
                        VStack(spacing: 2) {
                            HStack { Circle().frame(width: 6); Spacer(); Circle().frame(width: 6) }
                                .foregroundStyle(.secondary).padding(8)
                            ForEach(model.units) { unit in
                                HStack(spacing: 8) {
                                    Text(unit.name).font(.caption.monospaced()).frame(width: 48, alignment: .trailing)
                                    if let device = unit.device, let id = device.id {
                                        NavigationLink {
                                            InventoryDetailView(service: InventoryService(client: client, kind: .devices), id: id)
                                        } label: { equipment(unit, text: device.text) }
                                        .accessibilityIdentifier("rackDevice-\(id)-\(unit.id)")
                                    } else {
                                        equipment(unit, text: L10n.text(unit.occupied ? "Occupied · restricted" : "Empty"))
                                    }
                                }
                            }
                            HStack { Circle().frame(width: 6); Spacer(); Circle().frame(width: 6) }
                                .foregroundStyle(.secondary).padding(8)
                        }
                        .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        Text("Each row represents ½ U. The order and occupancy come from NetBox. Occupied spaces can contain equipment hidden by your permissions; reservations and unmounted devices are not shown here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding()
        }
        .navigationTitle("Rack elevation").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .accessibilityIdentifier("refreshRackElevation").disabled(model.isLoading)
        }
        .task(id: Request(face: face, refresh: refreshID)) { await model.reload(face: face) }
        .refreshable { await model.reload(face: face) }
    }

    private func equipment(_ unit: RackUnit, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: unit.device != nil ? "server.rack" : unit.occupied ? "lock.fill" : "minus")
            Text(text).font(.subheadline.weight(unit.occupied ? .semibold : .regular))
            Spacer(minLength: 0)
            if unit.device != nil {
                Image(systemName: "circle.fill").font(.system(size: 5))
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .foregroundStyle(unit.device != nil ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10).frame(minHeight: 44)
        .frame(maxWidth: .infinity)
        .background(unit.occupied ? Color.accentColor.opacity(0.13) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore).accessibilityLabel("\(unit.name), \(text)")
    }
}
