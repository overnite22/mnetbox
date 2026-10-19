import SwiftUI

// Native vector illustrations remain sharp in both appearances and need no network assets.
struct InventoryIllustration: View {
    let kind: InventoryKind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.08))
            if kind == .racks || kind == .devices {
                VStack(spacing: 4) {
                    ForEach(0..<(kind == .racks ? 4 : 2), id: \.self) { _ in
                        HStack(spacing: 3) {
                            Circle().fill(.green).frame(width: 4, height: 4)
                            RoundedRectangle(cornerRadius: 1).fill(.secondary).frame(height: 3)
                            Image(systemName: "line.3.horizontal").font(.system(size: 8))
                        }.padding(5).background(.background, in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor.opacity(0.5)))
                    }
                }.padding(9)
            } else {
                Image(systemName: kind.symbol).resizable().scaledToFit().padding(12).foregroundStyle(Color.accentColor)
            }
        }.accessibilityHidden(true)
    }
}
