import SwiftUI

struct ContextGraphicHeader: View {
    let kind: ContextKind; let row: ContextRecord
    @Environment(\.dynamicTypeSize) private var size
    private var tint: Color { kind == .vrfs ? .indigo : kind == .tenants ? .teal : kind == .roles ? .orange : .blue }
    private var metrics: [(String, String, String)] {
        var values: [(String, String, String)] = []
        for (title, count, symbol) in [("Prefixes", row.prefixCount, "square.stack.3d.up.fill"), ("IP addresses", row.ipCount, "network"), ("VLANs", row.vlanCount, "square.stack.3d.up"), ("Devices", row.deviceCount, "server.rack"), ("Virtual machines", row.vmCount, "desktopcomputer")] {
            if let count, count >= 0 { values.append((title, String(count), symbol)) }
        }
        return values
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: kind.symbol).font(.system(size: 36, weight: .semibold)).foregroundStyle(tint).frame(width: 72, height: 72).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.title).font(.title2.bold()).accessibilityIdentifier("contextGraphicTitle")
                    Text(kind.title + " · #\(row.id)").font(.caption).foregroundStyle(.secondary)
                    if let rd = row.rd { Label(rd, systemImage: "point.3.filled.connected.trianglepath.dotted").font(.callout.monospaced()).foregroundStyle(tint) }
                    if let tenant = row.tenant ?? row.group { Label(tenant.text, systemImage: "person.2.fill").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !metrics.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: size.isAccessibilitySize ? 1 : 2), spacing: 10) {
                    ForEach(metrics, id: \.0) { title, value, symbol in
                        HStack { Image(systemName: symbol).foregroundStyle(tint); VStack(alignment: .leading) { Text(value).font(.title3.bold()).monospacedDigit(); Text(L10n.text(title)).font(.caption).foregroundStyle(.secondary) } }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
    }
}

struct InventoryGraphicHeader: View {
    let kind: InventoryKind; let object: InventoryObject
    private var color: Color { kind == .devices ? .blue : kind == .racks ? .orange : kind == .sites ? .teal : .purple }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: kind.symbol).font(.system(size: 38, weight: .semibold)).foregroundStyle(color).frame(width: 74, height: 74).background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 8) {
                Text(object.title).font(.title2.bold())
                if let status = object.status { Label(status.text, systemImage: "circle.fill").font(.caption.bold()).foregroundStyle(color) }
                if let parent = object.site ?? object.cluster { Label(parent.text, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
                if let type = object.deviceType { Text(type.text).font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 8).accessibilityElement(children: .contain)
    }
}
