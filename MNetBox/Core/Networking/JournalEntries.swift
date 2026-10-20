import Foundation

/// NetBox journal entries attached to one inventory object (devices, VMs, sites, racks).
struct JournalTarget: Sendable, Equatable {
    let kind: InventoryKind; let id: Int
    var objectType: String {
        switch kind {
        case .virtualMachines: "virtualization.virtualmachine"
        case .sites: "dcim.site"
        case .racks: "dcim.rack"
        default: "dcim.device"
        }
    }
    func validate() throws {
        guard id > 0, [.devices, .virtualMachines, .sites, .racks].contains(kind) else { throw APIError.invalidReference }
    }
}

struct JournalEntry: Codable, Sendable, Identifiable {
    struct Choice: Codable, Sendable { let value: String; let label: String? }
    let id: Int; let objectType: String; let objectID: Int
    let created: String?; let author: NetBoxLabel?; let kind: Choice; let comments: String
    enum CodingKeys: String, CodingKey { case id, created, kind, comments; case objectType = "assigned_object_type", objectID = "assigned_object_id", author = "created_by" }
    /// Day and time from NetBox's ISO-8601 timestamp, without guessing a time zone.
    var createdText: String {
        guard let created, created.count >= 16 else { return created ?? "—" }
        return String(created.prefix(10)) + " " + String(created.dropFirst(11).prefix(5))
    }
}

struct JournalDraft: Encodable, Sendable, Equatable {
    let target: JournalTarget; var kind = "info"; var comments = ""
    static let kinds = ["info", "success", "warning", "danger"]
    func validated() throws -> Self {
        try target.validate()
        var draft = self; draft.comments = EditableTextField.comments.normalized(comments)
        guard Self.kinds.contains(draft.kind) else { throw APIError.invalidStatus }
        guard !draft.comments.isEmpty else { throw APIError.requiredJournalText }
        try EditableTextField.comments.validate(draft.comments)
        return draft
    }
    enum Keys: String, CodingKey { case kind, comments; case objectType = "assigned_object_type", objectID = "assigned_object_id" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(target.objectType, forKey: .objectType); try c.encode(target.id, forKey: .objectID)
        try c.encode(kind, forKey: .kind); try c.encode(comments, forKey: .comments)
    }
    func matches(_ entry: JournalEntry) -> Bool {
        entry.id > 0 && entry.objectType == target.objectType && entry.objectID == target.id && entry.kind.value == kind && entry.comments == comments
    }
}
