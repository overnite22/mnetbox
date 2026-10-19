import XCTest
@testable import MNetBox

@MainActor final class DescriptionEditingTests: XCTestCase {
    private func client(_ scenario: String = "success") throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EditProtocol.self]
        return APIClient(credential: Credential(configuration: try NetBoxConfiguration("https://\(scenario).test"),
                                               token: "test-placeholder", kind: .bearer), session: URLSession(configuration: config))
    }
    private let target = TextEditTarget(collection: .sites, id: 101)
    func testAllTargetsAreDetailPathsAndRejectNonpositiveIDs() throws {
        for collection in TextEditTarget.Collection.allCases {
            XCTAssertEqual(try TextEditTarget(collection: collection, id: 101).path, collection.rawValue + "101/")
            XCTAssertThrowsError(try TextEditTarget(collection: collection, id: 0).path)
        }
    }
    func testWeakNetBoxETagAndDescriptionOnlyPatchIncludingClearing() async throws {
        let api = try client()
        let snapshot = try await api.textSnapshot(for: target)
        XCTAssertEqual(snapshot.etag, "W/\"revision-1\"")
        for value in ["Bonjour réseau 🌍", ""] {
            let result = try await api.updateText(snapshot, to: value)
            XCTAssertEqual(result.object.description, value)
        }
        await api.close()
    }
    func testSnapshotVersionIsNotReplacedByAnotherGET() async throws {
        let api = try client()
        let snapshot = try await api.textSnapshot(for: target)
        let _: TextEditObject = try await api.get("dcim/sites/101/", query: [.init(name: "newer", value: "true")])
        let result = try await api.updateText(snapshot, to: "Changed")
        XCTAssertEqual(result.object.description, "Changed")
        await api.close()
    }
    func testMissingVersionWrongIdentityAndMalformedVersionsFailClosed() async throws {
        for scenario in ["missing", "wrongid"] {
            let api = try client(scenario)
            do { _ = try await api.textSnapshot(for: target); XCTFail("Invalid snapshot") }
            catch { XCTAssertEqual(error as? APIError, scenario == "missing" ? .missingETag : .invalidResponse) }
            await api.close()
        }
        for tag in ["", "*", "W/\"\"", "revision-1", "\"a\", \"b\"", "W/\"bad\r\nheader\"", "\"bad\"quote\""] {
            XCTAssertFalse(TextEditSnapshot.validETag(tag))
        }
    }
    func testDeniedConflictAndLostResponseRequireReloadKeepDraftAndNoRetry() async throws {
        for scenario in ["forbidden", "conflict", "lost", "wrongreply"] {
            let api = try client(scenario)
            let model = TextEditModel(client: api, target: target)
            await model.load(); XCTAssertNil(model.errorMessage)
            model.draft = "Changed"
            XCTAssertTrue(model.canSave)
            await model.save()
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload); XCTAssertNotNil(model.errorMessage)
            XCTAssertEqual(model.draft, "Changed"); XCTAssertFalse(model.canSave)
            await model.save() // Must not send a second mutation after uncertainty.
            await model.load()
            XCTAssertEqual(model.draft, "Changed"); XCTAssertFalse(model.requiresReload)
            await api.close()
        }
    }
    func testNoOpLengthAndDoubleSaveAreBlocked() async throws {
        let api = try client()
        let model = TextEditModel(client: api, target: target)
        await model.load(); XCTAssertFalse(model.canSave)
        model.draft = String(repeating: "e\u{301}", count: 101)
        XCTAssertFalse(model.canSave) // NetBox counts Unicode scalar code points, not grapheme clusters.
        do { _ = try await api.updateText(try XCTUnwrap(model.snapshot), to: model.draft); XCTFail("Too long") }
        catch { XCTAssertEqual(error as? APIError, .descriptionTooLong) }
        model.draft = "Changed"; await model.save()
        XCTAssertTrue(model.saved); XCTAssertFalse(model.canSave)
        await model.save(); await api.close()
    }
    func testPreviewAndSaveUseTheSameTrimmedDescription() async throws {
        let api = try client()
        let model = TextEditModel(client: api, target: target)
        await model.load()
        model.draft = "  Original \n"; XCTAssertFalse(model.canSave)
        model.draft = "  Changed \n"
        XCTAssertEqual(model.proposedValue, "Changed"); XCTAssertTrue(model.canSave)
        await model.save()
        XCTAssertTrue(model.saved); XCTAssertEqual(model.snapshot?.object.description, "Changed")
        await api.close()
    }
    func testSyntheticEditsPreserveFullObjectsAndSelectedField() throws {
        let fixture = FixtureDescriptions()
        let network = NetworkWriteFixture()
        for collection in TextEditTarget.Collection.allCases {
            let id = collection == .sites ? 101 : collection == .racks ? 201 : collection == .devices ? 301 : collection == .virtualMachines ? 401 : collection == .prefixes ? 1 : collection == .vlans ? 22 : collection == .vlanGroups ? 31 : 11
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/" + collection.rawValue + "\(id)/")))
            request.httpMethod = "PATCH"
            request.setValue("W/\"fixture-1\"", forHTTPHeaderField: "If-Match")
            request.httpBody = try JSONEncoder().encode(TextEditPayload(field: .comments, value: "## Updated\n\nText"))
            let response = try XCTUnwrap(collection == .vlans || collection == .macAddresses || collection == .vlanGroups ? network.response(request) : fixture.response(request))
            XCTAssertEqual(response.0, 200)
            let object = try JSONDecoder().decode(TextEditObject.self, from: Data(response.1.utf8))
            XCTAssertEqual(object.id, id); XCTAssertEqual(object.comments, "## Updated\n\nText")
            XCTAssertFalse(object.description.isEmpty)
            request.httpMethod = "GET"; request.httpBody = nil
            XCTAssertEqual((collection == .vlans || collection == .macAddresses || collection == .vlanGroups ? network.response(request) : fixture.response(request))?.1, response.1)
        }
    }
    func testCommentsOnlyPayloadAcrossAllCollectionsAndClearing() async throws {
        let api = try client()
        for collection in TextEditTarget.Collection.allCases {
            let snapshot = try await api.textSnapshot(for: TextEditTarget(collection: collection, id: 101), field: .comments)
            for value in ["## Réseau\n\n**Markdown** 🌍", ""] {
                let updated = try await api.updateText(snapshot, to: "  " + value + "\n")
                XCTAssertEqual(updated.object.comments, value)
                XCTAssertEqual(updated.object.description, "Original")
                XCTAssertEqual(updated.object.dnsName, "host.example.test")
            }
        }
        await api.close()
    }
    func testDNSNormalizationClearingAndExactPayload() async throws {
        let api = try client()
        let target = TextEditTarget(collection: .ipAddresses, id: 101)
        let model = TextEditModel(client: api, target: target, field: .dnsName)
        await model.load()
        model.draft = " HOST.EXAMPLE.TEST "; XCTAssertFalse(model.canSave)
        model.draft = "bad name"; XCTAssertFalse(model.canSave)
        model.draft = " New_Host.EXAMPLE.TEST. "; XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.proposedValue, "new_host.example.test.")
        await model.save(); XCTAssertTrue(model.saved)
        XCTAssertEqual(model.snapshot?.object.dnsName, "new_host.example.test.")
        XCTAssertEqual(model.snapshot?.object.description, "Original")
        let snapshot = try await api.textSnapshot(for: target, field: .dnsName)
        let cleared = try await api.updateText(snapshot, to: "")
        XCTAssertEqual(cleared.object.dnsName, "")
        await api.close()
    }
    func testDNSWhitelistAndMissingFieldsFailClosed() async throws {
        let api = try client()
        do { _ = try await api.textSnapshot(for: target, field: .dnsName); XCTFail("Unsupported collection") }
        catch { XCTAssertEqual(error as? APIError, .invalidURL) }
        await api.close()
        let missing = try client("missingfield")
        do { _ = try await missing.textSnapshot(for: target, field: .comments); XCTFail("Missing field") }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        await missing.close()
    }
    func testDNSValidatorAndCommentScalarLimit() throws {
        for value in ["", "host", "*.example.test", "_srv.example.test.", "xn--rseau-bsa.test"] { XCTAssertNoThrow(try EditableTextField.dnsName.validate(value)) }
        for value in ["bad name", "é.test", "host..test", "host.*.test", "https://host", "host\n.test"] { XCTAssertThrowsError(try EditableTextField.dnsName.validate(value)) }
        XCTAssertNoThrow(try EditableTextField.comments.validate(String(repeating: "a", count: 10000)))
        XCTAssertThrowsError(try EditableTextField.comments.validate(String(repeating: "e\u{301}", count: 5001)))
        XCTAssertThrowsError(try EditableTextField.dnsName.validate(String(repeating: "a", count: 256)))
    }
    func testCommentsConflictKeepsMarkdownDraft() async throws {
        let api = try client("conflict")
        let model = TextEditModel(client: api, target: target, field: .comments)
        await model.load(); model.draft = "## Draft\n\nPreserved"
        await model.save(); XCTAssertTrue(model.requiresReload); XCTAssertFalse(model.saved)
        await model.load(); XCTAssertEqual(model.draft, "## Draft\n\nPreserved")
        XCTAssertTrue(model.canSave); await api.close()
    }
    func testFrenchCatalogHasEveryEnglishTranslationAndStableFormatPlaceholders() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "fr"))
        let data = try Data(contentsOf: url)
        let strings = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        let englishURL = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let english = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: englishURL), format: nil) as? [String: String])
        XCTAssertEqual(Set(strings.keys), Set(english.keys))
        for (key, value) in strings {
            XCTAssertFalse(value.isEmpty, key)
            XCTAssertEqual(key.components(separatedBy: "%ld").count, value.components(separatedBy: "%ld").count, key)
            XCTAssertEqual(key.components(separatedBy: "%@").count, value.components(separatedBy: "%@").count, key)
        }
        XCTAssertEqual(strings["Edit description"], "Modifier la description")
        XCTAssertEqual(strings["Devices"], "Équipements")
        XCTAssertTrue(strings["%ld loaded · %ld total"]?.contains("%ld") == true)
    }
    func testInventoryNameAndStatusAreConfinedToDeviceAndVMCollections() async throws {
        let api = try client()
        for collection in TextEditTarget.Collection.allCases {
            for field in [EditableTextField.name, .status] {
                let target = TextEditTarget(collection: collection, id: 101)
                if field.supports(collection) {
                    let snapshot = try await api.textSnapshot(for: target, field: field)
                    let result = try await api.updateText(snapshot, to: field == .name ? "  réseau-01  " : collection == .vlans ? "reserved" : "offline")
                    XCTAssertEqual(result.object.value(for: field), field == .name ? "réseau-01" : collection == .vlans ? "reserved" : "offline")
                    XCTAssertEqual(result.object.description, "Original")
                    XCTAssertEqual(result.object.comments, "Original comments")
                } else {
                    do { _ = try await api.textSnapshot(for: target, field: field); XCTFail("Unsupported field target") }
                    catch { XCTAssertEqual(error as? APIError, .invalidURL) }
                }
            }
        }
        await api.close()
    }
    func testNamesDistinguishMissingAndNullAndOnlyDevicesCanBeUnnamed() async throws {
        let device = TextEditTarget(collection: .devices, id: 101)
        let api = try client()
        let snapshot = try await api.textSnapshot(for: device, field: .name)
        let result = try await api.updateText(snapshot, to: "  ")
        XCTAssertNil(result.object.name)
        XCTAssertEqual(result.object.value(for: .name), "")
        await api.close()
        for scenario in ["missingname", "nullname"] {
            let api = try client(scenario)
            if scenario == "missingname" {
                do { _ = try await api.textSnapshot(for: device, field: .name); XCTFail("Missing field") }
                catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
            } else {
                let model = TextEditModel(client: api, target: device, field: .name)
                await model.load(); XCTAssertNil(model.errorMessage); XCTAssertFalse(model.canSave)
                model.draft = "named-device"; XCTAssertTrue(model.canSave)
                await model.save(); XCTAssertTrue(model.saved)
            }
            await api.close()
        }
        XCTAssertThrowsError(try EditableTextField.name.validate("", for: .virtualMachines))
        XCTAssertNoThrow(try EditableTextField.name.validate("", for: .devices))
    }
    func testNameLengthControlCharactersAndVMStatusChoices() throws {
        XCTAssertNoThrow(try EditableTextField.name.validate(String(repeating: "é", count: 64), for: .devices))
        for value in [String(repeating: "e\u{301}", count: 33), "bad\nname", "bad\tname", "bad\u{0}name"] {
            XCTAssertThrowsError(try EditableTextField.name.validate(value, for: .devices))
        }
        XCTAssertNoThrow(try EditableTextField.status.validate("paused", for: .virtualMachines))
        XCTAssertThrowsError(try EditableTextField.status.validate("paused", for: .devices))
        XCTAssertNoThrow(try EditableTextField.status.validate("inventory", for: .devices))
        for value in ["inventory", "", "invented", "Active"] {
            XCTAssertThrowsError(try EditableTextField.status.validate(value, for: .virtualMachines))
        }
        let data = try JSONEncoder().encode(TextEditPayload(field: .name, value: ""))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["name"]); XCTAssertTrue(object["name"] is NSNull)
    }
    func testStatusMissingFieldMismatchedValueAndConflictFailSafely() async throws {
        let target = TextEditTarget(collection: .virtualMachines, id: 101)
        let missing = try client("missingstatus")
        do { _ = try await missing.textSnapshot(for: target, field: .status); XCTFail("Missing status") }
        catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        await missing.close()
        for scenario in ["wrongvalue", "conflict", "forbidden", "lost"] {
            let api = try client(scenario)
            let model = TextEditModel(client: api, target: target, field: .status)
            await model.load(); XCTAssertFalse(model.canSave)
            model.draft = "paused"; XCTAssertTrue(model.canSave)
            await model.save()
            XCTAssertFalse(model.saved); XCTAssertTrue(model.requiresReload)
            XCTAssertEqual(model.draft, "paused"); XCTAssertFalse(model.canSave)
            await model.save(); XCTAssertTrue(model.requiresReload)
            await api.close()
        }
    }
    func testSyntheticInventoryNameAndStatusPreserveRelationships() throws {
        let fixture = FixtureDescriptions()
        for (collection, id) in [(TextEditTarget.Collection.devices, 301), (.virtualMachines, 401)] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: "https://example.test/api/" + collection.rawValue + "\(id)/")))
            let originalReply = try XCTUnwrap(InventoryFixture.response(try XCTUnwrap(request.url)))
            let original = try JSONDecoder().decode(InventoryObject.self, from: Data(originalReply.1.utf8))
            request.httpMethod = "PATCH"; request.setValue("W/\"fixture-1\"", forHTTPHeaderField: "If-Match")
            for (field, value) in [(EditableTextField.name, "new-name"), (.status, "offline")] {
                request.httpBody = try JSONEncoder().encode(TextEditPayload(field: field, value: value))
                let reply = try XCTUnwrap(fixture.response(request)); XCTAssertEqual(reply.0, 200)
                let object = try JSONDecoder().decode(InventoryObject.self, from: Data(reply.1.utf8))
                XCTAssertEqual(object.name, "new-name"); XCTAssertEqual(object.id, id)
                XCTAssertEqual(object.site?.id, original.site?.id)
                XCTAssertEqual(object.description, "Example inventory")
                XCTAssertEqual(object.rack?.id, original.rack?.id)
                XCTAssertEqual(object.device?.id, original.device?.id)
                XCTAssertEqual(object.cluster?.id, original.cluster?.id)
            }
        }
    }
}

