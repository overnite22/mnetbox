import SwiftUI

@MainActor @Observable final class IPAMEditModel {
    let client: APIClient
    let kind: IPAMKind
    let id: Int
    let field: IPAMEditField
    var reference: ReferenceSelection?
    var scope = PrefixScope.global
    var cidr = ""
    private(set) var snapshot: IPAMEditSnapshot?
    private(set) var reviewed: IPAMEditValue?
    private(set) var working = false
    private(set) var requiresReload = false
    private(set) var saved = false
    private(set) var errorMessage: String?
    init(client: APIClient, kind: IPAMKind, id: Int, field: IPAMEditField) { self.client = client; self.kind = kind; self.id = id; self.field = field }
    func proposal() throws -> IPAMEditValue {
        let value: IPAMEditValue = field == .cidr ? .cidr(try IPAMCIDR(cidr, network: kind == .prefixes)) : field == .scope ? .scope(scope, reference) : .reference(reference)
        try value.validate(field: field, kind: kind); return value
    }
    var canReview: Bool {
        guard !working, !requiresReload, !saved, let snapshot, let before = try? snapshot.record.value(field, kind: kind), let after = try? proposal() else { return false }
        return !before.matches(after)
    }
    var validationMessage: String? { do { _ = try proposal(); return nil } catch { return readErrorMessage(error) } }
    func load() async {
        guard !working else { return }
        working = true; errorMessage = nil; reviewed = nil
        defer { working = false }
        do {
            let current = try await client.ipamEditSnapshot(kind: kind, id: id, field: field)
            try Task.checkCancellation()
            if snapshot == nil {
                switch try current.record.value(field, kind: kind) {
                case .reference(let value): reference = value
                case .scope(let type, let value): scope = type; reference = value
                case .cidr(let value): cidr = value.text
                }
            }
            snapshot = current; requiresReload = false
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func review() async {
        guard canReview, let snapshot else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { let value = try proposal(); try await client.checkIPAMEdit(snapshot, value: value); try Task.checkCancellation(); reviewed = value }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func save() async {
        guard canReview, let snapshot, let reviewed, let current = try? proposal(), current.matches(reviewed) else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do { self.snapshot = try await client.updateIPAM(snapshot, value: reviewed); saved = true }
        catch { requiresReload = true; errorMessage = readErrorMessage(error) }
    }
}

struct IPAMEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: IPAMEditModel
    @FocusState private var focused: Bool
    private enum Operation: Equatable { case load(UUID), review(UUID), save(UUID) }
    @State private var operation = Operation.load(UUID())
    init(client: APIClient, kind: IPAMKind, id: Int, field: IPAMEditField) { _model = State(initialValue: IPAMEditModel(client: client, kind: kind, id: id, field: field)) }
    private var scopeBinding: Binding<PrefixScope> { Binding(get: { model.scope }, set: { model.scope = $0; model.reference = nil }) }
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(model.snapshot?.record.object.title ?? "#\(String(model.id))").font(.headline).monospaced()
                    Text("#" + String(model.id)).font(.caption)
                    DetailField(title: "VRF", value: model.snapshot?.record.object.vrf?.text ?? L10n.text("Global"))
                }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if model.saved {
                    Label("Change saved", systemImage: "checkmark.circle").accessibilityIdentifier("ipamEditSaved")
                    Button("Done") { dismiss() }
                } else if let snapshot = model.snapshot {
                    if let reviewed = model.reviewed {
                        Section("Before") { Text((try? snapshot.record.value(model.field, kind: model.kind).display(for: model.field)) ?? "—") }
                        Section("After") { Text(reviewed.display(for: model.field)) }
                        Text(model.field.moving ? "Only this object's address or VRF changes. Related objects are never renumbered or moved." : "This changes only the selected field on the server.")
                        Button("Confirm change") { operation = .save(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("ipamEditConfirm")
                        Button("Back to editing") { model.back() }.disabled(model.working)
                    } else {
                        Section(model.field.title) {
                            if model.field == .cidr {
                                TextField("Address / prefix", text: $model.cidr).focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ipamCIDRDraft")
                            } else {
                                if model.field == .scope { Picker("Scope", selection: scopeBinding) { ForEach(PrefixScope.allCases) { Text(L10n.text($0.title)).tag($0) } }.accessibilityIdentifier("prefixScopeKind") }
                                if model.field != .scope || model.scope != .global {
                                    NavigationLink {
                                        ReferencePickerView(client: model.client, path: model.field == .scope ? model.scope.path : model.field.path, title: model.field == .scope ? model.scope.title : model.field.title, selection: $model.reference, emptyTitle: model.field == .vrf ? "Global" : "None", allowsEmpty: model.field != .scope)
                                    } label: {
                                        HStack { Text(model.field == .scope ? L10n.text(model.scope.title) : model.field.title); Spacer(); Text(model.reference?.title ?? L10n.text(model.field == .vrf ? "Global" : "None")).foregroundStyle(.secondary) }
                                    }.id(model.scope).accessibilityIdentifier("ipamEditReference")
                                }
                            }
                            if model.field.moving { Text("Address and VRF edits require no dependent objects. IP family changes are not supported here.").font(.caption) }
                            if let error = model.validationMessage { StatusMessage(message: error) }
                            Button("Review change") { focused = false; operation = .review(UUID()) }.disabled(!model.canReview).accessibilityIdentifier("ipamEditReview")
                        }.disabled(model.working)
                    }
                }
                if model.requiresReload {
                    Text("Reload before trying again. Your draft is kept. If the connection failed, check the current value: the change may already have been saved.")
                    Button("Reload current value") { operation = .load(UUID()) }.accessibilityIdentifier("ipamEditReload")
                } else if model.snapshot == nil && !model.working { Button("Retry") { operation = .load(UUID()) } }
                if model.working { ProgressView("Loading…") }
            }.navigationTitle(model.field.title).navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar {
                if focused { ToolbarItem(placement: .topBarLeading) { Button("Done") { focused = false } } }
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.disabled(model.working) }
            }.interactiveDismissDisabled(model.working)
            .task(id: operation) { switch operation { case .load: await model.load(); case .review: await model.review(); case .save: await model.save() } }
        }
    }
}
