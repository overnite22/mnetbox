import SwiftUI

private func cableTint(_ hex: String) -> Color {
    let red = Double(Int(hex.prefix(2), radix: 16) ?? 0) / 255
    let green = Double(Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255
    let blue = Double(Int(hex.suffix(2), radix: 16) ?? 0) / 255
    return Color(red: red, green: green, blue: blue)
}

@MainActor @Observable final class CableCreateModel {
    let client: APIClient; let source: CableEndpointSelection
    var destination: CableEndpointSelection?
    var device: ReferenceSelection?
    var label = ""; var type = ""; var status = "connected"; var color = "0088ff"
    private(set) var reviewed: CableCreationPlan?
    private(set) var created: CableObject?
    private(set) var working = false; private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, source: CableEndpointSelection) { self.client = client; self.source = source }
    var plan: CableCreationPlan? {
        guard let destination else { return nil }
        return try? CableCreationPlan(a: source, b: destination, label: label.trimmingCharacters(in: .whitespacesAndNewlines), type: type, status: status, color: color).validated()
    }
    func review() async {
        guard !working, !attempted, let plan else { return }
        working = true; errorMessage = nil; defer { working = false }
        do { try await client.checkCableCreation(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = (error as? CableCreationError)?.errorDescription ?? readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil; defer { working = false }
        do { created = try await client.createCable(reviewed) }
        catch { errorMessage = (error as? CableCreationError)?.errorDescription ?? readErrorMessage(error) }
    }
}
struct CableConnectionPreview: View {
    let a: CableEndpointSelection; let b: CableEndpointSelection?; let color: String
    private var tint: Color { cableTint(color) }
    private func endpoint(_ value: CableEndpointSelection?, side: String) -> some View {
        HStack(spacing: 12) {
            Text(side).font(.headline).frame(width: 36, height: 36).background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(value?.deviceName ?? L10n.text("Choose destination equipment")).font(.headline)
                Text(value?.name ?? L10n.text("Choose a free port")).font(.subheadline).foregroundStyle(.secondary)
                if let value { Text(value.family.title).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "cable.connector").foregroundStyle(tint)
        }.padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    var body: some View {
        VStack(spacing: 0) {
            endpoint(a, side: "A")
            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    path.move(to: CGPoint(x: width - 30, y: 0))
                    path.addCurve(to: CGPoint(x: 30, y: 55), control1: CGPoint(x: width - 30, y: 45), control2: CGPoint(x: 30, y: 10))
                }.stroke(tint.opacity(b == nil ? 0.35 : 1), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: b == nil ? [6, 6] : []))
            }.frame(height: 55).accessibilityHidden(true)
            endpoint(b, side: "B")
        }.accessibilityIdentifier("connectionPreview")
    }
}
struct CableCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CableCreateModel
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, source: CableEndpointSelection) { _model = State(initialValue: CableCreateModel(client: client, source: source)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.client.serverDisplay).font(.caption).foregroundStyle(.secondary)
                    CableConnectionPreview(a: model.source, b: model.reviewed?.b ?? model.destination, color: model.reviewed?.color ?? model.color)
                    if let error = model.errorMessage { StatusMessage(message: error) }
                    if let created = model.created {
                        Label("Cable created", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("cableCreated")
                        NavigationLink("Open created cable") { CableDetailView(client: model.client, id: created.id) }
                        Button("Done") { dismiss() }
                    } else if let plan = model.reviewed {
                        Text("Connection review").font(.title2.bold())
                        DetailField(title: "Label", value: plan.label)
                        DetailField(title: "Type", value: plan.type.isEmpty ? L10n.text("Unspecified") : plan.type)
                        DetailField(title: "Status", value: L10n.text(plan.status.capitalized))
                        Text("This creates one cable in NetBox. It does not configure the equipment.").font(.caption).foregroundStyle(.secondary)
                        if !model.attempted {
                            Button("Confirm connection") { operation = .create(UUID()) }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmCableCreation")
                            Button("Back to editing") { model.back() }
                        }
                    } else {
                        Text("Destination").font(.headline)
                        NavigationLink {
                            ReferencePickerView(client: model.client, path: "dcim/devices/", title: "Choose destination equipment", selection: $model.device, allowsEmpty: false)
                        } label: { Label(model.device?.title ?? L10n.text("Choose destination equipment"), systemImage: "server.rack") }.accessibilityIdentifier("cableDestinationDevice")
                        if let device = model.device {
                            NavigationLink {
                                PortPanelView(client: model.client, deviceID: device.id, title: device.title, excluding: model.source, onSelect: { model.destination = $0 })
                            } label: { Label(model.destination?.name ?? L10n.text("Choose a free port"), systemImage: "rectangle.split.3x3") }.accessibilityIdentifier("cableDestinationPort")
                        }
                        TextField("Label", text: $model.label).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("cableCreationLabel")
                        Picker("Type", selection: $model.type) { ForEach(CableCreationPlan.types, id: \.self) { Text($0.isEmpty ? L10n.text("Unspecified") : $0).tag($0) } }
                        Picker("Status", selection: $model.status) { Text("Connected").tag("connected"); Text("Planned").tag("planned") }
                        HStack(spacing: 14) {
                            ForEach(CableCreationPlan.colors, id: \.self) { color in
                                Button { model.color = color } label: {
                                    Circle().fill(cableTint(color)).frame(width: 30, height: 30).padding(5)
                                        .overlay { Circle().stroke(model.color == color ? Color.primary : Color.clear, lineWidth: 2) }
                                }.accessibilityLabel(L10n.text("Cable color") + " " + color)
                            }
                        }
                        Button("Review connection") { operation = .review(UUID()) }.buttonStyle(.borderedProminent).disabled(model.plan == nil).accessibilityIdentifier("reviewCableCreation")
                    }
                    if model.attempted && model.created == nil && !model.working {
                        Text("Creation was not confirmed. Check the ports and cable list in NetBox before starting again; the request may have succeeded.").font(.callout)
                    }
                    if model.working { ProgressView("Loading…") }
                }.padding().disabled(model.working || (model.attempted && model.created == nil))
            }.background(Color(.systemGroupedBackground)).navigationTitle("Connect a cable").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
                .interactiveDismissDisabled(model.working)
                .onChange(of: model.device) { model.destination = nil }
                .task(id: operation) { switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() } }
        }
    }
}
