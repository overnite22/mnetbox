import SwiftUI

@MainActor @Observable final class MarkConnectedModel {
    let client: APIClient; let port: CableEndpointSelection
    private(set) var current: Bool?
    private(set) var cabled = false
    private var etag = ""
    private(set) var saved = false
    private(set) var working = false; private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, port: CableEndpointSelection) { self.client = client; self.port = port }
    var proposed: Bool? { current.map { !$0 } }
    var canSave: Bool { proposed != nil && !working && !attempted && !(proposed == true && cabled) }
    func load() async {
        guard !working, !attempted else { return }
        working = true; errorMessage = nil; defer { working = false }
        do {
            let (snapshot, tag) = try await client.markConnectedSnapshot(port)
            current = snapshot.marked; cabled = snapshot.cable != nil; etag = tag
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func save() async {
        guard canSave, let proposed else { return }
        attempted = true; working = true; errorMessage = nil; defer { working = false }
        do { _ = try await client.setMarkConnected(port, etag: etag, to: proposed); saved = true }
        catch { errorMessage = (error as? CableCreationError)?.errorDescription ?? readErrorMessage(error) }
    }
}

struct MarkConnectedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: MarkConnectedModel
    private enum Operation: Equatable { case load(UUID), save(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, port: CableEndpointSelection) { _model = State(initialValue: MarkConnectedModel(client: client, port: port)) }
    private func state(_ value: Bool?) -> String {
        value.map { L10n.text($0 ? "Marked connected" : "Not marked") } ?? "—"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.port.deviceName + " · " + model.port.name).font(.headline)
                    Text(verbatim: "#\(model.port.id)").font(.caption)
                }
                Section("Before") { Text(state(model.current)) }
                Section("After") { Text(state(model.proposed)) }
                Section {
                    Text("Documents a connection that is not modeled by a cable, for example to unmanaged equipment. Nothing is configured on the device.").font(.caption)
                    if model.cabled && model.proposed == true { Text("A port with a cable cannot be marked connected.").font(.caption).foregroundStyle(.red) }
                    if let error = model.errorMessage { StatusMessage(message: error) }
                    if model.saved {
                        Label("Change saved", systemImage: "checkmark.circle").accessibilityIdentifier("markConnectedSaved")
                        Button("Done") { dismiss() }
                    } else if !model.attempted {
                        Button("Confirm change") { operation = .save(UUID()) }.disabled(!model.canSave).accessibilityIdentifier("markConnectedConfirm")
                    } else if !model.working {
                        Text("The change was not confirmed. Check the port in NetBox before trying again.").font(.callout)
                    }
                    if model.working { ProgressView("Loading…") }
                }
            }
            .navigationTitle("Connected mark").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
            .interactiveDismissDisabled(model.working)
            .task(id: operation) {
                switch operation { case .load: await model.load(); case .save: await model.save() }
            }
        }
    }
}
