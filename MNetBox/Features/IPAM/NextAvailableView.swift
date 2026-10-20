import SwiftUI

/// A read-only suggestion handed to the reviewed creation form; nothing is allocated here.
struct IPAMCreationPrefill: Identifiable, Equatable {
    let kind: IPAMKind; let cidr: String
    var id: String { kind.rawValue + cidr }
}

enum NextAvailableMode: String, Identifiable {
    case ip, prefix
    var id: String { rawValue }
}

struct NextAvailableView: View {
    @Environment(\.dismiss) private var dismiss
    let client: APIClient; let prefixID: Int; let parent: IPAMCIDR; let vrf: NetBoxLabel?; let mode: NextAvailableMode
    let onUse: (IPAMCreationPrefill) -> Void
    @State private var length: Int
    @State private var suggestion: IPAMCIDR?
    @State private var searched = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var request = UUID()
    init(client: APIClient, prefixID: Int, parent: IPAMCIDR, vrf: NetBoxLabel?, mode: NextAvailableMode, onUse: @escaping (IPAMCreationPrefill) -> Void) {
        self.client = client; self.prefixID = prefixID; self.parent = parent; self.vrf = vrf; self.mode = mode; self.onUse = onUse
        let maximum = parent.bytes.count * 8
        _length = State(initialValue: min(maximum, max(parent.mask + 1, parent.family == 4 ? 24 : 64)))
    }
    private var maximum: Int { parent.bytes.count * 8 }
    private func load() async {
        working = true; errorMessage = nil; suggestion = nil; defer { working = false; searched = true }
        do {
            suggestion = mode == .ip
                ? try await client.nextAvailableIP(prefixID: prefixID, parent: parent, vrfID: vrf?.id)
                : try await client.nextAvailablePrefix(prefixID: prefixID, parent: parent, vrfID: vrf?.id, length: length)
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Parent prefix") {
                    Text(parent.text).font(.headline).monospaced()
                    Text(vrf?.text ?? L10n.text("Global VRF")).font(.caption)
                }
                if mode == .prefix, parent.mask < maximum {
                    Section("Size") {
                        Stepper(value: $length, in: (parent.mask + 1)...maximum) { Text(verbatim: "/\(length)").monospaced() }
                            .accessibilityIdentifier("nextPrefixLength")
                            .onChange(of: length) { suggestion = nil; searched = false }
                    }
                }
                Section {
                    if let error = errorMessage { StatusMessage(message: error) }
                    if let suggestion {
                        Text(suggestion.text).font(.title3.bold()).monospaced().accessibilityIdentifier("nextAvailableValue")
                        Text("Suggested by NetBox from the free space it reports now. It is not reserved: the creation review checks it again.").font(.caption)
                        Button("Use this value") {
                            onUse(IPAMCreationPrefill(kind: mode == .ip ? .ipAddresses : .prefixes, cidr: suggestion.text)); dismiss()
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("useNextAvailable")
                    } else if searched, errorMessage == nil {
                        Text(mode == .ip ? "No free address is visible in this prefix." : "No free block of this size is visible in this prefix.").accessibilityIdentifier("nextAvailableNone")
                    }
                    Button(searched ? "Search again" : "Find next available") { request = UUID() }.disabled(working).accessibilityIdentifier("findNextAvailable")
                    if working { ProgressView("Loading…") }
                }
            }
            .navigationTitle(mode == .ip ? "Next available IP" : "Next available prefix").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel", role: .cancel) { dismiss() } }
            .task(id: request) { await load() }
        }
    }
}
