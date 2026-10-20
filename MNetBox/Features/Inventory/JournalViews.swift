import SwiftUI

private func journalColor(_ kind: String) -> Color {
    switch kind { case "success": .green; case "warning": .orange; case "danger": .red; default: .blue }
}
private func journalSymbol(_ kind: String) -> String {
    switch kind { case "success": "checkmark.circle.fill"; case "warning": "exclamationmark.triangle.fill"; case "danger": "xmark.octagon.fill"; default: "info.circle.fill" }
}

struct JournalView: View {
    let client: APIClient; let target: JournalTarget; let title: String
    @State private var model: PaginatedListModel<JournalEntry, Int>
    @State private var refresh = UUID()
    @State private var more = 0
    @State private var adding = false
    init(client: APIClient, target: JournalTarget, title: String) {
        self.client = client; self.target = target; self.title = title
        _model = State(initialValue: PaginatedListModel(query: 0, fetch: { _, next in try await client.journalEntries(target, next: next) }))
    }
    var body: some View {
        List {
            Section { Label(title, systemImage: target.kind.symbol) }
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                Button("Retry") { if model.failedLoadingMore { more += 1 } else { refresh = UUID() } }
            }
            ForEach(model.objects) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(entry.kind.label ?? L10n.text(entry.kind.value.capitalized), systemImage: journalSymbol(entry.kind.value))
                            .font(.caption.bold()).foregroundStyle(journalColor(entry.kind.value))
                        Spacer()
                        Text(verbatim: entry.createdText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(entry.comments).textSelection(.enabled)
                    if let author = entry.author { Text(author.text).font(.caption).foregroundStyle(.secondary) }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("journalEntry-\(entry.id)")
            }
            if model.hasLoaded, model.objects.isEmpty, !model.isLoading { Text("No journal entries.").foregroundStyle(.secondary) }
            if model.hasLoaded { Text(L10n.format("%ld loaded · %ld total", model.objects.count, model.total)).font(.caption).foregroundStyle(.secondary) }
            if model.next != nil { Button("Load more") { more += 1 }.disabled(model.isLoadingMore).accessibilityIdentifier("journalLoadMore") }
        }
        .navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Add journal entry", systemImage: "plus") { adding = true }.accessibilityIdentifier("addJournalEntry")
            Button("Refresh", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(model.isLoading)
        }
        .sheet(isPresented: $adding, onDismiss: { refresh = UUID() }) { JournalEntryCreateView(client: client, target: target, title: title) }
        .task(id: refresh) { await model.reload(query: 0) }
        .task(id: more) { if more > 0 { await model.loadMore() } }
        .refreshable { await model.reload(query: 0) }
    }
}

@MainActor @Observable final class JournalEntryCreateModel {
    let client: APIClient
    var draft: JournalDraft
    private(set) var reviewed: JournalDraft?
    private(set) var created: JournalEntry?
    private(set) var working = false; private(set) var attempted = false
    private(set) var errorMessage: String?
    init(client: APIClient, target: JournalTarget) { self.client = client; draft = JournalDraft(target: target) }
    var plan: JournalDraft? { try? draft.validated() }
    func review() async {
        guard !working, !attempted, let plan else { return }
        working = true; errorMessage = nil; defer { working = false }
        do { try await client.checkJournalEntry(plan); try Task.checkCancellation(); reviewed = plan }
        catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    func back() { guard !working else { return }; reviewed = nil }
    func create() async {
        guard !working, !attempted, let reviewed else { return }
        attempted = true; working = true; errorMessage = nil; defer { working = false }
        do { created = try await client.createJournalEntry(reviewed) } catch { errorMessage = readErrorMessage(error) }
    }
}

struct JournalEntryCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: JournalEntryCreateModel
    let title: String
    private enum Operation: Equatable { case idle, review(UUID), create(UUID) }
    @State private var operation = Operation.idle
    init(client: APIClient, target: JournalTarget, title: String) {
        _model = State(initialValue: JournalEntryCreateModel(client: client, target: target)); self.title = title
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Target") {
                    Text(model.client.serverDisplay).font(.caption)
                    Text(title).font(.headline)
                    Text(verbatim: "#\(model.draft.target.id)").font(.caption)
                }
                if model.created != nil {
                    Section {
                        Label("Journal entry added", systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("journalEntryCreated")
                        Button("Done") { dismiss() }
                    }
                } else if let plan = model.reviewed {
                    Section("Journal entry review") {
                        Label(L10n.text(plan.kind.capitalized), systemImage: journalSymbol(plan.kind)).foregroundStyle(journalColor(plan.kind))
                        Text(plan.comments)
                    }
                    Section {
                        Text("This adds one journal entry in NetBox under your account. Existing entries are not changed.").font(.caption)
                        if !model.attempted {
                            Button("Confirm entry") { operation = .create(UUID()) }.accessibilityIdentifier("confirmJournalEntry")
                            Button("Back to editing") { model.back() }
                        }
                    }
                } else {
                    Section("Kind") {
                        Picker("Kind", selection: $model.draft.kind) {
                            ForEach(JournalDraft.kinds, id: \.self) { Label(L10n.text($0.capitalized), systemImage: journalSymbol($0)).tag($0) }
                        }.pickerStyle(.menu)
                    }
                    Section("Comments") {
                        TextEditor(text: $model.draft.comments).frame(minHeight: 160).accessibilityLabel(L10n.text("Comments")).accessibilityIdentifier("journalDraft")
                        Text("Plain text and Markdown are supported. Only surrounding whitespace is removed.").font(.caption)
                    }
                    Section { Button("Review entry") { operation = .review(UUID()) }.disabled(model.plan == nil || model.working).accessibilityIdentifier("reviewJournalEntry") }
                }
                if let error = model.errorMessage { Section { StatusMessage(message: error) } }
                if model.attempted && model.created == nil && !model.working {
                    Section { Text("The entry was not confirmed. Check the journal in NetBox before trying again; the request may have succeeded.").font(.callout) }
                }
                if model.working { ProgressView("Loading…") }
            }
            .disabled(model.working || (model.attempted && model.created == nil))
            .navigationTitle("Add journal entry").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel", role: .cancel) { dismiss() }.disabled(model.working) }
            .interactiveDismissDisabled(model.working)
            .task(id: operation) { switch operation { case .idle: break; case .review: await model.review(); case .create: await model.create() } }
        }
    }
}
