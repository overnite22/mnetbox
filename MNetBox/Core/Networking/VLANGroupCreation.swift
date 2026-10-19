import Foundation

enum VLANGroupScope: String, CaseIterable, Identifiable, Sendable {
    case global = "", region = "dcim.region", siteGroup = "dcim.sitegroup", site = "dcim.site", location = "dcim.location"
    case rackGroup = "dcim.rackgroup", rack = "dcim.rack", clusterGroup = "virtualization.clustergroup", cluster = "virtualization.cluster"
    var id: String { rawValue }
    var title: String { switch self {
    case .global: "Global"; case .region: "Region"; case .siteGroup: "Site group"; case .site: "Site"
    case .location: "Location"; case .rackGroup: "Rack group"; case .rack: "Rack"; case .clusterGroup: "Cluster group"; case .cluster: "Cluster"
    } }
    var path: String { switch self {
    case .global: ""; case .region: "dcim/regions/"; case .siteGroup: "dcim/site-groups/"; case .site: "dcim/sites/"
    case .location: "dcim/locations/"; case .rackGroup: "dcim/rack-groups/"; case .rack: "dcim/racks/"
    case .clusterGroup: "virtualization/cluster-groups/"; case .cluster: "virtualization/clusters/"
    } }
}

struct VLANGroupCreationPlan: Encodable, Sendable {
    let name: String
    let slug: String
    let scope: VLANGroupScope
    let reference: ReferenceSelection?
    let ranges: [[Int]]
    let tenant: ReferenceSelection?
    let description: String
    let comments: String
    static func parseRanges(_ input: String) throws -> [[Int]] {
        let parts = input.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...100).contains(parts.count) else { throw APIError.invalidVID }
        let ranges = try parts.map { part -> [Int] in
            let bounds = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count) else { throw APIError.invalidVID }
            let values = try bounds.map { text -> Int in
                guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text), (1...4094).contains(value) else { throw APIError.invalidVID }
                return value
            }
            return [values[0], values.last ?? values[0]]
        }.sorted { $0[0] < $1[0] }
        try validateRanges(ranges); return ranges
    }
    static func validateRanges(_ ranges: [[Int]]) throws {
        guard (1...100).contains(ranges.count), ranges.allSatisfy({ $0.count == 2 && (1...4094).contains($0[0]) && ($0[0]...4094).contains($0[1]) }) else { throw APIError.invalidVID }
        let sorted = ranges.sorted { $0[0] < $1[0] }
        for i in sorted.indices.dropFirst() { guard sorted[i][0] > sorted[i - 1][1] else { throw APIError.invalidVID } }
    }
    func validate() throws {
        try EditableTextField.name.validate(name, for: .vlanGroups)
        guard name == EditableTextField.name.normalized(name), !slug.isEmpty, slug.utf8.count <= 100,
              slug.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw APIError.invalidName }
        guard scope == .global ? reference == nil : (reference?.id ?? 0) > 0, (tenant?.id ?? 1) > 0 else { throw APIError.invalidReference }
        try Self.validateRanges(ranges)
        try EditableTextField.description.validate(description); try EditableTextField.comments.validate(comments)
    }
    enum CodingKeys: String, CodingKey { case name, slug, tenant, description, comments; case type = "scope_type", id = "scope_id", ranges = "vid_ranges" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(slug, forKey: .slug)
        try c.encode(scope == .global ? nil : scope.rawValue, forKey: .type); try c.encode(reference?.id, forKey: .id)
        try c.encode(ranges, forKey: .ranges); try c.encode(tenant?.id, forKey: .tenant)
        try c.encode(description, forKey: .description); try c.encode(comments, forKey: .comments)
    }
    func matchesScope(_ row: VLANBrowseRecord) -> Bool {
        Set(["scope_type", "scope_id", "scope"]).isSubset(of: row.knownFields)
            && row.scopeType == (scope == .global ? nil : scope.rawValue) && row.scopeID == reference?.id && row.scope?.id == reference?.id
    }
    func matches(_ row: VLANBrowseRecord) -> Bool {
        matchesScope(row) && row.name == name && row.slug == slug && row.vidRanges == ranges && row.knownFields.contains("tenant")
            && row.tenant?.id == tenant?.id && row.description == description && row.comments == comments
    }
}
