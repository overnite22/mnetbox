#if DEBUG
import Foundation

// In-memory only. Intercepts synthetic edits before the read-only fixtures.
final class FixtureDescriptions: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String: Any]] = [:]
    func response(_ request: URLRequest) -> (Int, String)? {
        guard let url = request.url, let id = Int(url.lastPathComponent), id > 0 else { return nil }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
        let textCollection = TextEditTarget.Collection.allCases.first { path == "/api/" + $0.rawValue + "\(id)/" }
        let structuredCollection = StructuredEditTarget.Collection.allCases.first { path == "/api/" + $0.rawValue + "\(id)/" }
        guard textCollection != nil || structuredCollection != nil else { return nil }
        lock.lock(); defer { lock.unlock() }
        if request.httpMethod == "PATCH" {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-edit-conflict") { return (412, "{}") }
            guard request.value(forHTTPHeaderField: "If-Match") == "W/\"fixture-1\"",
                  let data = requestBody(request),
                  let patch = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], (patch.count == 1 || (patch.count == 2 && Set(patch.keys) == ["assigned_object_type", "assigned_object_id"]) || (patch.count == 3 && Set(patch.keys) == ["mode", "untagged_vlan", "tagged_vlans"])),
                  let entry = patch.first,
                  let original = InventoryFixture.response(url) ?? IPAMFixture.response(url) ?? ComponentFixture.response(url) ?? CableBrowseFixture.response(url), original.0 == 200,
                  let originalData = original.1.data(using: .utf8),
                  var object = values[url.path] ?? (try? JSONSerialization.jsonObject(with: originalData) as? [String: Any]) else { return (400, "{}") }
            if patch.count == 3, structuredCollection?.isInterface == true {
                guard let mode = patch["mode"] as? String, VLANMode(rawValue: mode) != nil, let tagged = patch["tagged_vlans"] as? [Int] else { return (400, "{}") }
                func vlan(_ id: Int) -> [String: Any]? {
                    guard let refURL = URL(string: "https://example.test/api/ipam/vlans/\(id)/"), let reply = ComponentFixture.response(refURL), reply.0 == 200 else { return nil }
                    return (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any]
                }
                let untagged: [String: Any]?
                if patch["untagged_vlan"] is NSNull { untagged = nil }
                else if let id = patch["untagged_vlan"] as? Int, let ref = vlan(id) { untagged = ref }
                else { return (400, "{}") }
                let refs = tagged.compactMap(vlan)
                guard refs.count == tagged.count else { return (400, "{}") }
                object["mode"] = mode.isEmpty ? NSNull() : ["value": mode, "label": VLANMode(rawValue: mode)?.title ?? mode] as Any
                object["untagged_vlan"] = untagged ?? NSNull() as Any
                object["tagged_vlans"] = refs
            } else if patch.count == 2, structuredCollection == .ipAddresses {
                if patch["assigned_object_type"] is NSNull && patch["assigned_object_id"] is NSNull {
                    object["assigned_object_type"] = NSNull(); object["assigned_object_id"] = NSNull(); object["assigned_object"] = NSNull()
                } else {
                    guard let type = patch["assigned_object_type"] as? String, let kind = InterfaceKind(rawValue: type),
                          let identifier = patch["assigned_object_id"] as? Int, identifier > 0,
                          let refURL = URL(string: "https://example.test/api/" + kind.path + "\(identifier)/"),
                          let reply = ComponentFixture.response(refURL) ?? IPAMFixture.response(refURL), reply.0 == 200,
                          let reference = (try? JSONSerialization.jsonObject(with: Data(reply.1.utf8))) as? [String: Any] else { return (400, "{}") }
                    object["assigned_object_type"] = type; object["assigned_object_id"] = identifier; object["assigned_object"] = reference
                }
            } else if let field = EditableTextField(rawValue: entry.key), let collection = textCollection, field.supports(collection) {
                let value: String
                if (field == .name || field.clearsWithNull), entry.value is NSNull { value = "" }
                else if let text = entry.value as? String { value = field.normalized(text) }
                else { return (400, "{}") }
                guard (try? field.validate(value, for: collection)) != nil else { return (400, "{}") }
                if field == .status || field == .lengthUnit { object[field.rawValue] = value.isEmpty && field.clearsWithNull ? NSNull() : ["value": value, "label": value.capitalized] as Any }
                else if field == .name {
                    object["name"] = value.isEmpty ? NSNull() : value as Any
                    object["display"] = value.isEmpty ? "Unnamed device" : value
                } else { object[field.rawValue] = value.isEmpty && field.clearsWithNull ? NSNull() : value as Any }
            } else if let field = StructuredEditField(rawValue: entry.key), let collection = structuredCollection, field.supports(collection) {
                if field.isText, let value = entry.value as? String {
                    guard (try? StructuredEditValue.text(value).validate(field: field, target: StructuredEditTarget(collection: collection, id: id, parentID: 301))) != nil else { return (400, "{}") }
                    object[entry.key] = value
                    if field == .name { object["display"] = value }
                } else if field == .type, let value = entry.value as? String, InterfaceTypeOptions.values.contains(value) {
                    object["type"] = ["value": value, "label": InterfaceTypeOptions.title(value)]
                } else if field == .status, let value = entry.value as? String, field.statuses(collection).contains(value) {
                    object["status"] = ["value": value, "label": value.capitalized]
                } else if field.isReference {
                    if entry.value is NSNull {
                        guard field.allowsEmpty(collection) else { return (400, "{}") }
                        object[entry.key] = NSNull()
                    } else {
                        guard let referenceID = entry.value as? Int, referenceID > 0,
                              let refURL = URL(string: "https://example.test/api/" + field.referencePath + "\(referenceID)/"),
                              let reply = ComponentFixture.response(refURL) ?? IPAMFixture.response(refURL), reply.0 == 200,
                              let refData = reply.1.data(using: .utf8),
                              let reference = (try? JSONSerialization.jsonObject(with: refData)) as? [String: Any],
                              field != .role || collection != .virtualMachines || reference["vm_role"] as? Bool == true else { return (400, "{}") }
                        object[entry.key] = reference
                    }
                } else if field == .mtu {
                    if entry.value is NSNull { object[entry.key] = NSNull() }
                    else if let mtu = entry.value as? Int, (1...65536).contains(mtu) { object[entry.key] = mtu }
                    else { return (400, "{}") }
                } else if let enabled = entry.value as? Bool { object[entry.key] = enabled }
                else { return (400, "{}") }
            } else { return (400, "{}") }
            values[url.path] = object
        }
        guard let object = values[url.path], let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return (200, text)
    }
}

func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { return nil }; if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
#endif
