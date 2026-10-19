import SwiftUI

@MainActor @Observable final class ConnectionModel {
    enum State { case disconnected, connecting, connected }
    private(set) var state: State = .disconnected
    private(set) var client: APIClient?
    var errorMessage: String?
    private let store: any CredentialStore
    private let makeClient: (Credential) -> APIClient
    private var operation: Task<Void, Never>?
    private var generation = UUID()

    init(store: (any CredentialStore)? = nil,
         makeClient: @escaping (Credential) -> APIClient = { APIClient(credential: $0) }) {
        self.store = store ?? KeychainCredentialStore()
        self.makeClient = makeClient
    }

    func restore() {
        guard state == .disconnected else { return }
        do {
            if let credential = try store.load() { connect(credential) }
        } catch { errorMessage = "Saved connection could not be opened. Unlock your device and retry." }
    }

    func connect(url: String, token: String, kind: TokenKind) {
        do { connect(Credential(configuration: try NetBoxConfiguration(url), token: token, kind: kind)) }
        catch { errorMessage = error.localizedDescription }
    }

    private func connect(_ credential: Credential) {
        operation?.cancel()
        generation = UUID()
        let current = generation
        state = .connecting
        errorMessage = nil
        operation = Task {
            let candidate = makeClient(credential)
            do {
                try await candidate.validateConnection()
                try Task.checkCancellation()
                guard generation == current else { await candidate.close(); return }
                try store.save(credential)
                client = candidate
                state = .connected
            } catch {
                await candidate.close()
                guard generation == current else { return }
                state = .disconnected
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    func disconnect() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        let old = client
        client = nil
        state = .disconnected
        Task { await old?.close() }
        do { try store.delete(); errorMessage = nil }
        catch { errorMessage = "Connection closed, but saved credentials could not be removed. Unlock your device and tap Forget saved connection again." }
    }
}
