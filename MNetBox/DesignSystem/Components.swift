import SwiftUI

enum Layout { static let spacing: CGFloat = 16; static let cornerRadius: CGFloat = 16 }

struct StatusMessage: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .foregroundStyle(.red)
            .accessibilityIdentifier("connectionError")
    }
}
