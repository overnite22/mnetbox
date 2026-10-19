import SwiftUI

struct DetailField: View {
    @Environment(\.dynamicTypeSize) private var size
    let title: String
    let value: String
    var action: (() -> Void)? = nil
    var identifier = ""
    @ViewBuilder var body: some View {
        if let action {
            Button(action: action) {
                HStack {
                    contents
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.tint)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text(title)).accessibilityValue(value)
                .accessibilityIdentifier(identifier)
        } else { contents }
    }
    private var contents: some View {
        Group {
            if size.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(title))
                    Text(value).foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(L10n.text(title))
                    Spacer(minLength: 8)
                    Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
        }.padding(.vertical, 4)
            .accessibilityElement(children: .ignore).accessibilityLabel(L10n.text(title)).accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }
}
