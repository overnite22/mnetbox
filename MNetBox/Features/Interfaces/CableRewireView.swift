import SwiftUI

@MainActor @Observable final class CableRewireModel {
    let client: APIClient; let cableID: Int; let side: CableSide
    private(set) var current: CableEndpointSelection?
    private(set) var kept: CableEndpointSelection?
    private var etag = ""
    var device: ReferenceSelection?
    var destination: CableEndpointSelection?
    private(set) var reviewed: CableRewirePlan?
    private(set) var moved: CableObject?
    private(set) var working = false; private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, cableID: Int, side: CableSide) { self.client = client; self.cableID = cableID; self.side = side }
    var plan: CableRewirePlan? {
        guard let current, let kept, let destination else { return nil }
        return try? CableRewirePlan(cableID: cableID, etag: etag, side: side, current: current, kept: kept, destination: destination).validated()
    }
    func load() async {
        guard !working, !attempted else { return }
        working = true; errorMessage = nil; defer { working = false }
        do {
            let (cable, tag) = try await client.cableRewireSnapshot(id: cableID)
            let ends = try CableRewirePlan.ends(of: cable)
            current = side == .a ? ends.a : ends.b
            kept = side == .a ? ends.b : ends.a
            etag = tag
        } catch { if !Task.isCancelled { errorMessage = message(error) } }
    }
    func review() async {
        guard !working, !attempted, let plan else { return }
        working = true; errorMessage = nil; defer { working = false }
        do { try await client.checkCableRewire(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = message(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func confirm() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil; defer { working = false }
        do { moved = try await client.rewireCable(reviewed) }
        catch { errorMessage = message(error) }
    }
    private func message(_ error: Error) -> String {
        (error as? CableCreationError)?.errorDescription ?? readErrorMessage(error)
    }
}

struct CableRewireView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CableRewireModel
    let onMoved: () -> Void
    private enum Operation: Equatable { case load(UUID), review(UUID), confirm(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, cableID: Int, side: CableSide, onMoved: @escaping () -> Void) {
        _model = State(initialValue: CableRewireModel(client: client, cableID: cableID, side: side)); self.onMoved = onMoved
    }
    private func endLine(_ title: String, _ value: CableEndpointSelection?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title)).font(.caption).foregroundStyle(.secondary)
            Text(value.map { $0.deviceName + " · " + $0.name } ?? "—").font(.headline)
            if let value { Text(value.family.title).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.client.serverDisplay).font(.caption).foregroundStyle(.secondary)
                    Text(L10n.identifier("Cable #%ld", model.cableID) + " · " + L10n.format("End %@", model.side.title)).font(.headline)
                    if let error = model.errorMessage { StatusMessage(message: error) }
                    if let kept = model.kept {
                        endLine("Kept end", kept)
                        endLine("Current end", model.current)
                        Image(systemName: "arrow.down").foregroundStyle(.tint).frame(maxWidth: .infinity).accessibilityHidden(true)
                        endLine("New end", model.reviewed?.destination ?? model.destination)
                        if model.moved != nil {
                            Label("Cable end moved", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("cableRewired")
                            Button("Done") { dismiss() }
                        } else if model.reviewed != nil {
                            Text("This moves one end of the cable in NetBox. The previous port becomes free; no equipment is configured.").font(.caption).foregroundStyle(.secondary)
                            if !model.attempted {
                                Button("Confirm move") { operation = .confirm(UUID()) }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmCableRewire")
                                Button("Back to editing") { model.back() }
                            }
                        } else {
                            NavigationLink {
                                ReferencePickerView(client: model.client, path: "dcim/devices/", title: "Choose destination equipment", selection: $model.device, allowsEmpty: false)
                            } label: { Label(model.device?.title ?? L10n.text("Choose destination equipment"), systemImage: "server.rack") }.accessibilityIdentifier("rewireDevice")
                            if let device = model.device {
                                NavigationLink {
                                    PortPanelView(client: model.client, deviceID: device.id, title: device.title, excluding: kept, onSelect: { model.destination = $0 })
                                } label: { Label(model.destination?.name ?? L10n.text("Choose a free port"), systemImage: "rectangle.split.3x3") }.accessibilityIdentifier("rewirePort")
                            }
                            Button("Review move") { operation = .review(UUID()) }.buttonStyle(.borderedProminent).disabled(model.plan == nil).accessibilityIdentifier("reviewCableRewire")
                        }
                    } else if !model.working, model.errorMessage != nil {
                        Text("Only cables with exactly one known device port on each side can be moved here.").font(.callout)
                        Button("Retry") { operation = .load(UUID()) }
                    }
                    if model.attempted && model.moved == nil && !model.working {
                        Text("The move was not confirmed. Check the cable in NetBox before trying again; the request may have succeeded.").font(.callout)
                    }
                    if model.working { ProgressView("Loading…") }
                }.padding().disabled(model.working || (model.attempted && model.moved == nil))
            }.background(Color(.systemGroupedBackground)).navigationTitle("Move cable end").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
                .interactiveDismissDisabled(model.working)
                .onChange(of: model.device) { model.destination = nil }
                .task(id: operation) {
                    switch operation {
                    case .load: await model.load()
                    case .review: await model.review()
                    case .confirm: await model.confirm(); if model.moved != nil { onMoved() }
                    }
                }
        }
    }
}
