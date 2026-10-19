import SwiftUI

struct NetBoxServerStatus: Decodable, Sendable {
    let version: String
    enum CodingKeys: String, CodingKey { case version = "netbox-version" }
}

struct TechnicalVersion: Equatable, Sendable {
    let value: String
    init?(_ input: String) {
        // Never place arbitrary server text in a support report. Only a bounded
        // numeric version and known prerelease suffix may cross this boundary.
        guard input.count <= 32, input.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }),
              input.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){1,2}((a|b|rc|dev)[0-9]{1,3})?$", options: .regularExpression) != nil else { return nil }
        value = input
    }
}

struct SupportReport: Sendable {
    static let reference = "4.7.2"
    let appVersion: String
    let build: String
    let osVersion: String
    let netBox: TechnicalVersion?
    var text: String {
        let version = TechnicalVersion(appVersion)?.value ?? "unknown"
        let safeBuild = !build.isEmpty && build.count <= 12 && build.utf8.allSatisfy({ (48...57).contains($0) }) ? build : "unknown"
        let system = TechnicalVersion(osVersion)?.value ?? "unknown"
        return "MNetBox \(version) (build \(safeBuild))\niOS \(system)\nNetBox \(netBox?.value ?? "unknown")\nReference NetBox \(Self.reference)\nCompatibility: \(netBox?.value == Self.reference ? "reference version" : "unverified")"
    }
}

struct AppInformationView: View {
    let client: APIClient?
    @State private var model: ReadDetailModel<TechnicalVersion>
    @State private var refresh = UUID()
    init(client: APIClient? = nil) {
        self.client = client
        _model = State(initialValue: ReadDetailModel(fetch: {
            guard let client else { throw APIError.invalidResponse }
            let status: NetBoxServerStatus = try await client.get("status/")
            guard let version = TechnicalVersion(status.version) else { throw APIError.invalidResponse }
            return version
        }))
    }
    private var report: SupportReport {
        SupportReport(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                      build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
                      osVersion: UIDevice.current.systemVersion, netBox: model.object)
    }
    var body: some View {
        List {
            Section("Application") {
                AppVersionLabel()
                DetailField(title: "iOS", value: UIDevice.current.systemVersion)
                Text("Native iPhone application. iOS 26 or later. French and English.")
            }
            Section("Compatibility") {
                DetailField(title: "Reference NetBox", value: SupportReport.reference)
                if client != nil {
                    if model.isLoading { ProgressView("Loading…") }
                    DetailField(title: "Server version", value: model.object?.value ?? "—", identifier: "netBoxServerVersion")
                    if let error = model.errorMessage {
                        StatusMessage(message: error)
                        if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let version = model.object {
                        Label(L10n.text(version.value == SupportReport.reference ? "Reference version" : "Version not yet verified"), systemImage: version.value == SupportReport.reference ? "checkmark.seal" : "info.circle")
                            .accessibilityIdentifier("serverCompatibility")
                    }
                    Button("Check server version") { refresh = UUID() }.disabled(model.isLoading).accessibilityIdentifier("checkServerVersion")
                }
                Text("The reference version is NetBox 4.7.2. Other versions require validation; this does not prevent browsing. Permissions and server constraints still apply.")
            }
            Section("Privacy and permissions") {
                Text("Your server and token stay in this device’s Keychain. Requests go to the HTTPS NetBox server you choose.")
                Text("MNetBox has no advertising, analytics or developer telemetry. NetBox may retain access logs and reviewed changes according to its own policy.")
                Text("Browsing needs read permissions. Changes need a write-enabled token and corresponding NetBox permissions.")
                Text("Changes are reviewed before confirmation. External synchronization can overwrite fields it manages.")
            }
            Section("Diagnostics") {
                Text(report.text).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("supportReport")
                ShareLink(item: report.text) { Label("Share diagnostics", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("shareDiagnostics")
                Text("This report contains only app, iOS and NetBox versions. It excludes tokens, server addresses, accounts and inventory.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App information")
        .task(id: refresh) { if client != nil { await model.reload() } }
    }
}
