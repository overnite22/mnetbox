import SwiftUI

@MainActor @Observable final class DeletionModel {
    let client: APIClient
    let target: DeletionTarget
    private(set) var snapshot: DeletionSnapshot?
    private(set) var working = false
    private(set) var attempted = false
    private(set) var deleted = false
    private(set) var errorMessage: String?
    var confirmation = ""
    init(client: APIClient, target: DeletionTarget) { self.client = client; self.target = target }
    var canDelete: Bool {
        snapshot?.blockers.isEmpty == true && confirmation == String(target.id) && !working && !attempted
    }
    func load() async {
        guard !working, !attempted else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { snapshot = try await client.deletionSnapshot(target); try Task.checkCancellation() }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func delete() async {
        guard canDelete, let snapshot else { return }
        attempted = true; working = true; errorMessage = nil
        defer { working = false }
        do { try await client.deleteObject(snapshot); deleted = true }
        catch { errorMessage = readErrorMessage(error) }
    }
    func checkCurrent() async {
        guard attempted, !working else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do {
            snapshot = try await client.deletionSnapshot(target)
            errorMessage = L10n.text("The object is still visible. Close this screen and review a new deletion if needed.")
        } catch {
            if case APIError.http(404, _) = error {
                errorMessage = L10n.text("The object is no longer visible. This does not prove deletion; verify its state in NetBox.")
            } else { errorMessage = readErrorMessage(error) }
        }
    }
}
struct DeletionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeletionModel
    @FocusState private var focused: Bool
    let onDeleted: () -> Void
    private enum Operation: Equatable { case load(UUID), delete(UUID), check(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, target: DeletionTarget, onDeleted: @escaping () -> Void) {
        _model = State(initialValue: DeletionModel(client: client, target: target)); self.onDeleted = onDeleted
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.snapshot?.object.title ?? "#\(model.target.id)").font(.headline).textSelection(.enabled)
                    Text("#\(model.target.id)")
                    Text(L10n.text(model.target.collection.titleKey))
                    if let parent = model.target.imageParent {
                        Text(parent.kind.singular + " · " + (model.snapshot?.imageParentTitle ?? "#\(parent.id)"))
                        Text(L10n.format("Parent #%ld", parent.id)).font(.caption)
                    }
                    if let kind = model.target.collection.interfaceKind, let parent = model.snapshot?.object.parent {
                        Text(kind.parentKind.singular + " · " + parent.text)
                        Text(L10n.format("Parent #%ld", parent.id ?? 0)).font(.caption)
                    }
                    if model.target.collection == .prefixes || model.target.collection == .ipAddresses {
                        DetailField(title: "VRF", value: model.snapshot?.object.vrf?.text ?? L10n.text("Global VRF"))
                    }
                }
                if let ends = model.snapshot?.object.cableEnds, model.target.collection == .cables {
                    Section("Cable ends") {
                        if ends.isEmpty { Text("No visible terminations").foregroundStyle(.secondary) }
                        ForEach(Array(ends.enumerated()), id: \.offset) { _, line in Text(line).font(.callout) }
                        Text("Only the cable record is deleted. Ports, devices and their configuration are not changed.").font(.caption)
                    }.accessibilityIdentifier("cableDeletionEnds")
                }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if model.attempted && !model.deleted && !model.working {
                    Text("Deletion was not confirmed. No second attempt is sent from this screen. Check NetBox before starting another deletion.")
                    Button("Check current object") { operation = .check(UUID()) }.accessibilityIdentifier("checkDeletionOutcome")
                }
                if model.deleted {
                    Label("Object deleted", systemImage: "checkmark.circle").accessibilityIdentifier("deletionSucceeded")
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if !snapshot.blockers.isEmpty {
                        Section("Deletion blocked") {
                            ForEach(snapshot.blockers, id: \.self) { Label(L10n.text(["ipam/prefixes/": "Prefixes", "ipam/ip-addresses/": "IP addresses", "ipam/ip-ranges/": "IP ranges", "ipam/vlans/": "VLANs", "ipam/asns/": "ASNs", "dcim/interfaces/": "Physical interfaces", "virtualization/interfaces/": "VM interfaces"][$0] ?? $0), systemImage: "exclamationmark.triangle") }
                            Text("Remove dependencies deliberately in NetBox, then review again. Nothing is detached automatically.")
                        }.accessibilityIdentifier("deletionBlocked")
                    } else if !model.attempted {
                        Section("Deletion preview") {
                            Text("This permanently deletes one object in NetBox. The app cannot undo it.")
                            Text("Checks cover visible dependencies only. NetBox permissions and constraints still apply.").font(.caption)
                            Text("An object managed by your synchronization may be recreated by its next run.").font(.caption)
                            if !model.attempted {
                                TextField("Type the object ID to confirm", text: $model.confirmation).keyboardType(.numberPad).focused($focused)
                                    .accessibilityIdentifier("deletionConfirmationID")
                                Button("Confirm deletion", role: .destructive) { focused = false; operation = .delete(UUID()) }
                                    .disabled(!model.canDelete).accessibilityIdentifier("confirmDeletion")
                            }
                        }
                    }
                } else if !model.working && !model.attempted {
                    Button("Retry checks") { operation = .load(UUID()) }
                }
                if model.working { ProgressView("Loading…") }
            }
            .navigationTitle("Delete object").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
            }
            .interactiveDismissDisabled(model.working)
            .task(id: operation) {
                switch operation {
                case .load: await model.load()
                case .delete: await model.delete(); if model.deleted { onDeleted() }
                case .check: await model.checkCurrent()
                }
            }
        }
    }
}
