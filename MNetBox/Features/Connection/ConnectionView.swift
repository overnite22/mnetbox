import SwiftUI

struct ConnectionView: View {
    @Bindable var model: ConnectionModel
    @State private var url = ""
    @State private var token = ""
    @State private var kind: TokenKind = .legacy

    var body: some View {
        NavigationStack {
            Form {
                Section("NetBox server") {
                    TextField("HTTPS URL", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("serverURL")
                    SecureField("API token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("apiToken")
                    Picker("Token format", selection: $kind) {
                        ForEach(TokenKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    if model.state == .connecting {
                        ProgressView("Checking connection…")
                        Button("Cancel", role: .cancel) { model.disconnect() }
                    } else {
                        Button("Connect") { model.connect(url: url, token: token, kind: kind); token = "" }
                            .disabled(token.isEmpty).accessibilityIdentifier("connect")
                        Button("Retry saved connection") { model.restore() }
                        Button("Forget saved connection", role: .destructive) { model.disconnect() }
                    }
                } footer: {
                    Text("Your token is stored in this device’s Keychain. Browsing needs read permissions; changes need a write-enabled token and corresponding NetBox permissions.")
                }
                Section("Getting started") {
                    Text("Enter your own HTTPS NetBox URL, then select your token format. NetBox v1 uses Token; v2 uses Bearer.")
                    Text("Start with read permissions. Enable writes only for the objects you intend to change.")
                    NavigationLink { AppInformationView() } label: { Label("App information", systemImage: "info.circle") }.accessibilityIdentifier("appInformation")
                }
                if let message = model.errorMessage { Section { StatusMessage(message: message) } }
            }
            .navigationTitle("Connect to NetBox")
        }
    }
}
