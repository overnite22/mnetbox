import Foundation

enum TokenKind: String, Codable, CaseIterable, Sendable {
    case legacy, bearer
    var title: String { L10n.text(self == .legacy ? "Legacy (Token)" : "v2 (Bearer)") }
}

struct Credential: Codable, Sendable {
    let configuration: NetBoxConfiguration
    let token: String
    let kind: TokenKind
}

struct RequestBuilder: Sendable {
    let credential: Credential

    func get(_ path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        let token = credential.token
        guard !token.isEmpty, token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw APIError.invalidToken
        }
        let url = try credential.configuration.validatedURL(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = (components.queryItems ?? []) + query }
        guard let finalURL = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(credential.kind == .legacy ? "Token" : "Bearer") \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return request
    }
}

// Refuse redirects so authorization is never forwarded to an unvalidated destination.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor APIClient {
    nonisolated let serverDisplay: String
    private let builder: RequestBuilder
    private let session: URLSession
    private var etags: [URL: String] = [:]

    init(credential: Credential, session: URLSession? = nil) {
        serverDisplay = credential.configuration.baseURL.absoluteString
        builder = RequestBuilder(credential: credential)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let request = try builder.get(path, query: query)
        let (object, tag): (T, String?) = try await send(request)
        if let url = request.url { etags[url] = tag }
        return object
    }

    private func transfer(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIError.transport
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 409, 412: throw APIError.conflict
        default:
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let fields = object.mapValues { value -> [String] in
                if let strings = value as? [String] { return strings }
                if let string = value as? String { return [string] }
                return ["Invalid value"]
            }
            throw APIError.http(http.statusCode, fields)
        }
        return (data, http)
    }
    private func send<T: Decodable & Sendable>(_ request: URLRequest) async throws -> (T, String?) {
        let (data, http) = try await transfer(request)
        guard http.mimeType == "application/json" else { throw APIError.invalidResponse }
        let decoded: T
        do { decoded = try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding }
        return (decoded, http.value(forHTTPHeaderField: "ETag"))
    }

    // NetBox 4.7.2 deliberately compares weak timestamp ETags under a row lock.
    // Keep this version paired with its decoded object, separate from the GET cache.
    func textSnapshot(for target: TextEditTarget, field: EditableTextField = .description) async throws -> TextEditSnapshot {
        guard field.supports(target.collection) else { throw APIError.invalidURL }
        let request = try builder.get(target.path)
        let (object, tag): (TextEditObject, String?) = try await send(request)
        guard object.id == target.id, object.value(for: field) != nil else { throw APIError.invalidResponse }
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return TextEditSnapshot(target: target, object: object, etag: tag, field: field)
    }

    func updateText(_ snapshot: TextEditSnapshot, to value: String) async throws -> TextEditSnapshot {
        guard TextEditSnapshot.validETag(snapshot.etag) else { throw APIError.missingETag }
        guard snapshot.field.supports(snapshot.target.collection), snapshot.object.id == snapshot.target.id,
              snapshot.object.value(for: snapshot.field) != nil else { throw APIError.invalidURL }
        // Normalize before both transmission and response verification, especially lowercase DNS names.
        let proposed = snapshot.field.normalized(value)
        try snapshot.field.validate(proposed, for: snapshot.target.collection)
        var request = try builder.get(snapshot.target.path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(TextEditPayload(field: snapshot.field, value: proposed))
        // Never retry a mutation: a lost response does not establish whether it was applied.
        let (object, tag): (TextEditObject, String?) = try await send(request)
        guard object.id == snapshot.target.id, object.value(for: snapshot.field) == proposed else { throw APIError.invalidResponse }
        return TextEditSnapshot(target: snapshot.target, object: object, etag: tag ?? "", field: snapshot.field)
    }

    func ipamEditSnapshot(kind: IPAMKind, id: Int, field: IPAMEditField) async throws -> IPAMEditSnapshot {
        guard id > 0, field.supports(kind) else { throw APIError.invalidURL }
        let (record, tag): (IPAMEditRecord, String?) = try await send(builder.get(kind.path + "\(id)/"))
        try record.validate(kind: kind, id: id)
        _ = try record.value(field, kind: kind)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return .init(kind: kind, id: id, field: field, record: record, etag: tag)
    }

    func checkIPAMEdit(_ snapshot: IPAMEditSnapshot, value: IPAMEditValue) async throws {
        try value.validate(field: snapshot.field, kind: snapshot.kind)
        if case .reference(let reference) = value, let reference {
            if snapshot.field == .vlan {
                _ = try await VLANBrowseService(client: self, kind: .vlans).detail(id: reference.id)
            } else {
                let object: EditReference = try await get(snapshot.field.path + "\(reference.id)/")
                guard object.id == reference.id else { throw APIError.invalidReference }
            }
        }
        if case .scope(let type, let reference) = value, let reference {
            let object: EditReference = try await get(type.path + "\(reference.id)/")
            guard object.id == reference.id else { throw APIError.invalidReference }
        }
        guard snapshot.field.moving else { return }
        let before = try IPAMCIDR(snapshot.record.object.title, network: snapshot.kind == .prefixes)
        let deletion = try await deletionSnapshot(.init(collection: snapshot.kind == .prefixes ? .prefixes : .ipAddresses, id: snapshot.id))
        guard deletion.etag == snapshot.etag, deletion.object.cidr == before,
              deletion.object.vrf?.id == snapshot.record.object.vrf?.id else { throw APIError.conflict }
        guard deletion.blockers.isEmpty else { throw APIError.ipamMoveBlocked }
        let cidr: IPAMCIDR
        if case .cidr(let proposed) = value { cidr = proposed } else { cidr = before }
        // Family changes are deliberately separate from address/VRF editing.
        guard cidr.family == before.family else { throw APIError.invalidCIDR }
        let vrf: Int?
        if snapshot.field == .vrf, case .reference(let ref) = value { vrf = ref?.id } else { vrf = snapshot.record.object.vrf?.id }
        let vrfItem = URLQueryItem(name: "vrf_id", value: vrf.map(String.init) ?? "null")
        let items = [vrfItem, URLQueryItem(name: snapshot.kind == .prefixes ? "prefix" : "address", value: snapshot.kind == .prefixes ? cidr.text : cidr.host), .init(name: "ordering", value: "id"), .init(name: "limit", value: "50")]
        var next: String?; var seen = Set<String>(); var ids = Set<Int>(); var total: Int?
        var finished = false
        for _ in 0..<100 {
            try CollectionLinks.validate(next, path: snapshot.kind.path, required: items)
            let page: IPAMEditPage = try await get(next ?? snapshot.kind.path, query: next == nil ? items : [])
            guard page.count >= 0, page.results.count <= 50, total == nil || total == page.count else { throw APIError.invalidResponse }
            total = page.count
            for row in page.results {
                try row.validate(kind: snapshot.kind, id: row.object.id)
                let parsed = try IPAMCIDR(row.object.title, network: snapshot.kind == .prefixes)
                guard row.object.vrf?.id == vrf, parsed.family == cidr.family,
                      snapshot.kind == .prefixes ? parsed == cidr : parsed.bytes == cidr.bytes,
                      ids.insert(row.object.id).inserted else { throw APIError.invalidResponse }
                if row.object.id != snapshot.id { throw APIError.duplicateIPAM }
            }
            guard ids.count <= page.count else { throw APIError.invalidResponse }
            guard let link = page.next else {
                guard ids.count == page.count else { throw APIError.invalidResponse }
                finished = true; break
            }
            guard !page.results.isEmpty, seen.insert(link).inserted else { throw APIError.invalidResponse }; next = link
        }
        guard finished else { throw APIError.invalidResponse }
        if snapshot.kind == .prefixes {
            // Check the destination too: expanding/moving an empty prefix must not
            // silently acquire existing children, addresses or ranges in its new VRF.
            let children: IPAMEditPage = try await get("ipam/prefixes/", query: [.init(name: "within", value: cidr.text), vrfItem, .init(name: "limit", value: "2")])
            guard children.count >= children.results.count, children.results.count <= 2,
                  children.count == 0 ? children.results.isEmpty && children.next == nil : !children.results.isEmpty else { throw APIError.invalidResponse }
            guard children.count <= 1, children.results.allSatisfy({ $0.object.id == snapshot.id && $0.object.vrf?.id == vrf }) else { throw APIError.ipamMoveBlocked }
            if children.count == 1 { guard children.next == nil else { throw APIError.invalidResponse } }
            for (path, filter) in [("ipam/ip-addresses/", "parent"), ("ipam/ip-ranges/", "parent")] {
                guard try await deletionDependencyCount(path, [.init(name: filter, value: cidr.text), vrfItem]) == 0 else { throw APIError.ipamMoveBlocked }
            }
        }
    }

    func updateIPAM(_ snapshot: IPAMEditSnapshot, value: IPAMEditValue) async throws -> IPAMEditSnapshot {
        try snapshot.record.validate(kind: snapshot.kind, id: snapshot.id)
        guard TextEditSnapshot.validETag(snapshot.etag) else { throw APIError.missingETag }
        let fresh = try await ipamEditSnapshot(kind: snapshot.kind, id: snapshot.id, field: snapshot.field)
        guard fresh.etag == snapshot.etag, fresh.record.preserved(comparedTo: snapshot.record, field: .cidr),
              fresh.record.object.title == snapshot.record.object.title,
              try fresh.record.value(snapshot.field, kind: snapshot.kind).matches(snapshot.record.value(snapshot.field, kind: snapshot.kind)) else { throw APIError.conflict }
        try await checkIPAMEdit(fresh, value: value)
        try Task.checkCancellation()
        var request = try builder.get(snapshot.kind.path + "\(snapshot.id)/")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(IPAMEditPayload(kind: snapshot.kind, field: snapshot.field, value: value))
        let (reply, tag): (IPAMEditRecord, String?) = try await send(request)
        try reply.validate(kind: snapshot.kind, id: snapshot.id)
        guard !snapshot.field.moving || reply.dependencies.blockers.isEmpty else { throw APIError.invalidResponse }
        guard reply.preserved(comparedTo: fresh.record, field: snapshot.field), try reply.value(snapshot.field, kind: snapshot.kind).matches(value) else { throw APIError.invalidResponse }
        return .init(kind: snapshot.kind, id: snapshot.id, field: snapshot.field, record: reply, etag: tag ?? "")
    }

    func structuredSnapshot(target: StructuredEditTarget, field: StructuredEditField) async throws -> StructuredEditSnapshot {
        guard field.supports(target.collection) else { throw APIError.invalidURL }
        let (object, tag): (StructuredEditObject, String?) = try await send(builder.get(target.path))
        try object.validate(target: target, field: field)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return StructuredEditSnapshot(target: target, field: field, object: object, etag: tag)
    }

    func checkStructuredReference(_ value: StructuredEditValue, target: StructuredEditTarget, field: StructuredEditField) async throws {
        try value.validate(field: field, target: target)
        if case .reference(let selected) = value, let selected {
            if field == .primaryIP4 || field == .primaryIP6 {
                let ip: IPAMObject = try await get("ipam/ip-addresses/\(selected.id)/")
                guard ip.id == selected.id, let address = ip.address, let cidr = try? IPAMCIDR(address, network: false),
                      cidr.family == (field == .primaryIP4 ? 4 : 6), let (kind, id) = ip.interfaceAssignment,
                      kind == (target.collection == .devices ? .physical : .virtual) else { throw APIError.invalidReference }
                let service = InterfaceService(client: self, kind: kind, parentID: target.id)
                let interface = try await service.detail(id: id)
                guard service.parent(interface)?.id == target.id else { throw APIError.invalidReference }
                return
            }
            if field == .primaryMAC {
                let mac = try await MACService(client: self).detail(id: selected.id)
                let kind: InterfaceKind = target.collection == .physicalInterfaces ? .physical : .virtual
                guard mac.assignment?.0 == kind, mac.assignment?.1 == target.id else { throw APIError.invalidReference }
                return
            }
            let referencePath = target.collection == .vlans && field == .role ? "ipam/roles/" : field.referencePath
            let object: EditReference = try await get(referencePath + "\(selected.id)/")
            guard object.id == selected.id,
                  field != .role || target.collection != .virtualMachines || object.vmRole == true else { throw APIError.invalidReference }
        }
        if case .assignment(let selected) = value {
            if let selected {
            guard let parent = selected.parentID, parent > 0 else { throw APIError.invalidReference }
            let service = InterfaceService(client: self, kind: selected.kind, parentID: parent)
            let interface = try await service.detail(id: selected.id)
            guard service.parent(interface)?.id == parent else { throw APIError.invalidReference }
            }
            if target.collection == .macAddresses { try await checkMACAssignment(target: target, selected: selected) }
            else { try await checkAssignmentParent(target: target, selected: selected) }
        }
    }

    private func checkAssignmentParent(target: StructuredEditTarget, selected: InterfaceSelection?) async throws {
        let current = try await structuredSnapshot(target: target, field: .assignment)
        guard case .assignment(let original) = current.object.value(.assignment), let original else { return }
        let service = InterfaceService(client: self, kind: original.kind)
        let interface = try await service.detail(id: original.id)
        guard let parentID = service.parent(interface)?.id, parentID > 0 else { throw APIError.invalidResponse }
        // Moving between interfaces on the same parent retains its primary designation.
        if selected?.kind == original.kind, selected?.parentID == parentID { return }
        let path = original.kind == .physical ? "dcim/devices/" : "virtualization/virtual-machines/"
        let parent: AssignmentParent = try await get(path + "\(parentID)/")
        try parent.validate(id: parentID, physical: original.kind == .physical)
        if parent.primaryIP4?.id == target.id || parent.primaryIP6?.id == target.id { throw APIError.assignmentPrimaryBlocked }
        if parent.oobIP?.id == target.id { throw APIError.assignmentOOBBlocked }
    }

    func updateStructured(_ snapshot: StructuredEditSnapshot, to value: StructuredEditValue) async throws -> StructuredEditSnapshot {
        try snapshot.object.validate(target: snapshot.target, field: snapshot.field)
        guard TextEditSnapshot.validETag(snapshot.etag) else { throw APIError.missingETag }
        let fresh = try await structuredSnapshot(target: snapshot.target, field: snapshot.field)
        guard fresh.etag == snapshot.etag, fresh.object.value(snapshot.field)?.matches(snapshot.object.value(snapshot.field) ?? value) == true else { throw APIError.conflict }
        try await checkStructuredReference(value, target: snapshot.target, field: snapshot.field)
        var request = try builder.get(snapshot.target.path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(StructuredEditPayload(field: snapshot.field, value: value))
        let object: StructuredEditObject
        let tag: String?
        do { (object, tag) = try await send(request) }
        catch APIError.http(400, let fields) where snapshot.field == .assignment {
            let reasons = fields["non_field_errors"] ?? []
            if snapshot.target.collection == .macAddresses {
                if reasons.contains(where: { $0.contains("primary MAC") }) { throw APIError.primaryMACBlocked }
                throw APIError.macAssignmentRejected
            }
            if reasons.contains(where: { $0.contains("designated as the primary IP") }) { throw APIError.assignmentPrimaryBlocked }
            if reasons.contains(where: { $0.contains("designated as the OOB IP") }) { throw APIError.assignmentOOBBlocked }
            throw APIError.assignmentRejected
        }
        try object.validate(target: snapshot.target, field: snapshot.field)
        guard object.value(snapshot.field)?.matches(value) == true else { throw APIError.invalidResponse }
        return StructuredEditSnapshot(target: snapshot.target, field: snapshot.field, object: object, etag: tag ?? "")
    }

    private func checkMACAssignment(target: StructuredEditTarget, selected: InterfaceSelection?) async throws {
        let mac = try await MACService(client: self).detail(id: target.id)
        if selected?.kind == mac.assignment?.0, selected?.id == mac.assignment?.1 { return }
        if mac.isPrimary { throw APIError.primaryMACBlocked }
        if let (kind, id) = mac.assignment {
            let current = try await structuredSnapshot(target: StructuredEditTarget(collection: kind == .physical ? .physicalInterfaces : .virtualInterfaces, id: id, parentID: try await macInterfaceParent(kind: kind, id: id)), field: .primaryMAC)
            if case .reference(let reference) = current.object.value(.primaryMAC), reference?.id == target.id { throw APIError.primaryMACBlocked }
        }
    }

    private func macInterfaceParent(kind: InterfaceKind, id: Int) async throws -> Int {
        let service = InterfaceService(client: self, kind: kind)
        let object = try await service.detail(id: id)
        guard let parent = service.parent(object)?.id, parent > 0 else { throw APIError.invalidReference }
        return parent
    }

    func imageLoader() -> NetBoxImageLoader {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.httpShouldSetCookies = false
        // Preserve only protocol injection for synthetic tests, never API headers/cookies.
        config.protocolClasses = session.configuration.protocolClasses
        return NetBoxImageLoader(apiURL: builder.credential.configuration.baseURL, credential: builder.credential, session: URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil))
    }
    func imageUploadTargetTitle(_ target: ImageUploadTarget) async throws -> String {
        try target.validate()
        let object = try await InventoryService(client: self, kind: target.kind).detail(id: target.id)
        guard !object.title.isEmpty else { throw APIError.invalidResponse }
        return object.title
    }
    func uploadImage(_ plan: ImageUploadPlan) async throws -> ImageUploadReply {
        try plan.validate()
        guard try await imageUploadTargetTitle(plan.target) == plan.targetTitle else { throw APIError.conflict }
        try Task.checkCancellation()
        let boundary = "MNetBox-" + UUID().uuidString
        var request = try builder.get("extras/image-attachments/")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try plan.multipart(boundary: boundary)
        let (data, response) = try await transfer(request)
        guard response.statusCode == 201 else { throw APIError.invalidResponse }
        let reply: ImageUploadReply
        do { reply = try JSONDecoder().decode(ImageUploadReply.self, from: data) } catch { throw APIError.invalidResponse }
        try reply.validate(plan, apiURL: builder.credential.configuration.baseURL)
        return reply
    }
    func cableTrace(interfaceID: Int) async throws -> CableTrace {
        return try await cableTrace(id: interfaceID, portKind: nil)
    }
    func cableTrace(id: Int, portKind: DevicePortKind?) async throws -> CableTrace {
        guard id > 0, portKind?.traceable != false else { throw APIError.invalidURL }
        let path = portKind?.path ?? "dcim/interfaces/"
        var trace: CableTrace = try await get(path + "\(id)/trace/")
        try trace.validate(apiURL: builder.credential.configuration.baseURL, interfaceID: id, sourceKind: portKind?.rawValue ?? "interfaces")
        return trace
    }

    func imageCatalog(kind: InventoryKind, id: Int, deviceTypeID: Int?) async throws -> NetBoxImageCatalog {
        guard id > 0, (deviceTypeID ?? 1) > 0, kind == .devices || deviceTypeID == nil else { throw APIError.invalidReference }
        let policy = NetBoxImagePolicy(apiURL: builder.credential.configuration.baseURL)
        let type = kind == .virtualMachines ? "virtualization.virtualmachine" : kind == .sites ? "dcim.site" : kind == .racks ? "dcim.rack" : "dcim.device"
        var images: [NetBoxImageReference] = [], count = 0, unavailable = false
        do {
            let items = [URLQueryItem(name: "object_type", value: type), .init(name: "object_id", value: String(id)), .init(name: "ordering", value: "-id"), .init(name: "limit", value: "4")]
            let page: NetBoxImagePage = try await get("extras/image-attachments/", query: items)
            guard page.count >= page.results.count, page.results.count <= 4, Set(page.results.map(\.id)).count == page.results.count,
                  (page.next == nil ? page.count == page.results.count : page.count > page.results.count && !page.results.isEmpty) else { throw APIError.invalidResponse }
            try CollectionLinks.validate(page.next, path: "extras/image-attachments/", required: items)
            count = page.count
            for image in page.results {
                guard image.id > 0, image.objectType == type, image.objectID == id, image.parent?.id == id,
                      (image.imageSize ?? 0) >= 0, (image.imageSize ?? 0) <= NetBoxImagePolicy.byteLimit else { throw APIError.invalidResponse }
                images.append(.init(id: "attachment-\(image.id)", title: image.name, url: try policy.url(image.image), attachmentID: image.id))
            }
        } catch { if Task.isCancelled { throw CancellationError() }; unavailable = true }
        if let deviceTypeID {
            do {
                let object: NetBoxDeviceImages = try await get("dcim/device-types/\(deviceTypeID)/")
                guard object.id == deviceTypeID, !object.model.isEmpty else { throw APIError.invalidResponse }
                for (label, value) in [("Front", object.front), ("Rear", object.rear)] {
                    if let value { images.append(.init(id: "type-\(deviceTypeID)-\(label)", title: L10n.text(label) + " · " + object.model, url: try policy.url(value))) }
                }
            } catch { if Task.isCancelled { throw CancellationError() }; unavailable = true }
        }
        return .init(images: images, attachmentCount: count, unavailable: unavailable)
    }

    private func contextDuplicateRows(kind: ContextKind, field: String, text: String) async throws -> [ContextAdminRecord] {
        guard kind.writable else { throw APIError.invalidReference }
        let items = [URLQueryItem(name: field, value: text), .init(name: "ordering", value: "id"), .init(name: "limit", value: "50")]
        var next: String?, total: Int?, ids = Set<Int>(), visited = Set<String>(), rows: [ContextAdminRecord] = []
        for _ in 0..<100 {
            try CollectionLinks.validate(next, path: kind.path, required: items)
            let page: ContextAdminPage = try await get(next ?? kind.path, query: next == nil ? items : [])
            guard page.count >= 0, page.results.count <= 50, total == nil || total == page.count else { throw APIError.invalidResponse }; total = page.count
            for record in page.results {
                try record.validate(kind)
                let actual = field == "name" ? record.row.name : field == "slug" ? record.row.slug : record.row.rd
                guard actual == text, ids.insert(record.row.id).inserted else { throw APIError.invalidResponse }; rows.append(record)
            }
            guard rows.count <= page.count else { throw APIError.invalidResponse }
            guard let link = page.next else { guard rows.count == page.count else { throw APIError.invalidResponse }; return rows }
            guard !page.results.isEmpty, visited.insert(link).inserted else { throw APIError.invalidResponse }; next = link
        }
        throw APIError.invalidResponse
    }
    private func contextReference(_ reference: ReferenceSelection?, path: String) async throws {
        if let reference { guard reference.id > 0 else { throw APIError.invalidReference }; let row: EditReference = try await get(path + "\(reference.id)/"); guard row.id == reference.id else { throw APIError.invalidReference } }
    }
    private func contextUniqueness(kind: ContextKind, name: String, slug: String?, rd: String?, group: Int?, excluding id: Int? = nil) async throws {
        var checks = [("name", name)]
        if let slug { checks.append(("slug", slug)) }
        if let rd, !rd.isEmpty { checks.append(("rd", rd)) }
        for (field, text) in checks {
            for candidate in try await contextDuplicateRows(kind: kind, field: field, text: text) where candidate.row.id != id {
                // NetBox permits reused VRF names; creation/rename use a conservative visible-name check.
                if kind != .tenants || candidate.row.group?.id == group { throw APIError.duplicateContext }
            }
        }
    }
    func checkContextCreation(_ plan: ContextCreationPlan) async throws {
        try plan.validate(); try await contextReference(plan.tenant, path: "tenancy/tenants/"); try await contextReference(plan.group, path: "tenancy/tenant-groups/")
        try await contextUniqueness(kind: plan.kind, name: plan.name, slug: plan.kind == .vrfs ? nil : plan.slug, rd: plan.kind == .vrfs ? plan.rd : nil, group: plan.group?.id)
    }
    func createContext(_ plan: ContextCreationPlan) async throws -> ContextAdminRecord {
        try await checkContextCreation(plan); try Task.checkCancellation()
        var request = try builder.get(plan.kind.path); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(plan)
        let (record, _): (ContextAdminRecord, String?) = try await send(request)
        try record.validate(plan.kind); guard plan.matches(record) else { throw APIError.invalidResponse }; return record
    }
    func contextEditSnapshot(kind: ContextKind, id: Int, field: ContextEditField) async throws -> ContextEditSnapshot {
        guard id > 0, field.supports(kind) else { throw APIError.invalidReference }
        let (record, tag): (ContextAdminRecord, String?) = try await send(builder.get(kind.path + "\(id)/")); try record.validate(kind, id: id)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }; _ = try record.value(field)
        return .init(kind: kind, field: field, record: record, etag: tag)
    }
    func checkContextEdit(_ snapshot: ContextEditSnapshot, value: ContextEditValue) async throws {
        try value.validate(field: snapshot.field, kind: snapshot.kind); try snapshot.record.validate(snapshot.kind, id: snapshot.record.row.id)
        let row = snapshot.record.row
        if case .reference(let ref) = value { try await contextReference(ref, path: snapshot.field.path) }
        if [.name, .slug, .group].contains(snapshot.field) {
            var name = row.name, slug = row.slug, group = row.group?.id
            if case .text(let text) = value { if snapshot.field == .name { name = text } else { slug = text } }
            if case .reference(let ref) = value { group = ref?.id }
            try await contextUniqueness(kind: snapshot.kind, name: name, slug: slug, rd: nil, group: group, excluding: row.id)
        }
    }
    func updateContext(_ snapshot: ContextEditSnapshot, value: ContextEditValue) async throws -> ContextEditSnapshot {
        let fresh = try await contextEditSnapshot(kind: snapshot.kind, id: snapshot.record.row.id, field: snapshot.field)
        guard fresh.etag == snapshot.etag, try fresh.record.unchanged(from: snapshot.record) else { throw APIError.conflict }
        try await checkContextEdit(fresh, value: value); try Task.checkCancellation()
        var request = try builder.get(snapshot.path); request.httpMethod = "PATCH"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match"); request.httpBody = try JSONEncoder().encode(ContextEditPayload(kind: snapshot.kind, field: snapshot.field, value: value))
        let (record, tag): (ContextAdminRecord, String?) = try await send(request); try record.validate(snapshot.kind, id: snapshot.record.row.id)
        guard try record.value(snapshot.field).matches(value), try record.unchanged(from: snapshot.record, except: snapshot.field) else { throw APIError.invalidResponse }
        return .init(kind: snapshot.kind, field: snapshot.field, record: record, etag: tag ?? snapshot.etag)
    }

    func vlanAdminSnapshot(kind: VLANBrowseKind, id: Int, field: VLANAdminField) async throws -> VLANAdminSnapshot {
        guard id > 0, field.supports(kind) else { throw APIError.invalidReference }
        let (record, tag): (VLANAdminRecord, String?) = try await send(builder.get(kind.path + "\(id)/"))
        try record.validate(kind: kind, id: id)
        _ = try record.value(field)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return .init(kind: kind, field: field, record: record, etag: tag)
    }

    private func vlanAdminRows(kind: VLANBrowseKind, items: [URLQueryItem]) async throws -> [VLANBrowseRecord] {
        let query = items + [.init(name: "ordering", value: "id"), .init(name: "limit", value: "50")]
        var rows: [VLANBrowseRecord] = [], next: String?, total: Int?, ids = Set<Int>(), visited = Set<String>()
        for _ in 0..<100 {
            try CollectionLinks.validate(next, path: kind.path, required: query)
            let page: NetBoxPage<VLANBrowseRecord> = try await get(next ?? kind.path, query: next == nil ? query : [])
            guard page.count >= 0, page.results.count <= 50, total == nil || total == page.count else { throw APIError.invalidResponse }
            total = page.count
            for row in page.results { try row.validate(kind: kind); guard ids.insert(row.id).inserted else { throw APIError.invalidResponse }; rows.append(row) }
            guard ids.count <= page.count else { throw APIError.invalidResponse }
            guard let link = page.next else { guard ids.count == page.count else { throw APIError.invalidResponse }; return rows }
            guard !page.results.isEmpty, visited.insert(link).inserted else { throw APIError.invalidResponse }; next = link
        }
        throw APIError.invalidResponse
    }

    private func checkVLANMembership(vid: Int, site: Int?, group: VLANBrowseRecord) async throws {
        guard Set(["scope_type", "scope_id", "scope", "vid_ranges"]).isSubset(of: group.knownFields), let ranges = group.vidRanges else { throw APIError.invalidResponse }
        try VLANGroupCreationPlan.validateRanges(ranges)
        guard ranges.contains(where: { $0[0] <= vid && vid <= $0[1] }) else { throw APIError.invalidVID }
        guard let scope = VLANGroupScope(rawValue: group.scopeType ?? "") else { throw APIError.unsupportedVLANScope }
        guard scope == .global ? group.scopeID == nil && group.scope == nil : (group.scopeID ?? 0) > 0 && group.scope?.id == group.scopeID else { throw APIError.invalidResponse }
        if let site, scope == .site { guard site == group.scopeID else { throw APIError.invalidReference } }
        if let site, scope == .siteGroup {
            let record = try await InventoryService(client: self, kind: .sites).detail(id: site)
            guard record.group?.id == group.scopeID else { throw APIError.invalidReference }
        }
    }

    func checkVLANAdministration(_ snapshot: VLANAdminSnapshot, value: VLANAdminValue) async throws {
        try snapshot.record.validate(kind: snapshot.kind, id: snapshot.record.row.id)
        try value.validate(field: snapshot.field, kind: snapshot.kind)
        let row = snapshot.record.row
        if snapshot.kind == .vlans {
            let dependency = try await deletionSnapshot(.init(collection: .vlans, id: row.id))
            guard dependency.etag == snapshot.etag else { throw APIError.conflict }
            guard dependency.blockers.isEmpty else { throw APIError.vlanIdentityBlocked }
            var vid = row.vid ?? 0, site = row.site?.id, group = row.group?.id
            switch (snapshot.field, value) {
            case (.vid, .vid(let n)): vid = n
            case (.site, .reference(let r)): site = r?.id
            case (.group, .reference(let r)): group = r?.id
            default: throw APIError.invalidReference
            }
            if let site { let ref: EditReference = try await get("dcim/sites/\(site)/"); guard ref.id == site else { throw APIError.invalidReference } }
            if let group { let selected = try await VLANBrowseService(client: self, kind: .groups).detail(id: group); try await checkVLANMembership(vid: vid, site: site, group: selected) }
            var base = [URLQueryItem(name: "group_id", value: group.map(String.init) ?? "null")]
            if group == nil { base.append(.init(name: "site_id", value: site.map(String.init) ?? "null")) }
            for (field, expected) in [("vid", String(vid)), ("name", row.name)] {
                let matches = try await vlanAdminRows(kind: .vlans, items: base + [.init(name: field, value: expected)])
                for candidate in matches {
                    guard Set(["site", "group"]).isSubset(of: candidate.knownFields), candidate.group?.id == group,
                          (group != nil || candidate.site?.id == site), (field == "vid" ? candidate.vid == vid : candidate.name == row.name) else { throw APIError.invalidResponse }
                    guard candidate.id == row.id else { throw APIError.duplicateVLAN }
                }
            }
        } else {
            if case .reference(let ref) = value, let ref {
                let fresh: EditReference = try await get("tenancy/tenants/\(ref.id)/"); guard fresh.id == ref.id else { throw APIError.invalidReference }
            }
            if snapshot.field == .ranges || snapshot.field == .scope {
                let members = try await vlanAdminRows(kind: .vlans, items: [.init(name: "group_id", value: String(row.id))])
                guard members.count == row.vlanCount, members.allSatisfy({ $0.knownFields.contains("group") && $0.group?.id == row.id }) else { throw APIError.invalidResponse }
                if case .scope = value { guard members.isEmpty else { throw APIError.groupMembersBlocked } }
                if case .ranges(let ranges) = value {
                    guard members.allSatisfy({ member in ranges.contains { $0[0] <= (member.vid ?? 0) && (member.vid ?? 0) <= $0[1] } }) else { throw APIError.groupMembersBlocked }
                }
            }
            if snapshot.field == .slug || snapshot.field == .scope {
                var type = row.scopeType, scopeID = row.scopeID, slug = row.slug ?? ""
                if case .slug(let text) = value { slug = text }
                if case .scope(let scope, let reference) = value {
                    type = scope == .global ? nil : scope.rawValue; scopeID = reference?.id
                    if let reference { let fresh: EditReference = try await get(scope.path + "\(reference.id)/"); guard fresh.id == reference.id else { throw APIError.invalidReference } }
                }
                for (field, text) in [("name", row.name), ("slug", slug)] {
                    let matches = try await vlanAdminRows(kind: .groups, items: [.init(name: field, value: text)])
                    for candidate in matches {
                        guard Set(["scope_type", "scope_id", "scope"]).isSubset(of: candidate.knownFields), (field == "name" ? candidate.name : candidate.slug) == text,
                              (candidate.scopeType == nil && candidate.scopeID == nil && candidate.scope == nil) || (candidate.scopeType != nil && (candidate.scopeID ?? 0) > 0 && candidate.scope?.id == candidate.scopeID) else { throw APIError.invalidResponse }
                        if candidate.id != row.id && candidate.scopeType == type && candidate.scopeID == scopeID { throw APIError.duplicateVLANGroup }
                    }
                }
            }
        }
    }

    func updateVLANAdministration(_ snapshot: VLANAdminSnapshot, value: VLANAdminValue) async throws -> VLANAdminSnapshot {
        let fresh = try await vlanAdminSnapshot(kind: snapshot.kind, id: snapshot.record.row.id, field: snapshot.field)
        guard fresh.etag == snapshot.etag, try fresh.record.unchanged(from: snapshot.record, except: nil) else { throw APIError.conflict }
        try await checkVLANAdministration(fresh, value: value)
        try Task.checkCancellation()
        var request = try builder.get(snapshot.path)
        request.httpMethod = "PATCH"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(VLANAdminPayload(kind: snapshot.kind, field: snapshot.field, value: value))
        let (record, tag): (VLANAdminRecord, String?) = try await send(request)
        try record.validate(kind: snapshot.kind, id: snapshot.record.row.id)
        guard try record.value(snapshot.field).matches(value), try record.unchanged(from: snapshot.record, except: snapshot.field),
              snapshot.kind != .vlans || record.dependency?.blockers.isEmpty == true else { throw APIError.invalidResponse }
        return .init(kind: snapshot.kind, field: snapshot.field, record: record, etag: tag ?? snapshot.etag)
    }

    func checkVLANGroupCreation(_ plan: VLANGroupCreationPlan) async throws {
        try plan.validate()
        for (reference, path) in [(plan.reference, plan.scope.path), (plan.tenant, "tenancy/tenants/")] {
            if let reference {
                let object: EditReference = try await get(path + "\(reference.id)/")
                guard object.id == reference.id else { throw APIError.invalidReference }
            }
        }
        // Scan exact-name/slug matches across scopes: null content-type filtering
        // is not assumed. Bounded pages preserve the exact filter and ordering.
        for (field, value) in [("name", plan.name), ("slug", plan.slug)] {
            let items = [URLQueryItem(name: field, value: value), .init(name: "ordering", value: "id"), .init(name: "limit", value: "50")]
            var next: String?; var visited = Set<String>(); var ids = Set<Int>(); var total: Int?
            var finished = false
            for _ in 0..<100 {
                try CollectionLinks.validate(next, path: "ipam/vlan-groups/", required: items)
                let page: NetBoxPage<VLANBrowseRecord> = try await get(next ?? "ipam/vlan-groups/", query: next == nil ? items : [])
                guard page.count >= 0, page.results.count <= 50, total == nil || total == page.count else { throw APIError.invalidResponse }
                total = page.count
                for row in page.results {
                    try row.validate(kind: .groups)
                    guard ids.insert(row.id).inserted, (field == "name" ? row.name : row.slug) == value,
                          Set(["scope_type", "scope_id", "scope"]).isSubset(of: row.knownFields) else { throw APIError.invalidResponse }
                    if plan.matchesScope(row) { throw APIError.duplicateVLANGroup }
                }
                guard ids.count <= page.count else { throw APIError.invalidResponse }
                guard let link = page.next else {
                    guard ids.count == page.count else { throw APIError.invalidResponse }
                    finished = true; break
                }
                guard !page.results.isEmpty, visited.insert(link).inserted else { throw APIError.invalidResponse }
                next = link
            }
            guard finished else { throw APIError.invalidResponse }
        }
    }

    func createVLANGroup(_ plan: VLANGroupCreationPlan) async throws -> VLANBrowseRecord {
        try await checkVLANGroupCreation(plan)
        try Task.checkCancellation()
        var request = try builder.get("ipam/vlan-groups/")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        let (row, _): (VLANBrowseRecord, String?) = try await send(request)
        try row.validate(kind: .groups)
        guard plan.matches(row) else { throw APIError.invalidResponse }
        return row
    }

    func checkVLANCreation(_ plan: VLANCreationPlan) async throws {
        try plan.validate()
        for (reference, path) in [(plan.site, "dcim/sites/"), (plan.tenant, "tenancy/tenants/"), (plan.role, "ipam/roles/")] {
            if let reference {
                let object: EditReference = try await get(path + "\(reference.id)/")
                guard object.id == reference.id else { throw APIError.invalidReference }
            }
        }
        if let group = plan.group {
            let object = try await VLANBrowseService(client: self, kind: .groups).detail(id: group.id)
            guard let ranges = object.vidRanges, !ranges.isEmpty, ranges.contains(where: { $0[0] <= plan.vid && plan.vid <= $0[1] }) else { throw APIError.invalidVID }
            if let site = plan.site, object.scopeType == "dcim.site", object.scopeID != site.id { throw APIError.invalidReference }
            if let site = plan.site, object.scopeType == "dcim.sitegroup" {
                let record = try await InventoryService(client: self, kind: .sites).detail(id: site.id)
                guard let id = record.group?.id, let scopeID = object.scopeID,
                      id == scopeID else { throw APIError.invalidReference }
            }
        }
        // Group VID/name uniqueness is server enforced. Ungrouped VIDs may recur;
        // the app's additional visible duplicate check uses the selected direct site.
        var query = [URLQueryItem(name: "group_id", value: plan.group.map { String($0.id) } ?? "null"), .init(name: "limit", value: "1")]
        if plan.group == nil { query.append(.init(name: "site_id", value: plan.site.map { String($0.id) } ?? "null")) }
        for (field, value) in [("vid", String(plan.vid)), ("name", plan.name)] {
            let page: NetBoxPage<VLANBrowseRecord> = try await get("ipam/vlans/", query: query + [.init(name: field, value: value)])
            guard page.count >= 0, page.results.count <= 1, page.results.allSatisfy({ $0.group?.id == plan.group?.id && (plan.group != nil || $0.site?.id == plan.site?.id) && (field == "vid" ? $0.vid == plan.vid : $0.name == plan.name) }),
                  page.count == 0 ? page.results.isEmpty && page.next == nil : !page.results.isEmpty else { throw APIError.invalidResponse }
            guard page.count == 0 else { throw APIError.duplicateVLAN }
        }
    }

    func createVLAN(_ plan: VLANCreationPlan) async throws -> VLANBrowseRecord {
        try await checkVLANCreation(plan)
        try Task.checkCancellation()
        var request = try builder.get("ipam/vlans/")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        let (row, _): (VLANBrowseRecord, String?) = try await send(request)
        try row.validate(kind: .vlans)
        guard plan.matches(row) else { throw APIError.invalidResponse }
        return row
    }

    func checkMACCreation(_ plan: MACCreationPlan) async throws {
        try plan.validate()
        guard try await macInterfaceParent(kind: plan.interface.kind, id: plan.interface.id) == plan.interface.parentID else { throw APIError.invalidReference }
        let page: NetBoxPage<MACRecord> = try await get("dcim/mac-addresses/", query: [.init(name: "mac_address", value: plan.address.text), .init(name: plan.interface.kind.ipFilter, value: String(plan.interface.id)), .init(name: "limit", value: "1")])
        guard page.count >= 0, page.results.count <= 1,
              page.results.allSatisfy({ (try? MACValue($0.macAddress)) == plan.address && $0.assignment?.0 == plan.interface.kind && $0.assignment?.1 == plan.interface.id }),
              page.count == 0 ? page.results.isEmpty && page.next == nil : !page.results.isEmpty else { throw APIError.invalidResponse }
        guard page.count == 0 else { throw APIError.duplicateMAC }
    }

    func createMAC(_ plan: MACCreationPlan) async throws -> MACRecord {
        try await checkMACCreation(plan)
        try Task.checkCancellation()
        var request = try builder.get("dcim/mac-addresses/")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        let (row, _): (MACRecord, String?) = try await send(request)
        guard (try? MACValue(row.macAddress)) == plan.address, row.assignment?.0 == plan.interface.kind, row.assignment?.1 == plan.interface.id,
              !row.isPrimary, row.description == plan.description, row.comments == plan.comments else { throw APIError.invalidResponse }
        return row
    }

    private func vlanParentSite(_ target: StructuredEditTarget) async throws -> Int? {
        guard target.collection.isInterface, let parentID = target.parentID, parentID > 0 else { throw APIError.invalidURL }
        let path = target.collection == .physicalInterfaces ? "dcim/devices/" : "virtualization/virtual-machines/"
        let parent: VLANParent = try await get(path + "\(parentID)/")
        guard parent.id == parentID else { throw APIError.invalidResponse }
        return parent.site?.id
    }

    func vlanSnapshot(target: StructuredEditTarget) async throws -> VLANSnapshot {
        guard target.collection.isInterface else { throw APIError.invalidURL }
        let (object, tag): (VLANInterface, String?) = try await send(builder.get(target.path))
        try object.validate(target: target)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        let site = try await vlanParentSite(target)
        return VLANSnapshot(target: target, object: object, etag: tag, siteID: site)
    }

    func checkVLANPlan(_ plan: VLANPlan, snapshot: VLANSnapshot) async throws {
        try snapshot.object.validate(target: snapshot.target)
        try plan.validate()
        let site = try await vlanParentSite(snapshot.target)
        guard site == snapshot.siteID else { throw APIError.conflict }
        for selection in (plan.untagged.map { [$0] } ?? []) + plan.tagged {
            let vlan: VLANReference = try await get("ipam/vlans/\(selection.id)/")
            guard vlan.id == selection.id, vlan.site == nil || vlan.site?.id == site else { throw APIError.invalidReference }
        }
    }

    func updateVLAN(_ snapshot: VLANSnapshot, to plan: VLANPlan) async throws -> VLANInterface {
        guard TextEditSnapshot.validETag(snapshot.etag) else { throw APIError.missingETag }
        let fresh = try await vlanSnapshot(target: snapshot.target)
        guard fresh.etag == snapshot.etag, fresh.object.plan.matches(snapshot.object.plan), fresh.siteID == snapshot.siteID else { throw APIError.conflict }
        try await checkVLANPlan(plan, snapshot: fresh)
        var request = try builder.get(snapshot.target.path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(plan)
        let (object, _): (VLANInterface, String?) = try await send(request)
        try object.validate(target: snapshot.target)
        guard object.plan.matches(plan) else { throw APIError.invalidResponse }
        return object
    }

    private func deletionDependencyCount(_ path: String, _ query: [URLQueryItem]) async throws -> Int {
        let page: DeletionDependencyPage = try await get(path, query: query + [.init(name: "limit", value: "1")])
        try page.validate()
        return page.count
    }

    // Search by host is supported by the Device/VM filtersets; inspect every visible page,
    // then compare actual primary-IP IDs (not text or VRF/address coincidence).
    private func deletionPrimaryReferenceExists(path: String, ip: Int, host: String) async throws -> Bool {
        let required = [URLQueryItem(name: "q", value: host), .init(name: "ordering", value: "id")]
        var next: String? = nil
        var visited = Set<String>(), ids = Set<Int>(), total: Int?
        for _ in 0..<100 {
            try CollectionLinks.validate(next, path: path, required: required)
            let page: NetBoxPage<DeletionPrimaryObject> = try await get(next ?? path, query: next == nil ? required + [.init(name: "limit", value: "50")] : [])
            guard page.count >= 0, total == nil || total == page.count else { throw APIError.invalidResponse }
            total = page.count
            for object in page.results {
                guard ids.insert(object.id).inserted else { throw APIError.invalidResponse }
                if object.primaryIP4?.id == ip || object.primaryIP6?.id == ip { return true }
                for value in [object.primaryIP4, object.primaryIP6].compactMap({ $0 }) {
                    guard (value.id ?? 0) > 0 else { throw APIError.invalidResponse }
                }
            }
            guard ids.count <= page.count else { throw APIError.invalidResponse }
            guard let link = page.next else {
                guard ids.count == page.count else { throw APIError.invalidResponse }
                return false
            }
            guard !page.results.isEmpty, visited.insert(link).inserted else { throw APIError.invalidResponse }
            next = link
        }
        throw APIError.invalidResponse
    }

    func deletionSnapshot(_ target: DeletionTarget) async throws -> DeletionSnapshot {
        let (object, tag): (DeletionObject, String?) = try await send(builder.get(target.path))
        try object.validate(target)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        var imageParentTitle: String?
        if let imageParent = target.imageParent { imageParentTitle = try await imageUploadTargetTitle(imageParent) }
        var blockers = object.blockers
        func append(_ count: Int, _ reason: String) { if count > 0 { blockers.append(reason) } }
        if target.collection == .vrfs || target.collection == .ipamRoles {
            let vrf = target.collection == .vrfs
            let paths = vrf ? ["ipam/prefixes/", "ipam/ip-addresses/", "ipam/ip-ranges/", "dcim/interfaces/", "virtualization/interfaces/"] : ["ipam/prefixes/", "ipam/vlans/", "ipam/ip-ranges/", "ipam/asns/"]
            for path in paths {
                let field = vrf ? "vrf" : "role", filter = field + "_id"
                let items = [URLQueryItem(name: filter, value: String(target.id)), .init(name: "limit", value: "1")]
                let page: NetBoxPage<ContextDeletionDependency> = try await get(path, query: items)
                guard page.count >= 0, page.results.count <= 1, page.count >= page.results.count,
                      (page.count == 0 ? page.results.isEmpty && page.next == nil : !page.results.isEmpty),
                      page.results.allSatisfy({ $0.id > 0 && $0.fields.contains(field) && (vrf ? $0.vrf?.id : $0.role?.id) == target.id }) else { throw APIError.invalidResponse }
                try CollectionLinks.validate(page.next, path: path, required: items)
                append(page.count, path)
            }
        } else if target.collection == .prefixes, let cidr = object.cidr {
            let vrf = URLQueryItem(name: "vrf_id", value: object.vrf?.id.map(String.init) ?? "null")
            append(try await deletionDependencyCount("ipam/prefixes/", [.init(name: "within", value: cidr.text), vrf]), "Contained prefixes")
            append(try await deletionDependencyCount("ipam/ip-addresses/", [.init(name: "parent", value: cidr.text), vrf]), "Contained IP addresses")
            append(try await deletionDependencyCount("ipam/ip-ranges/", [.init(name: "parent", value: cidr.text), vrf]), "Contained IP ranges")
        } else if target.collection == .ipAddresses, let cidr = object.cidr {
            for path in ["dcim/devices/", "virtualization/virtual-machines/"] {
                if try await deletionPrimaryReferenceExists(path: path, ip: target.id, host: cidr.host) { blockers.append("Primary IP address") }
            }
            append(try await deletionDependencyCount("dcim/devices/", [.init(name: "oob_ip_id", value: String(target.id))]), "Out-of-band IP address")
            append(try await deletionDependencyCount("ipam/fhrp-groups/", [.init(name: "primary_ip\(cidr.family)_id", value: String(target.id))]), "FHRP groups")
            append(try await deletionDependencyCount("ipam/ip-addresses/", [.init(name: "nat_inside_id", value: String(target.id))]), "NAT relationship")
        } else if target.collection == .macAddresses {
            for path in ["dcim/interfaces/", "virtualization/interfaces/"] {
                append(try await deletionDependencyCount(path, [.init(name: "primary_mac_address_id", value: String(target.id))]), "Primary MAC")
            }
        } else if target.collection == .vlanGroups {
            let members = try await vlanAdminRows(kind: .vlans, items: [.init(name: "group_id", value: String(target.id))])
            guard members.count == object.groupVLANCount, members.allSatisfy({ $0.knownFields.contains("group") && $0.group?.id == target.id }) else { throw APIError.invalidResponse }
            append(members.count, "VLANs")
        } else if target.collection == .vlans {
            let id = String(target.id)
            append(try await deletionDependencyCount("ipam/prefixes/", [.init(name: "vlan_id", value: id)]), "Prefixes")
            for path in ["dcim/interfaces/", "virtualization/interfaces/"] {
                append(try await deletionDependencyCount(path, [.init(name: "vlan_id", value: id)]), "Dependent interfaces")
            }
            append(try await deletionDependencyCount("ipam/vlans/", [.init(name: "qinq_svlan_id", value: id)]), "QinQ relationship")
        } else if let kind = target.collection.interfaceKind {
            append(try await deletionDependencyCount("ipam/ip-addresses/", [.init(name: kind.ipFilter, value: String(target.id))]), "Assigned IP addresses")
            for field in (kind == .physical ? ["parent_id", "bridge_id", "lag_id"] : ["parent_id", "bridge_id"]) {
                append(try await deletionDependencyCount(kind.path, [.init(name: field, value: String(target.id))]), "Dependent interfaces")
            }
        }
        return DeletionSnapshot(target: target, object: object, etag: tag, blockers: Array(Set(blockers)).sorted(), imageParentTitle: imageParentTitle)
    }

    func deleteObject(_ snapshot: DeletionSnapshot) async throws {
        try snapshot.object.validate(snapshot.target)
        guard snapshot.blockers.isEmpty else { throw APIError.deletionBlocked }
        guard TextEditSnapshot.validETag(snapshot.etag) else { throw APIError.missingETag }
        let fresh = try await deletionSnapshot(snapshot.target)
        guard fresh.etag == snapshot.etag, fresh.object.title == snapshot.object.title,
              fresh.object.vrf?.id == snapshot.object.vrf?.id,
              fresh.object.groupMetadata == snapshot.object.groupMetadata, fresh.imageParentTitle == snapshot.imageParentTitle else { throw APIError.conflict }
        guard fresh.blockers.isEmpty else { throw APIError.deletionBlocked }
        try Task.checkCancellation()
        var request = try builder.get(snapshot.target.path)
        request.httpMethod = "DELETE"
        request.setValue(snapshot.etag, forHTTPHeaderField: "If-Match")
        let (data, response) = try await transfer(request)
        guard response.statusCode == 204, data.isEmpty else { throw APIError.invalidResponse }
    }

    func checkCableCreation(_ input: CableCreationPlan) async throws {
        let plan = try input.validated()
        for selected in [plan.a, plan.b] {
            let parent: EditReference = try await get("dcim/devices/\(selected.deviceID)/")
            guard parent.id == selected.deviceID else { throw APIError.invalidReference }
            let endpoint: CableEndpointSnapshot = try await get(selected.path)
            try endpoint.validate(selected)
        }
    }
    func createCable(_ input: CableCreationPlan) async throws -> CableObject {
        let plan = try input.validated()
        try await checkCableCreation(plan)
        try Task.checkCancellation()
        var request = try builder.get("dcim/cables/")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        let (data, response) = try await transfer(request)
        guard response.statusCode == 201, response.mimeType == "application/json" else { throw APIError.invalidResponse }
        let cable: CableObject
        do { cable = try JSONDecoder().decode(CableObject.self, from: data) } catch { throw APIError.decoding }
        try plan.validateReply(cable)
        return cable
    }

    func cableRewireSnapshot(id: Int) async throws -> (CableObject, String) {
        guard id > 0 else { throw APIError.invalidURL }
        let (cable, tag): (CableObject, String?) = try await send(builder.get("dcim/cables/\(id)/"))
        guard cable.id == id else { throw APIError.invalidResponse }
        _ = try CableRewirePlan.ends(of: cable)
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return (cable, tag)
    }
    func checkCableRewire(_ input: CableRewirePlan) async throws {
        let plan = try input.validated()
        let (cable, tag) = try await cableRewireSnapshot(id: plan.cableID)
        guard tag == plan.etag else { throw APIError.conflict }
        try plan.matches(cable, moved: false)
        let parent: EditReference = try await get("dcim/devices/\(plan.destination.deviceID)/")
        guard parent.id == plan.destination.deviceID else { throw APIError.invalidReference }
        let endpoint: CableEndpointSnapshot = try await get(plan.destination.path)
        try endpoint.validate(plan.destination)
    }
    func rewireCable(_ input: CableRewirePlan) async throws -> CableObject {
        let plan = try input.validated()
        try await checkCableRewire(plan)
        try Task.checkCancellation()
        var request = try builder.get("dcim/cables/\(plan.cableID)/")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(plan.etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try plan.body
        // Never retry: a lost reply does not tell whether the end already moved.
        let (cable, _): (CableObject, String?) = try await send(request)
        try plan.matches(cable, moved: true)
        return cable
    }

    func markConnectedSnapshot(_ port: CableEndpointSelection) async throws -> (CableEndpointSnapshot, String) {
        try port.validate()
        let (snapshot, tag): (CableEndpointSnapshot, String?) = try await send(builder.get(port.path))
        guard snapshot.id == port.id, snapshot.device.id == port.deviceID, snapshot.name == port.name else { throw APIError.invalidReference }
        guard let tag, TextEditSnapshot.validETag(tag) else { throw APIError.missingETag }
        return (snapshot, tag)
    }
    /// Toggles mark_connected on one free port. A cabled port cannot be marked; the reviewed ETag must still hold.
    func setMarkConnected(_ port: CableEndpointSelection, etag: String, to value: Bool) async throws -> CableEndpointSnapshot {
        let (fresh, tag) = try await markConnectedSnapshot(port)
        guard tag == etag, fresh.marked != value else { throw APIError.conflict }
        guard !value || fresh.cable == nil else { throw CableCreationError.occupied }
        try Task.checkCancellation()
        var request = try builder.get(port.path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(etag, forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(["mark_connected": value])
        let (reply, _): (CableEndpointSnapshot, String?) = try await send(request)
        guard reply.id == port.id, reply.device.id == port.deviceID, reply.name == port.name, reply.marked == value, !value || reply.cable == nil else { throw APIError.invalidResponse }
        return reply
    }

    func checkInterfaceCreation(_ input: InterfaceCreationPlan) async throws {
        let plan = try input.validated()
        let parent: EditReference = try await get(plan.kind.parentKind.path + "\(plan.parentID)/")
        guard parent.id == plan.parentID else { throw APIError.invalidReference }
        let page: NetBoxPage<InterfaceObject> = try await get(plan.kind.path, query: [.init(name: plan.kind.parentFilter, value: String(plan.parentID)), .init(name: "name", value: plan.name), .init(name: "limit", value: "1")])
        let service = InterfaceService(client: self, kind: plan.kind)
        guard page.count >= 0, page.results.count <= 1,
              (page.count == 0 ? page.results.isEmpty && page.next == nil : !page.results.isEmpty),
              page.results.allSatisfy({ $0.id > 0 && $0.name == plan.name && service.parent($0)?.id == plan.parentID }) else { throw APIError.invalidResponse }
        guard page.count == 0 else { throw APIError.duplicateInterface }
    }

    func createInterface(_ input: InterfaceCreationPlan) async throws -> InterfaceObject {
        let plan = try input.validated()
        try await checkInterfaceCreation(plan)
        try Task.checkCancellation()
        var request = try builder.get(plan.kind.path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        let (reply, _): (InterfaceCreationReply, String?) = try await send(request)
        let object = reply.object
        let service = InterfaceService(client: self, kind: plan.kind)
        guard object.id > 0, service.parent(object)?.id == plan.parentID, object.name == plan.name,
              object.enabled == plan.enabled, object.mtu == plan.mtu, object.description == plan.description,
              plan.kind == .virtual || reply.type == plan.type else { throw APIError.invalidResponse }
        return object
    }

    func checkIPAMCreation(_ input: IPAMCreationPlan) async throws {
        let plan = try input.validated()
        let query = [URLQueryItem(name: plan.kind == .prefixes ? "prefix" : "address", value: plan.kind == .prefixes ? plan.cidr.text : plan.cidr.host),
                     URLQueryItem(name: "vrf_id", value: plan.vrf.map { String($0.id) } ?? "null"),
                     URLQueryItem(name: "limit", value: "1")]
        let page: NetBoxPage<IPAMObject> = try await get(plan.kind.path, query: query)
        guard page.count >= 0, page.results.count <= 1,
              (page.count == 0 ? (page.results.isEmpty && page.next == nil) : !page.results.isEmpty),
              page.results.allSatisfy({ plan.matches($0, exactMask: plan.kind == .prefixes) }) else { throw APIError.invalidResponse }
        guard page.count == 0 else { throw APIError.duplicateIPAM }
    }

    func createIPAM(_ input: IPAMCreationPlan) async throws -> IPAMObject {
        let plan = try input.validated()
        try await checkIPAMCreation(plan) // Advisory visible-object check; the server still decides uniqueness.
        var request = try builder.get(plan.kind.path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(plan)
        // One attempt only. POST has no detail ETag or assumed idempotency contract.
        let (reply, _): (IPAMCreationReply, String?) = try await send(request)
        let object = reply.object
        guard plan.matches(object), (plan.tenant == nil ? object.tenant == nil : object.tenant?.id == plan.tenant?.id), reply.status == plan.status,
              object.family?.value == plan.cidr.family, object.description == plan.description,
              object.comments == plan.comments,
              (plan.kind == .prefixes || (object.dnsName == plan.dnsName && object.assignedObjectID == nil && object.assignedObjectType == nil)) else {
            throw APIError.invalidResponse
        }
        return object
    }

    // Original strong-ETag helper. Text edits use their paired snapshot instead.
    func ifMatchHeaders(for path: String) throws -> [String: String] {
        let url = try builder.credential.configuration.validatedURL(path)
        guard let tag = etags[url], !tag.hasPrefix("W/"), tag != "*" else { throw APIError.missingETag }
        return ["If-Match": tag]
    }

    func validateConnection() async throws {
        struct Status: Decodable, Sendable {
            let version: String
            enum CodingKeys: String, CodingKey { case version = "netbox-version" }
        }
        let status: Status = try await get("status/")
        guard !status.version.isEmpty else { throw APIError.invalidResponse }
        // Explicitly validate the user: public collection access does not prove authentication.
        struct User: Decodable, Sendable { let id: Int; let username: String }
        let _: User = try await get("authentication-check/")
    }

    func close() { session.invalidateAndCancel(); etags.removeAll() }
}
