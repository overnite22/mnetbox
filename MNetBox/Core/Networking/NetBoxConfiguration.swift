import Foundation

struct NetBoxConfiguration: Codable, Equatable, Sendable {
    let baseURL: URL

    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.path.contains(".."), !parts.path.contains("%") else { throw APIError.invalidURL }
        parts.scheme = "https"
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/api") { path = String(path.dropLast(4)) }
        parts.path = path + "/api/"
        guard let url = parts.url else { throw APIError.invalidURL }
        baseURL = url
    }

    func validatedURL(_ reference: String) throws -> URL {
        guard let url = URL(string: reference, relativeTo: baseURL)?.absoluteURL,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.absoluteString.hasPrefix(baseURL.absoluteString), !url.path.contains(".."),
              !parts.percentEncodedPath.lowercased().contains("%2e"),
              !parts.percentEncodedPath.lowercased().contains("%2f") else { throw APIError.invalidURL }
        return url
    }
}

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL, invalidToken, invalidResponse, decoding, unauthorized, forbidden, conflict
    case http(Int, [String: [String]])
    case invalidCIDR, networkHostBits, duplicateIPAM
    case assignmentPrimaryBlocked, assignmentOOBBlocked, assignmentRejected
    case invalidVLANConfiguration, unsupportedVLANConfiguration
    case unsupportedPrefixScope, ipamMoveBlocked, unsupportedVLANScope, vlanIdentityBlocked, groupMembersBlocked
    case deletionBlocked
    case requiredInterfaceName, duplicateInterface
    case requiredName, invalidName, invalidStatus, invalidLength, invalidPosition, duplicateDevice, requiredJournalText
    case invalidVID, requiredVLANName, duplicateVLAN, duplicateVLANGroup, invalidMAC, duplicateMAC, primaryMACBlocked, macAssignmentRejected
    case invalidMTU, invalidReference, requiredRole, invalidWeight, duplicateContext, invalidImage
    case transport, keychain(Int32), missingETag, descriptionTooLong, invalidDNSName, textTooLong(Int)

    var errorDescription: String? {
        switch self {
        case .assignmentPrimaryBlocked: L10n.text("This IP is a primary address. Clear its primary IPv4/IPv6 designation on the device or VM before removing or changing its parent assignment.")
        case .assignmentOOBBlocked: L10n.text("This IP is an OOB address. Clear its OOB designation in NetBox before removing or changing its parent assignment.")
        case .assignmentRejected: L10n.text("NetBox rejected this assignment. Check primary/OOB designations and interface compatibility in NetBox, then reload before trying again.")
        case .invalidVLANConfiguration: L10n.text("Check the VLAN mode and selections. Routed mode requires no VLANs; Access and Tagged all require an empty tagged list.")
        case .unsupportedVLANConfiguration: L10n.text("This interface uses an unsupported VLAN mode, QinQ or a translation policy. Edit its VLAN configuration in NetBox.")
        case .unsupportedPrefixScope: L10n.text("This prefix uses an unsupported scope. Manage its scope in NetBox.")
        case .unsupportedVLANScope: L10n.text("This VLAN group scope cannot be edited in this app.")
        case .vlanIdentityBlocked: L10n.text("VLAN ID, site and group changes require a VLAN without visible prefix, interface, QinQ or L2VPN dependencies. No related object is changed automatically.")
        case .groupMembersBlocked: L10n.text("The group contains incompatible VLANs. Keep every member VID in range; changing scope requires an empty group.")
        case .ipamMoveBlocked: L10n.text("Address or VRF changes require an unused prefix or an unassigned IP without primary, OOB, FHRP or NAT dependencies. No related object is moved automatically.")
        case .deletionBlocked: L10n.text("Deletion is blocked by a dependency. Review the current object in NetBox.")
        case .requiredInterfaceName: L10n.text("Enter an interface name (1–64 characters).")
        case .duplicateInterface: L10n.text("An interface with this name already exists on this parent.")
        case .invalidWeight: L10n.text("Weight must be an integer from 0 to 32767.")
        case .duplicateContext: L10n.text("A matching context already exists. Review its name, slug, group or route distinguisher.")
        case .invalidImage: L10n.text("This image is unavailable or unsupported. Only bounded images from this NetBox server can be displayed.")
        case .invalidVID: L10n.text("Enter a VLAN ID from 1 to 4094.")
        case .requiredVLANName: L10n.text("A VLAN must have a name.")
        case .duplicateVLANGroup: L10n.text("This group name or slug already exists in the selected scope. Review existing VLAN groups.")
        case .duplicateVLAN: L10n.text("This VLAN ID or name already exists in the selected context. Review existing VLANs.")
        case .invalidMAC: L10n.text("Enter a 48-bit MAC address, for example 02:00:00:00:00:01.")
        case .duplicateMAC: L10n.text("This MAC address already exists on this interface. Review the existing MAC.")
        case .macAssignmentRejected: L10n.text("NetBox rejected this MAC assignment. Check its primary designation and interface, then reload before trying again.")
        case .primaryMACBlocked: L10n.text("This MAC is primary on its interface. Clear that primary designation before removing or changing its assignment.")
        case .invalidMTU: L10n.text("Enter 1 to 65536, or leave empty to clear MTU.")
        case .invalidReference: L10n.text("This reference is unavailable or incompatible. Choose another value.")
        case .requiredRole: L10n.text("A device must have a role.")
        case .requiredName: L10n.text("A virtual machine must have a name.")
        case .invalidName: L10n.text("The name must not contain line breaks or control characters.")
        case .invalidStatus: L10n.text("Choose a supported status for this object.")
        case .requiredJournalText: L10n.text("Write the journal entry before reviewing it.")
        case .invalidPosition: L10n.text("Choose a rack, a face and a position between 1 and 100, or no position.")
        case .duplicateDevice: L10n.text("A visible device already uses this name in the site, or this asset tag.")
        case .invalidLength: L10n.text("Enter a positive length with at most two decimals, or leave it empty.")
        case .invalidCIDR: L10n.text("Enter an IPv4 or IPv6 address with its prefix length, for example 192.0.2.10/24 or 2001:db8::1/64.")
        case .networkHostBits: L10n.text("A prefix must use its network address. For example, use 192.0.2.0/24 rather than 192.0.2.10/24.")
        case .duplicateIPAM: L10n.text("This prefix or IP address already exists in the selected VRF. Review the existing object before creating another.")
        case .invalidURL: L10n.text("Enter a valid HTTPS NetBox URL without credentials, a query, or a fragment.")
        case .invalidToken: L10n.text("Enter a token without spaces or line breaks.")
        case .invalidResponse: L10n.text("The server did not return a valid NetBox API response.")
        case .decoding: L10n.text("The API response could not be read.")
        case .unauthorized: L10n.text("Your token was rejected. Reconnect with a valid token.")
        case .forbidden: L10n.text("Your token was rejected or does not have permission for this request.")
        case .conflict: L10n.text("This object changed on the server. Reload it before saving.")
        case .http(let status, _): L10n.format("The server returned HTTP %ld.", status)
        case .transport: L10n.text("Unable to connect. Check your network and server address.")
        case .keychain: L10n.text("Secure storage is unavailable. Unlock your device and try again.")
        case .missingETag: L10n.text("The server did not provide a usable version. Editing is unavailable.")
        case .invalidDNSName: L10n.text("Enter a hostname or FQDN using letters, numbers, hyphens, underscores and dots. A wildcard is allowed only at the start.")
        case .textTooLong(let limit): L10n.format("Maximum %ld characters", limit)
        case .descriptionTooLong: L10n.text("The description must contain at most 200 characters.")
        }
    }
}

struct NetBoxPage<Item: Codable & Sendable>: Codable, Sendable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [Item]
}

func readErrorMessage(_ error: Error) -> String {
    (error as? APIError)?.localizedDescription ?? APIError.transport.localizedDescription
}
