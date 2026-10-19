import SwiftUI

@MainActor @Observable final class VLANEditModel {
    let client: APIClient
    let target: StructuredEditTarget
    private(set) var snapshot: VLANSnapshot?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    var draft = VLANPlan(mode: "", untagged: nil, tagged: [])
    init(client: APIClient, target: StructuredEditTarget) { self.client = client; self.target = target }
    var canReview: Bool {
        guard let snapshot, (try? draft.validate()) != nil else { return false }
        return !isLoading && !isSaving && !requiresReload && !saved && !draft.matches(snapshot.object.plan)
    }
    var validationMessage: String? {
        do { try draft.validate(); return nil } catch { return readErrorMessage(error) }
    }
    func load() async {
        guard !isLoading, !isSaving, !saved else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await client.vlanSnapshot(target: target)
            try Task.checkCancellation()
            if self.snapshot == nil { draft = snapshot.object.plan }
            self.snapshot = snapshot; requiresReload = false
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func review() async -> VLANPlan? {
        guard canReview, let snapshot else { return nil }
        let proposal = draft
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.checkVLANPlan(proposal, snapshot: snapshot)
            try Task.checkCancellation()
            guard proposal.matches(draft) else { return nil }
            return proposal
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error); requiresReload = true }; return nil }
    }
    func save(_ reviewed: VLANPlan) async {
        guard canReview, let snapshot, reviewed.matches(draft) else { return }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client.updateVLAN(snapshot, to: reviewed)
            try Task.checkCancellation()
            saved = true
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) }; requiresReload = true }
    }
}

struct VLANEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: VLANEditModel
    @State private var reviewed: VLANPlan?
    @State private var candidate: ReferenceSelection?
    @State private var operation = UUID()
    @State private var action = Action.load
    private enum Action { case load, review, save }
    init(client: APIClient, target: StructuredEditTarget) { _model = State(initialValue: VLANEditModel(client: client, target: target)) }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.snapshot?.object.name ?? "—").bold()
                    Text(verbatim: "#\(model.target.id)")
                    DetailField(title: "Parent ID", value: model.target.parentID.map(String.init) ?? "—")
                }
                if model.isLoading || model.isSaving { ProgressView("Loading…") }
                if let error = model.errorMessage { Section { StatusMessage(message: error) } }
                if model.saved {
                    Section { Label("Saved", systemImage: "checkmark.circle").accessibilityIdentifier("vlanSaved"); Button("Done") { dismiss() } }
                } else if let snapshot = model.snapshot {
                    if let reviewed {
                        Section("Before") { summary(snapshot.object.plan) }
                        Section("After") { summary(reviewed) }
                        Section {
                            Text("This changes VLAN mode, untagged VLAN and tagged VLANs together on this interface.")
                            Button("Confirm change") { action = .save; operation = UUID() }.disabled(!model.canReview).accessibilityIdentifier("vlanConfirm")
                            Button("Back to editing") { self.reviewed = nil }.disabled(model.isSaving)
                        }
                    } else {
                        Section("VLAN configuration") {
                            Picker("VLAN mode", selection: $model.draft.mode) {
                                ForEach(VLANMode.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                            }.accessibilityIdentifier("vlanModeDraft")
                            NavigationLink {
                                VLANPickerView(client: model.client, siteID: snapshot.siteID, selection: $model.draft.untagged, allowsEmpty: true)
                            } label: { DetailField(title: "Untagged VLAN", value: model.draft.untagged?.title ?? L10n.text("None")) }
                            .accessibilityIdentifier("vlanUntaggedPicker")
                            ForEach(model.draft.tagged, id: \.id) { vlan in
                                HStack {
                                    Text(vlan.title)
                                    Spacer()
                                    Button("Remove", systemImage: "minus.circle") { model.draft.tagged.removeAll { $0.id == vlan.id } }
                                        .labelStyle(.iconOnly).accessibilityLabel(L10n.text("Remove") + " " + vlan.title)
                                        .accessibilityIdentifier("removeVLAN-\(vlan.id)")
                                }
                            }
                            NavigationLink {
                                VLANPickerView(client: model.client, siteID: snapshot.siteID, selection: $candidate, allowsEmpty: false)
                            } label: { Label("Add tagged VLAN", systemImage: "plus") }.accessibilityIdentifier("vlanTaggedPicker")
                            if !model.draft.tagged.isEmpty { Button("Clear tagged VLANs") { model.draft.tagged = [] }.accessibilityIdentifier("clearTaggedVLANs") }
                            Text("Changing mode keeps your selections. Remove incompatible VLANs explicitly before review.").font(.caption).foregroundStyle(.secondary)
                            if let error = model.validationMessage { StatusMessage(message: error) }
                        }.disabled(model.isLoading || model.isSaving || model.requiresReload)
                        Section { Button("Review change") { action = .review; operation = UUID() }.disabled(!model.canReview).accessibilityIdentifier("vlanReview") }
                    }
                }
                if model.requiresReload || (model.snapshot == nil && !model.isLoading) {
                    Button("Reload from server") { reviewed = nil; action = .load; operation = UUID() }.disabled(model.isSaving).accessibilityIdentifier("vlanReload")
                }
            }
            .navigationTitle("Edit VLAN configuration").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) } }
            .interactiveDismissDisabled(model.isSaving)
            .task(id: operation) {
                switch action {
                case .load: await model.load()
                case .review: reviewed = await model.review()
                case .save: if let reviewed { await model.save(reviewed) }
                }
            }
            .onChange(of: candidate) { _, value in
                if let value, !model.draft.tagged.contains(where: { $0.id == value.id }) { model.draft.tagged.append(value) }
                candidate = nil
            }
        }
    }
    private func summary(_ plan: VLANPlan) -> some View {
        Group {
            DetailField(title: "VLAN mode", value: VLANMode(rawValue: plan.mode)?.title ?? plan.mode)
            DetailField(title: "Untagged VLAN", value: plan.untagged.map { "\($0.title) (#\($0.id))" } ?? L10n.text("None"))
            DetailField(title: "Tagged VLANs", value: plan.tagged.isEmpty ? L10n.text("None") : plan.tagged.sorted { $0.id < $1.id }.map { "\($0.title) (#\($0.id))" }.joined(separator: ", "))
        }
    }
}
