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