private final class EditProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = url.host?.components(separatedBy: ".").first ?? "success"
        let patch = request.httpMethod == "PATCH"
        var status = 200
        var body: [String: Any] = ["id": scenario == "wrongid" ? 999 : 101, "display": "Example Paris", "name": "Original-name", "status": ["value": "active", "label": "Active"], "description": "Original", "comments": "Original comments", "dns_name": "host.example.test"]
        if scenario == "missingfield" { body.removeValue(forKey: "comments") }
        if scenario == "missingname" { body.removeValue(forKey: "name") }
        if scenario == "missingstatus" { body.removeValue(forKey: "status") }
        if scenario == "nullname" { body["name"] = NSNull() }
        if patch {
            guard request.value(forHTTPHeaderField: "If-Match") == "W/\"revision-1\"",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let data = requestBody(request), let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  value.count == 1, let entry = value.first, ["description", "comments", "dns_name", "name", "status"].contains(entry.key) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            if scenario == "lost" { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
            status = scenario == "forbidden" ? 403 : scenario == "conflict" ? 412 : 200
            if entry.key == "name" || entry.key == "status" {
                guard url.path.contains("/dcim/devices/") || url.path.contains("/virtualization/virtual-machines/") || url.path.contains("/ipam/vlans/") || (entry.key == "name" && url.path.contains("/ipam/vlan-groups/")) else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
                }
            }
            if entry.key == "status" {
                body["status"] = ["value": scenario == "wrongvalue" ? "active" : entry.value, "label": "Status"]
            } else { body[entry.key] = entry.value }
            if scenario == "wrongreply" { body["id"] = 999 }
        }
        var headers = ["Content-Type": "application/json"]
        if scenario != "missing" { headers["ETag"] = url.query == nil ? "W/\"revision-1\"" : "W/\"revision-2\"" }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
