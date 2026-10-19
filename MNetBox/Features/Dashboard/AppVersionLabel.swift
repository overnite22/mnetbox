import SwiftUI

struct AppVersionLabel: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    var body: some View {
        Text(L10n.format("MNetBox %@ · Build %@", version, build))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.text("App version"))
            .accessibilityValue(L10n.format("MNetBox %@ · Build %@", version, build))
            .accessibilityIdentifier("appVersion")
    }
}
