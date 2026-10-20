import Foundation

struct NetBoxLabel: Codable, Sendable {
    let id: Int?
    let display: String?
    let name: String?
    let label: String?
    let model: String?
    let address: String?
    let macAddress: String?
    enum CodingKeys: String, CodingKey { case id, display, name, label, model, address; case macAddress = "mac_address" }
    var text: String { display ?? name ?? model ?? address ?? macAddress ?? label ?? "—" }
}

// NetBox decimal fields may be serialized as JSON numbers or decimal strings.
struct NetBoxQuantity: Codable, Sendable {
    let text: String
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let string = try? value.decode(String.self) { text = string }
        else { text = NSDecimalNumber(decimal: try value.decode(Decimal.self)).stringValue }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(text)
    }
}

/// Custom field values rendered read-only. Empty values are skipped; unknown shapes are
/// summarized as text and never interpreted as references.
struct NetBoxCustomFields: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable, Identifiable {
        let key: String; let text: String
        var id: String { key }
        var title: String {
            let words = key.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }
    let entries: [Entry]
    private struct Key: CodingKey {
        let stringValue: String; var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private static func text(_ container: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        if let value = try? container.decode(String.self, forKey: key) { return value.isEmpty ? nil : value }
        if let value = try? container.decode(Bool.self, forKey: key) { return L10n.text(value ? "Yes" : "No") }
        if let value = try? container.decode(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decode(Double.self, forKey: key) { return String(value) }
        if let value = try? container.decode(NetBoxLabel.self, forKey: key) { return value.text }
        if let values = try? container.decode([String].self, forKey: key) { return values.isEmpty ? nil : values.joined(separator: ", ") }
        if let values = try? container.decode([NetBoxLabel].self, forKey: key) { return values.isEmpty ? nil : values.map(\.text).joined(separator: ", ") }
        return "…"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        entries = container.allKeys.sorted { $0.stringValue < $1.stringValue }.compactMap { key in
            Self.text(container, key).map { Entry(key: key.stringValue, text: $0) }
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for entry in entries { try container.encode(entry.text, forKey: Key(stringValue: entry.key)) }
    }
}
