import XCTest

final class MNetBoxUITests: XCTestCase {
    @MainActor private func contextApp(_ kind: String, forbidden: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        if forbidden { app.launchArguments.append("--ui-testing-context-forbidden") }
        app.launch()
        let tab = ["vrfs", "tenants", "roles"].contains(kind) ? "IPAM" : "Inventory"
        app.tabBars.buttons[tab].tap()
        let entry = app.buttons["contextCategory-\(kind)"]
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        return app
    }

    @MainActor func testAppInformationVersionAndSafeDiagnostic() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch(); app.buttons["appInformation"].tap()
        let version = app.descendants(matching: .any)["netBoxServerVersion"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5)); XCTAssertEqual(version.value as? String, "4.7.2")
        let report = app.staticTexts["supportReport"]
        for _ in 0..<6 where !report.isHittable { app.swipeUp() }
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("MNetBox 0.15.0 (build 33)"))
        XCTAssertTrue(report.label.contains("NetBox 4.7.2"))
        XCTAssertFalse(report.label.contains("example.test")); XCTAssertFalse(report.label.contains("test-placeholder")); XCTAssertFalse(report.label.contains("fixture-user"))
        XCTAssertTrue(app.buttons["shareDiagnostics"].exists)
        attach(app, name: "App information and redacted diagnostic")
    }

    @MainActor func testVRFDirectorySeparatesSameNamesAndLinksOverlappingPrefixes() {
        let app = contextApp("vrfs")
        XCTAssertTrue(app.buttons["contextObject-vrfs-7"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["contextObject-vrfs-8"].exists)
        app.buttons["contextLoadMore"].tap()
        XCTAssertTrue(app.buttons["contextObject-vrfs-9"].waitForExistence(timeout: 5))
        app.buttons["contextObject-vrfs-7"].tap()
        XCTAssertTrue(app.buttons["contextIPAM-prefixes"].waitForExistence(timeout: 5)); app.buttons["contextIPAM-prefixes"].tap()
        XCTAssertTrue(app.buttons["ipamObject-5"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ipamObject-1"].exists)
        app.swipeUp(); app.buttons["ipamObject-5"].tap()
        XCTAssertTrue(app.buttons["ipamVRF"].waitForExistence(timeout: 5)); app.buttons["ipamVRF"].tap()
        XCTAssertTrue(app.staticTexts["contextDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contextDetailTitle"].label, "Blue")
    }

    @MainActor func testVLANClusterScopeOpensVMInventoryAndBackLinks() {
        let app = openVLANs("groups")
        let group = app.buttons["vlanObject-groups-33"]
        XCTAssertTrue(group.waitForExistence(timeout: 5)); app.swipeUp(); group.tap()
        let scope = app.buttons["objectScope"]
        for _ in 0..<5 where !scope.isHittable { app.swipeUp() }
        XCTAssertTrue(scope.waitForExistence(timeout: 5)); scope.tap()
        XCTAssertTrue(app.buttons["contextInventory-virtualMachines"].waitForExistence(timeout: 5)); app.buttons["contextInventory-virtualMachines"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-401"].waitForExistence(timeout: 5)); app.buttons["inventoryObject-401"].tap()
        XCTAssertTrue(app.buttons["inventoryCluster"].waitForExistence(timeout: 5)); app.buttons["inventoryCluster"].tap()
        XCTAssertTrue(app.staticTexts["contextDetailTitle"].waitForExistence(timeout: 5))
    }

    @MainActor func testLocationAncestorOpensDescendantRacksAndLocation() {
        let app = contextApp("locations")
        XCTAssertTrue(app.buttons["contextObject-locations-61"].waitForExistence(timeout: 5)); app.buttons["contextObject-locations-61"].tap()
        app.buttons["contextInventory-racks"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-201"].waitForExistence(timeout: 5)); app.buttons["inventoryObject-201"].tap()
        XCTAssertTrue(app.buttons["inventoryLocation"].waitForExistence(timeout: 5)); app.buttons["inventoryLocation"].tap()
        XCTAssertTrue(app.buttons["contextParent"].waitForExistence(timeout: 5)); app.buttons["contextParent"].tap()
        XCTAssertTrue(app.staticTexts["contextDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["contextDetailTitle"].label, "DC1")
        attach(app, name: "Location hierarchy")
    }

    @MainActor func testForbiddenTenantsDoNotBlockClusterBrowsing() {
        let app = contextApp("tenants", forbidden: true)
        XCTAssertTrue(app.staticTexts["Your token was rejected or does not have permission for this request."].waitForExistence(timeout: 5))
        app.tabBars.buttons["Inventory"].tap()
        let cluster = app.buttons["contextCategory-clusters"]
        for _ in 0..<5 where !cluster.isHittable { app.swipeUp() }
        cluster.tap()
        XCTAssertTrue(app.buttons["contextObject-clusters-9"].waitForExistence(timeout: 5)); app.buttons["contextObject-clusters-9"].tap()
        XCTAssertTrue(app.buttons["contextInventory-virtualMachines"].waitForExistence(timeout: 5))
    }

    @MainActor func testGlobalSearchIncludesVRFContexts() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch(); app.tabBars.buttons["Search"].tap()
        let input = app.searchFields["Search all NetBox"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Blue\n")
        let result = app.buttons["global-context-vrfs-7"]
        for _ in 0..<12 where !result.isHittable { app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
        XCTAssertTrue(app.staticTexts["contextDetailTitle"].waitForExistence(timeout: 5))
    }

    @MainActor func testFrenchInformationAndContextNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "--ui-testing-dashboard"]
        app.launch(); app.buttons["appInformation"].tap()
        XCTAssertTrue(app.navigationBars["Informations sur l’app"].waitForExistence(timeout: 5))
        app.tabBars.buttons["IPAM"].tap()
        let link = app.buttons["contextCategory-vrfs"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.buttons["contextObject-vrfs-7"].waitForExistence(timeout: 5))
    }

    @MainActor func testFreshConnectionHasNoProductionServerAndOfflineInfo() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-empty-connection"]
        app.launch()
        let field = app.textFields["serverURL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(["", "HTTPS URL"].contains((field.value as? String) ?? ""))
        let info = app.buttons["appInformation"]
        for _ in 0..<5 where !info.isHittable { app.swipeUp() }
        info.tap()
        XCTAssertTrue(app.navigationBars["App information"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["checkServerVersion"].exists)
    }

    @MainActor private func openVLANs(_ category: String = "vlans") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["IPAM"].waitForExistence(timeout: 5))
        app.tabBars.buttons["IPAM"].tap()
        app.buttons["ipamCategory-\(category)"].tap()
        return app
    }

    @MainActor func testVLANBrowsingLinkedPrefixesAndInterfaces() {
        let app = openVLANs()
        let vlan = app.buttons["vlanObject-vlans-1"]
        XCTAssertTrue(vlan.waitForExistence(timeout: 5)); app.swipeUp(); vlan.tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
        app.swipeUp(); app.buttons["vlanPrefixes"].tap()
        XCTAssertTrue(app.buttons["ipamObject-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["createIPAM"].exists)
        app.swipeUp(); app.buttons["ipamObject-1"].tap()
        XCTAssertTrue(app.buttons["prefixVLAN"].waitForExistence(timeout: 5))
        app.buttons["prefixVLAN"].tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
        app.swipeUp(); app.buttons["vlanInterfaces-dcim.interface"].tap()
        XCTAssertTrue(app.buttons["interface-503"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["newInterface"].exists)
        app.buttons["interface-503"].tap()
        XCTAssertTrue(app.buttons["interfaceVLAN-1"].waitForExistence(timeout: 5))
        app.buttons["interfaceVLAN-1"].tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
        attach(app, name: "VLAN linked browsing")
    }

    @MainActor func testVLANGroupScopeAndReusedVID() {
        let app = openVLANs("groups")
        let group = app.buttons["vlanObject-groups-33"]
        XCTAssertTrue(group.waitForExistence(timeout: 5)); app.swipeUp(); group.tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS %@", "virtualization.cluster")).firstMatch.exists)
        app.swipeUp(); app.buttons["groupVLANs"].tap()
        XCTAssertTrue(app.buttons["vlanObject-vlans-24"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vlanObject-vlans-22"].exists)
        app.swipeUp(); app.buttons["vlanObject-vlans-24"].tap()
        reveal(app.buttons["vlanGroup"], in: app)
        app.buttons["vlanGroup"].tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
    }

    @MainActor func testVLANNoDirectSiteFilterAndPagination() {
        let app = openVLANs()
        app.buttons["vlanFilter-Site"].tap()
        XCTAssertTrue(app.buttons["No direct site"].waitForExistence(timeout: 5))
        app.buttons["No direct site"].tap()
        let first = app.buttons["vlanObject-vlans-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); app.swipeUp()
        XCTAssertTrue(app.buttons["vlanLoadMore"].waitForExistence(timeout: 5))
        app.buttons["vlanLoadMore"].tap()
        XCTAssertTrue(app.buttons["vlanObject-vlans-24"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vlanObject-vlans-22"].exists)
        attach(app, name: "No direct site includes cluster scoped VLAN")
    }

    @MainActor func testGlobalSearchOpensVLANGroupAndVLAN() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let input = app.searchFields["Search all NetBox"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Cluster\n")
        let group = app.buttons["global-vlan-groups-33"]
        for _ in 0..<7 where !group.isHittable { app.swipeUp() }
        XCTAssertTrue(group.waitForExistence(timeout: 10)); group.tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Cluster\n")
        let vlan = app.buttons["global-vlan-vlans-24"]
        for _ in 0..<7 where !vlan.isHittable { app.swipeUp() }
        XCTAssertTrue(vlan.waitForExistence(timeout: 10)); vlan.tap()
        XCTAssertTrue(app.staticTexts["vlanDetailTitle"].waitForExistence(timeout: 5))
    }

    @MainActor func testVLANVirtualInterfacesLinkAndEditCancel() {
        let app = openVLANs()
        let vlan = app.buttons["vlanObject-vlans-1"]
        XCTAssertTrue(vlan.waitForExistence(timeout: 5)); app.swipeUp(); vlan.tap()
        app.swipeUp(); app.buttons["vlanInterfaces-virtualization.vminterface"].tap()
        XCTAssertTrue(app.buttons["interface-803"].waitForExistence(timeout: 5)); app.buttons["interface-803"].tap()
        XCTAssertTrue(app.buttons["interfaceVLAN-1"].waitForExistence(timeout: 5))
        app.buttons["editInterface"].tap(); app.buttons["editInterfaceName"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5)); app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["interfaceTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["interfaceTitle"].label, "eth2")
    }

    /// Detail screens open with graphic headers and image galleries, so lists are lazily
    /// populated: scroll down, then back up, until the element is materialized.
    @MainActor @discardableResult private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> XCUIElement {
        if element.waitForExistence(timeout: 5) { return element }
        for _ in 0..<swipes { app.swipeUp(); if element.waitForExistence(timeout: 1) { return element } }
        for _ in 0..<(swipes * 2) { app.swipeDown(); if element.waitForExistence(timeout: 1) { return element } }
        XCTFail("Element not found after scrolling: \(element)")
        return element
    }

    @MainActor private func openInventory(_ kind: String, id: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        let link = app.buttons["browse-\(kind)"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.buttons["inventoryObject-\(id)"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor private func prepareDescriptionEdit(conflict: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        if conflict { app.launchArguments.append("--ui-testing-edit-conflict") }
        app.launch()
        XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        app.buttons["browse-sites"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-101"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-101"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["editObject"].tap()
        app.buttons["editDescription"].tap()
        let draft = app.descendants(matching: .any)["descriptionDraft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("mobile-test")
        app.swipeUp()
        XCTAssertTrue(app.buttons["descriptionReview"].waitForExistence(timeout: 5))
        app.buttons["descriptionReview"].tap()
        XCTAssertTrue(app.buttons["descriptionConfirm"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testDescriptionReviewSaveAndRefreshedDetail() {
        let app = prepareDescriptionEdit()
        attach(app, name: "Description change preview")
        app.buttons["descriptionConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["descriptionSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        app.swipeUp()
        let description = reveal(app.buttons["inventoryField-Description"], in: app)
        XCTAssertTrue((description.value as? String)?.contains("mobile-test") == true)
    }

    @MainActor func testDescriptionCancelLeavesServerValueUnchanged() {
        let app = prepareDescriptionEdit()
        app.buttons["Cancel"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        app.buttons["editObject"].tap()
        app.buttons["editDescription"].tap()
        let draft = app.descendants(matching: .any)["descriptionDraft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertFalse((draft.value as? String)?.contains("mobile-test") == true)
        XCTAssertFalse(app.buttons["descriptionReview"].isEnabled)
    }

    @MainActor func testDescriptionConflictPreservesDraftAndRequiresReload() {
        let app = prepareDescriptionEdit(conflict: true)
        app.buttons["descriptionConfirm"].tap()
        XCTAssertTrue(app.buttons["descriptionReload"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["descriptionReview"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["descriptionSaved"].firstMatch.exists)
        app.buttons["descriptionReload"].tap()
        XCTAssertTrue(app.buttons["descriptionReview"].isEnabled)
        let draft = app.descendants(matching: .any)["descriptionDraft"].firstMatch
        XCTAssertTrue((draft.value as? String)?.contains("mobile-test") == true)
    }

    @MainActor private func openCreation(_ kind: String = "prefixes", argument: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        if let argument { app.launchArguments.append(argument) }
        app.launch()
        XCTAssertTrue(app.buttons["browse-\(kind)"].waitForExistence(timeout: 5))
        app.buttons["browse-\(kind)"].tap()
        XCTAssertTrue(app.buttons["createIPAM"].waitForExistence(timeout: 5))
        app.buttons["createIPAM"].tap()
        XCTAssertTrue(app.textFields["creationCIDR"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func creationReviewButton(_ app: XCUIApplication) -> XCUIElement {
        if app.buttons["dismissCreationKeyboard"].exists { app.buttons["dismissCreationKeyboard"].tap() }
        let review = app.buttons["reviewIPAMCreation"]
        for _ in 0..<3 {
            if review.exists && review.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        return review
    }
    @MainActor private func reviewCreation(_ app: XCUIApplication) {
        let review = creationReviewButton(app)
        XCTAssertTrue(review.isEnabled)
        review.tap()
        XCTAssertTrue(app.buttons["confirmIPAMCreation"].waitForExistence(timeout: 5))
    }
    @MainActor private func existingObjectsButton(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["checkExistingIPAM"]
        for _ in 0..<3 {
            if button.exists && button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        return button
    }
    @MainActor func testCreateIPv4PrefixReviewAndRefreshedListDetail() {
        let app = openCreation()
        let cidr = app.textFields["creationCIDR"]
        cidr.tap(); cidr.typeText("203.0.113.0/24")
        reviewCreation(app)
        XCTAssertEqual(app.descendants(matching: .any)["creationCIDRPreview"].value as? String, "203.0.113.0/24")
        attach(app, name: "Prefix creation review")
        app.buttons["confirmIPAMCreation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ipamCreated"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["createIPAM"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("203.0.113.0/24")
        XCTAssertTrue(app.buttons["ipamObject-9001"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-9001"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "203.0.113.0/24")
    }
    @MainActor func testCreateIPv6IPWithVRFTenantAndDNS() {
        let app = openCreation("ipAddresses")
        let cidr = app.textFields["creationCIDR"]
        cidr.tap(); cidr.typeText("2001:0DB8:BEEF::42/64")
        app.buttons["dismissCreationKeyboard"].tap()
        app.buttons["creation-VRF"].tap()
        XCTAssertTrue(app.buttons["reference-7"].waitForExistence(timeout: 5))
        app.buttons["reference-7"].tap()
        app.buttons["creation-Tenant"].tap()
        XCTAssertTrue(app.buttons["reference-1"].waitForExistence(timeout: 5))
        app.buttons["reference-1"].tap()
        let dns = app.textFields["creationDNSName"]
        dns.tap(); dns.typeText("HOST.EXAMPLE.TEST")
        reviewCreation(app)
        XCTAssertEqual(app.descendants(matching: .any)["creationCIDRPreview"].value as? String, "2001:db8:beef::42/64")
        attach(app, name: "IPv6 IP creation review")
        app.buttons["confirmIPAMCreation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ipamCreated"].waitForExistence(timeout: 5))
        app.buttons["openCreatedIPAM"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "2001:db8:beef::42/64")
        app.swipeUp()
        XCTAssertEqual(app.buttons["ipamDNSName"].value as? String, "host.example.test")
    }
    @MainActor func testCreationInvalidNetworkAndCancelAfterReview() {
        let app = openCreation()
        let cidr = app.textFields["creationCIDR"]
        cidr.tap(); cidr.typeText("192.0.2.10/24")
        XCTAssertFalse(creationReviewButton(app).isEnabled)
        app.swipeDown()
        cidr.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        cidr.typeText("203.0.113.0/24")
        reviewCreation(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["createIPAM"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("203.0.113.0/24")
        XCTAssertTrue(app.buttons["ipamObject-1"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ipamObject-9001"].exists)
    }
    @MainActor func testCreationDuplicateBlocksConfirmation() {
        let app = openCreation()
        let cidr = app.textFields["creationCIDR"]
        cidr.tap(); cidr.typeText("192.0.2.0/24")
        if app.buttons["dismissCreationKeyboard"].exists { app.buttons["dismissCreationKeyboard"].tap() }
        app.swipeUp(); app.buttons["reviewIPAMCreation"].tap()
        let existing = existingObjectsButton(app)
        XCTAssertFalse(app.buttons["confirmIPAMCreation"].exists)
        existing.tap()
        var visible: XCUIElement?
        for _ in 0..<3 {
            visible = app.buttons.matching(identifier: "ipamObject-1").allElementsBoundByIndex.first(where: { $0.isHittable })
            if visible != nil { break }
            app.swipeUp()
        }
        XCTAssertNotNil(visible)
        visible?.tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "192.0.2.0/24")
        XCTAssertFalse(app.buttons["createIPAM"].isHittable)
    }
    @MainActor func testCreationUncertainReplyCanBeCheckedWithoutRetry() {
        let app = openCreation(argument: "--ui-testing-create-uncertain")
        let cidr = app.textFields["creationCIDR"]
        cidr.tap(); cidr.typeText("203.0.113.0/24")
        reviewCreation(app)
        app.buttons["confirmIPAMCreation"].tap()
        let existing = existingObjectsButton(app)
        XCTAssertFalse(app.buttons["confirmIPAMCreation"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["ipamCreated"].exists)
        existing.tap()
        XCTAssertTrue(app.buttons["ipamObject-9001"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-9001"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "203.0.113.0/24")
    }

    @MainActor func testBottomNavigationAcrossDeepDetailsAndReturnHome() {
        let app = openInventory("sites", id: 101)
        app.buttons["inventoryObject-101"].tap()
        reveal(app.buttons["related-racks"], in: app)
        app.buttons["related-racks"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-201"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-201"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.buttons["Inventory"].exists)
        tabs.buttons["IPAM"].tap()
        XCTAssertTrue(app.buttons["ipamCategory-ipAddresses"].waitForExistence(timeout: 5))
        app.buttons["ipamCategory-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-11"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        tabs.buttons["Inventory"].tap()
        XCTAssertTrue(app.buttons["inventoryCategory-devices"].waitForExistence(timeout: 5))
        app.buttons["inventoryCategory-devices"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-301"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-301"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        tabs.buttons["IPAM"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "192.0.2.10/24")
        tabs.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        app.buttons["browse-sites"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-101"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-101"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        tabs.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        attach(app, name: "Bottom navigation home")
    }

    @MainActor func testCommentsReviewSaveAndPreservedDescription() {
        let app = openInventory("sites", id: 101)
        app.buttons["inventoryObject-101"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["editObject"].tap(); app.buttons["editComments"].tap()
        let draft = app.descendants(matching: .any)["commentsDraft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(); draft.typeText("\n## mobile-comments\n\nMultiline notes\n")
        let expected = (draft.value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(expected.contains("mobile-comments"))
        XCTAssertTrue(expected.contains("\n\n"))
        app.swipeUp(); app.buttons["commentsReview"].tap()
        XCTAssertTrue(app.buttons["commentsConfirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[expected].exists)
        attach(app, name: "Comments preview")
        app.buttons["commentsConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["commentsSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["editObject"].tap(); app.buttons["editComments"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, expected)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["editObject"].tap(); app.buttons["editDescription"].tap()
        let description = app.descendants(matching: .any)["descriptionDraft"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertEqual(description.value as? String, "Example inventory")
    }
    @MainActor func testDNSValidationNormalizationSaveAndRefreshedDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-ipAddresses"].waitForExistence(timeout: 5))
        app.buttons["browse-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-11"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["ipamDNSName"].tap()
        let draft = app.descendants(matching: .any)["dns_nameDraft"].firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue)
        draft.typeText("bad name")
        XCTAssertFalse(app.buttons["dns_nameReview"].isEnabled)
        draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "bad name".count))
        draft.typeText("NEW.EXAMPLE.TEST")
        app.swipeUp(); app.buttons["dns_nameReview"].tap()
        XCTAssertTrue(app.staticTexts["new.example.test"].exists)
        attach(app, name: "DNS lowercase preview")
        app.buttons["dns_nameConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["dns_nameSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "192.0.2.10/24")
        app.swipeUp()
        XCTAssertEqual(app.buttons["ipamDNSName"].value as? String, "new.example.test")
    }

    @MainActor func testFrenchDashboardAndLargeDarkDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR", "--ui-testing-dashboard", "--ui-testing-large-text", "--ui-testing-dark"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connecté à NetBox"].exists)
        XCTAssertTrue(app.navigationBars["Tableau de bord"].exists)
        attach(app, name: "French large-text dark dashboard")
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let report = XCTAttachment(string: issue.element?.debugDescription ?? "Issue has no exposed accessibility element")
            report.name = "Accessibility issue element (synthetic data)"; report.lifetime = .keepAlways
            self.add(report)
            return false
        }
        app.buttons["browse-sites"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-101"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-101"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertTrue(app.buttons["editObject"].exists)
        app.swipeUp()
        attach(app, name: "French large-text dark site detail")
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            let report = XCTAttachment(string: issue.element?.debugDescription ?? "Issue has no exposed accessibility element")
            report.name = "Accessibility issue element (synthetic data)"; report.lifetime = .keepAlways
            self.add(report)
            return false
        }
    }

    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name + " (synthetic data)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testDeviceInterfacesCableAndAssignedIP() {
        let app = openInventory("devices", id: 301)
        app.buttons["inventoryObject-301"].tap()
        reveal(app.buttons["related-interfaces"], in: app)
        app.buttons["related-interfaces"].tap()
        XCTAssertTrue(app.buttons["interface-501"].waitForExistence(timeout: 5))
        app.buttons["interfaceLoadMore"].tap()
        XCTAssertTrue(app.buttons["interface-503"].waitForExistence(timeout: 5))
        app.buttons["interface-501"].tap()
        XCTAssertTrue(app.buttons["interfaceCable"].waitForExistence(timeout: 5))
        attach(app, name: "Physical interface")
        app.buttons["interfaceCable"].tap()
        XCTAssertTrue(app.staticTexts["cableTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cableTitle"].label, "Uplink-A")
        attach(app, name: "Cable multiple terminations")
        app.buttons["cableTermination-0-501"].tap()
        XCTAssertTrue(app.buttons["interfaceIPs"].waitForExistence(timeout: 5))
        app.buttons["interfaceIPs"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-11"].tap()
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForExistence(timeout: 5))
        for _ in 0..<3 { if app.buttons["ipAssignedInterface"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForExistence(timeout: 5)); app.buttons["ipAssignedInterface"].tap()
        XCTAssertTrue(app.buttons["interfaceParent"].waitForExistence(timeout: 5))
    }

    @MainActor func testVMInterfacesAndIPv6Assignment() {
        let app = openInventory("virtualMachines", id: 401)
        app.buttons["inventoryObject-401"].tap()
        reveal(app.buttons["related-interfaces"], in: app)
        app.buttons["related-interfaces"].tap()
        XCTAssertTrue(app.buttons["interface-801"].waitForExistence(timeout: 5))
        app.buttons["interface-801"].tap()
        XCTAssertTrue(app.buttons["interfaceIPs"].waitForExistence(timeout: 5))
        app.buttons["interfaceIPs"].tap()
        XCTAssertTrue(app.buttons["ipamObject-12"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-12"].tap()
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForExistence(timeout: 5))
        for _ in 0..<3 { if app.buttons["ipAssignedInterface"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForExistence(timeout: 5)); app.buttons["ipAssignedInterface"].tap()
        XCTAssertTrue(app.buttons["interfaceParent"].waitForExistence(timeout: 5))
        app.buttons["interfaceParent"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "monitoring-01")
    }

    @MainActor func testPrefixChildrenRemainInGlobalVRF() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-prefixes"].waitForExistence(timeout: 5))
        app.buttons["browse-prefixes"].tap()
        XCTAssertTrue(app.buttons["ipamObject-1"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-1"].tap()
        XCTAssertTrue(app.buttons["prefixChildren"].waitForExistence(timeout: 5))
        app.buttons["prefixChildren"].tap()
        XCTAssertTrue(app.buttons["ipamObject-4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ipamObject-6"].exists)
        attach(app, name: "Global VRF contained prefixes")
    }

    @MainActor func testVRFFilterAndNamedVRFContainedAddresses() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-prefixes"].waitForExistence(timeout: 5))
        app.buttons["browse-prefixes"].tap()
        XCTAssertTrue(app.buttons["More filters"].waitForExistence(timeout: 5))
        app.buttons["More filters"].tap()
        app.buttons["filter-VRF"].tap()
        XCTAssertTrue(app.buttons["reference-7"].waitForExistence(timeout: 5))
        app.buttons["reference-7"].tap()
        app.buttons["More filters"].tap()
        XCTAssertTrue(app.buttons["ipamObject-5"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-5"].tap()
        XCTAssertTrue(app.buttons["prefixIPs"].waitForExistence(timeout: 5))
        app.buttons["prefixIPs"].tap()
        XCTAssertTrue(app.buttons["ipamObject-13"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ipamObject-11"].exists)
        attach(app, name: "Blue VRF contained addresses")
    }

    @MainActor func testSiteLinkedRacksAndEquipment() {
        let app = openInventory("sites", id: 101)
        app.buttons["inventoryObject-101"].tap()
        reveal(app.buttons["related-racks"], in: app)
        app.buttons["related-racks"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-201"].waitForExistence(timeout: 5))
        attach(app, name: "Site racks with illustrations")
        app.buttons["inventoryObject-201"].tap()
        reveal(app.buttons["related-devices"], in: app)
        app.buttons["related-devices"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-301"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["inventoryObject-302"].exists)
        app.buttons["inventoryObject-301"].tap()
        reveal(app.buttons["parent-racks"], in: app)
        app.buttons["parent-racks"].tap()
        XCTAssertTrue(app.buttons["rackElevation"].waitForExistence(timeout: 5))
    }

    @MainActor func testRackGraphicFacesAndDeviceNavigation() {
        let app = openInventory("racks", id: 201)
        app.buttons["inventoryObject-201"].tap()
        XCTAssertTrue(app.buttons["rackElevation"].waitForExistence(timeout: 5))
        app.buttons["rackElevation"].tap()
        let device = app.buttons["rackDevice-301-2"]
        XCTAssertTrue(device.waitForExistence(timeout: 5))
        attach(app, name: "Rack front elevation")
        app.segmentedControls["rackFace"].buttons["Rear"].tap()
        XCTAssertTrue(device.waitForNonExistence(timeout: 5))
        app.segmentedControls["rackFace"].buttons["Front"].tap()
        XCTAssertTrue(device.waitForExistence(timeout: 5))
        app.buttons["refreshRackElevation"].tap()
        XCTAssertTrue(device.waitForExistence(timeout: 5))
        device.tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "Core-switch")
    }

    @MainActor func testSitesPaginationAndDetail() {
        let app = openInventory("sites", id: 101)
        app.buttons["inventoryLoadMore"].tap()
        XCTAssertTrue(app.buttons["inventoryObject-103"].waitForExistence(timeout: 5))
        app.buttons["inventoryObject-101"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "Example Paris")
        attach(app, name: "Site detail")
    }

    @MainActor func testRacksListAndDetail() {
        let app = openInventory("racks", id: 201)
        attach(app, name: "Rack list")
        app.buttons["inventoryObject-201"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "Rack-A")
        app.swipeUp()
        let height = app.descendants(matching: .any)["inventoryField-Height (U)"]
        XCTAssertTrue(height.waitForExistence(timeout: 5))
        XCTAssertEqual(height.value as? String, "42")
    }

    @MainActor func testDevicesSearchAndDetail() {
        let app = openInventory("devices", id: 301)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Core")
        XCTAssertTrue(app.buttons["inventoryObject-302"].waitForNonExistence(timeout: 5))
        app.buttons["inventoryObject-301"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "Core-switch")
        attach(app, name: "Device detail")
    }

    @MainActor func testVirtualMachinesDetailAndRefresh() {
        let app = openInventory("virtualMachines", id: 401)
        app.buttons["inventoryObject-401"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "monitoring-01")
        app.buttons["refreshInventoryDetail"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        app.swipeUp()
        let cpu = app.descendants(matching: .any)["inventoryField-vCPUs"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
        XCTAssertEqual(cpu.value as? String, "1.50")
        attach(app, name: "VM resources")
    }

    @MainActor func testPrefixPaginationAndDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-prefixes"].waitForExistence(timeout: 5))
        app.buttons["browse-prefixes"].tap()
        XCTAssertTrue(app.buttons["ipamObject-1"].waitForExistence(timeout: 5))
        let listScreenshot = XCTAttachment(screenshot: app.screenshot())
        listScreenshot.name = "Prefix list (synthetic data)"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)
        app.buttons["ipamLoadMore"].tap()
        XCTAssertTrue(app.buttons["ipamObject-3"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-1"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "192.0.2.0/24")
        if !app.staticTexts["Documentation LAN"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Documentation LAN"].waitForExistence(timeout: 5))
        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "Prefix detail (synthetic data)"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    @MainActor func testIPAddressSearchAndDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-ipAddresses"].waitForExistence(timeout: 5))
        app.buttons["browse-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Documentation")
        XCTAssertTrue(app.buttons["ipamObject-12"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5))
        app.buttons["ipamObject-11"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "192.0.2.10/24")
        app.swipeUp()
        let dns = app.buttons["ipamDNSName"]
        XCTAssertTrue(dns.waitForExistence(timeout: 5))
        XCTAssertEqual(dns.value as? String, "host.example.test")
    }

    @MainActor func testDashboardTotalsRefreshAndDisconnect() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        XCTAssertTrue(app.staticTexts["dashboardCount-sites"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["dashboardCount-sites"].label, "2")
        XCTAssertEqual(app.staticTexts["dashboardCount-racks"].label, "4")
        XCTAssertEqual(app.staticTexts["dashboardCount-devices"].label, "12")
        XCTAssertEqual(app.staticTexts["dashboardCount-virtualMachines"].label, "8")
        XCTAssertEqual(app.staticTexts["dashboardCount-prefixes"].label, "6")
        XCTAssertEqual(app.staticTexts["dashboardCount-ipAddresses"].label, "42")
        app.buttons["refreshDashboard"].tap()
        XCTAssertTrue(app.staticTexts["dashboardCount-sites"].waitForExistence(timeout: 5))
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 5))
    }

    @MainActor func testDashboardShowsPartialPermissionError() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-forbidden"]
        app.launch()
        XCTAssertTrue(app.staticTexts["dashboardCount-sites"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["dashboardCount-prefixes"].exists)
        let error = app.staticTexts["dashboardError-prefixes"]
        XCTAssertTrue(error.exists || app.otherElements["dashboardError-prefixes"].exists)
        XCTAssertEqual(app.staticTexts["dashboardCount-ipAddresses"].label, "42")
    }

    @MainActor func testConnectionFormAndValidation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let forget = app.buttons["Forget saved connection"]
        if forget.exists { forget.tap() }
        XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["apiToken"].exists)
        XCTAssertFalse(app.buttons["connect"].isEnabled)
        let field = app.textFields["serverURL"]
        field.tap()
        if let text = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        field.typeText("http://example.test")
        app.secureTextFields["apiToken"].tap()
        app.secureTextFields["apiToken"].typeText("test-placeholder")
        app.buttons["connect"].tap()
        let connectionError = app.descendants(matching: .any)["connectionError"].firstMatch
        XCTAssertTrue(connectionError.waitForExistence(timeout: 10))
    }
    @MainActor func testGlobalSearchOpensDeviceAndPreservesNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        app.tabBars.firstMatch.buttons["Search"].tap()
        let input = app.searchFields["Search all NetBox"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("Core")
        let result = app.buttons["global-devices-301"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        app.tabBars.firstMatch.buttons["Home"].tap()
        app.tabBars.firstMatch.buttons["Search"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        app.tabBars.firstMatch.buttons["Search"].tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "Search all NetBox")
    }

    @MainActor func testGlobalSearchOpensIPAddress() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        app.tabBars.firstMatch.buttons["Search"].tap()
        let input = app.searchFields["Search all NetBox"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("192.0.2.10")
        input.typeText("\n")
        let result = app.buttons["global-ipAddresses-11"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        for _ in 0..<5 where !result.isHittable { app.swipeUp() }
        XCTAssertTrue(result.isHittable)
        result.tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
    }
    @MainActor func testDeviceNameReviewSaveAndCancel() {
        let app = openInventory("devices", id: 301)
        app.buttons["inventoryObject-301"].tap()
        app.buttons["editObject"].tap(); app.buttons["editName"].tap()
        let draft = app.textFields["nameDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.press(forDuration: 1.2)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        else {
            draft.doubleTap()
            if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        }
        draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "core-mobile\n")
        app.buttons["nameReview"].tap()
        XCTAssertTrue(app.staticTexts["core-mobile"].waitForExistence(timeout: 5))
        attach(app, name: "Device name review")
        app.buttons["nameConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["nameSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        reveal(app.staticTexts["inventoryDetailTitle"], in: app)
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "core-mobile")
        app.buttons["editObject"].tap(); app.buttons["editName"].tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["inventoryDetailTitle"].label, "core-mobile")
    }

    @MainActor func testVMStatusPausedReviewSaveAndRefreshedDetail() {
        let app = openInventory("virtualMachines", id: 401)
        app.buttons["inventoryObject-401"].tap()
        app.buttons["editObject"].tap(); app.buttons["editStatus"].tap()
        XCTAssertTrue(app.buttons["statusDraft"].waitForExistence(timeout: 5))
        app.buttons["statusDraft"].tap()
        app.buttons["Paused"].tap()
        app.buttons["statusReview"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        attach(app, name: "VM status review")
        app.buttons["statusConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["statusSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inventoryField-Status"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["inventoryField-Status"].firstMatch.value as? String, "Paused")
    }
    @MainActor private func openEditableInterface(virtual: Bool = false) -> XCUIApplication {
        let app = openInventory(virtual ? "virtualMachines" : "devices", id: virtual ? 401 : 301)
        app.buttons[virtual ? "inventoryObject-401" : "inventoryObject-301"].tap()
        app.buttons["related-interfaces"].tap()
        let link = app.buttons[virtual ? "interface-801" : "interface-501"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(app.buttons["editInterface"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func confirmStructured(_ app: XCUIApplication) {
        app.buttons["structuredReview"].tap()
        XCTAssertTrue(app.buttons["structuredConfirm"].waitForExistence(timeout: 5))
        attach(app, name: "Structured change review")
        app.buttons["structuredConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["structuredSaved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }
    @MainActor func testPhysicalInterfaceEnabledAndMTUEditsPreserveCable() {
        let app = openEditableInterface()
        app.buttons["editInterface"].tap(); app.buttons["editEnabled"].tap()
        XCTAssertTrue(app.switches["enabledDraft"].waitForExistence(timeout: 5))
        app.switches["enabledDraft"].switches.firstMatch.tap()
        XCTAssertEqual(app.switches["enabledDraft"].value as? String, "0")
        confirmStructured(app)
        XCTAssertTrue(app.descendants(matching: .any)["interfaceField-Enabled"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["interfaceField-Enabled"].firstMatch.value as? String, "No")
        app.buttons["editInterface"].tap(); app.buttons["editMTU"].tap()
        let draft = app.textFields["mtuDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap()
        draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "9000")
        app.navigationBars.buttons["Done"].tap(); confirmStructured(app)
        XCTAssertTrue(app.descendants(matching: .any)["interfaceField-MTU"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["interfaceField-MTU"].firstMatch.value as? String, "9000")
        XCTAssertTrue(app.buttons["interfaceCable"].exists)
    }
    @MainActor func testVMInterfaceClearsMTU() {
        let app = openEditableInterface(virtual: true)
        app.buttons["editInterface"].tap(); app.buttons["editMTU"].tap()
        let draft = app.textFields["mtuDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap()
        draft.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        app.navigationBars.buttons["Done"].tap(); confirmStructured(app)
        XCTAssertTrue(app.descendants(matching: .any)["interfaceField-MTU"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["interfaceField-MTU"].firstMatch.value as? String, "—")
    }
    @MainActor func testDeviceTenantRolePlatformAndTenantClearing() {
        let app = openInventory("devices", id: 301); app.buttons["inventoryObject-301"].tap()
        for (menu, reference, field, label) in [("editTenant", "reference-1", "Tenant", "Example tenant"), ("editRole", "reference-2", "Role", "Application"), ("editPlatform", "reference-2", "Platform", "RouterOS")] {
            app.buttons["editObject"].tap(); app.buttons[menu].tap()
            XCTAssertTrue(app.buttons["structuredReference"].waitForExistence(timeout: 5))
            app.buttons["structuredReference"].tap()
            XCTAssertTrue(app.buttons[reference].waitForExistence(timeout: 5))
            if menu == "editRole" { XCTAssertFalse(app.buttons["None"].exists) }
            app.buttons[reference].tap(); confirmStructured(app)
            let value = app.descendants(matching: .any)["inventoryField-" + field].firstMatch
            for _ in 0..<6 where !value.exists { app.swipeUp() }
            XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.value as? String, label)
        }
        app.buttons["editObject"].tap(); app.buttons["editTenant"].tap()
        app.buttons["structuredReference"].tap(); app.buttons["None"].tap(); confirmStructured(app)
        for _ in 0..<4 where !app.descendants(matching: .any)["inventoryField-Tenant"].firstMatch.exists { app.swipeDown() }
        XCTAssertEqual(app.descendants(matching: .any)["inventoryField-Tenant"].firstMatch.value as? String, "—")
    }
    @MainActor func testVMRolePickerOnlyShowsCompatibleRoles() {
        let app = openInventory("virtualMachines", id: 401); app.buttons["inventoryObject-401"].tap()
        app.buttons["editObject"].tap(); app.buttons["editRole"].tap()
        XCTAssertTrue(app.buttons["structuredReference"].waitForExistence(timeout: 5)); app.buttons["structuredReference"].tap()
        XCTAssertTrue(app.buttons["reference-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reference-1"].exists)
        app.buttons["reference-2"].tap(); confirmStructured(app)
        XCTAssertTrue(app.descendants(matching: .any)["inventoryField-Role"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["inventoryField-Role"].firstMatch.value as? String, "Application")
    }
    @MainActor func testCreatePhysicalInterfaceReviewAndOpen() {
        let app = openInventory("devices", id: 301); app.buttons["inventoryObject-301"].tap()
        app.buttons["related-interfaces"].tap()
        XCTAssertTrue(app.buttons["newInterface"].waitForExistence(timeout: 5)); app.buttons["newInterface"].tap()
        let name = app.textFields["interfaceCreationName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("eth9")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["reviewInterfaceCreation"].tap()
        XCTAssertTrue(app.buttons["confirmInterfaceCreation"].waitForExistence(timeout: 5)); attach(app, name: "New interface preview")
        app.buttons["confirmInterfaceCreation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["interfaceCreated"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Open created object"].tap()
        XCTAssertTrue(app.buttons["editInterface"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["eth9"].firstMatch.exists)
    }
    @MainActor private func openIPWithClearedDevicePrimary() -> XCUIApplication {
        let app = openInventory("devices", id: 301); app.buttons["inventoryObject-301"].tap()
        app.buttons["editObject"].tap(); app.buttons["editPrimaryIPv4"].tap()
        app.buttons["structuredReference"].tap(); app.buttons["None"].tap(); confirmStructured(app)
        app.tabBars.firstMatch.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["browse-ipAddresses"].waitForExistence(timeout: 5)); app.buttons["browse-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5)); app.buttons["ipamObject-11"].tap()
        return app
    }
    @MainActor func testIPAMTenantClearingAndAssignmentDetach() {
        let app = openIPWithClearedDevicePrimary()
        app.buttons["ipamField-Tenant"].tap()
        app.buttons["structuredReference"].tap(); app.buttons["None"].tap(); confirmStructured(app)
        app.buttons["ipamField-Assigned object"].tap()
        XCTAssertTrue(app.buttons["clearAssignment"].waitForExistence(timeout: 5)); app.buttons["clearAssignment"].tap(); confirmStructured(app)
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["192.0.2.10/24"].firstMatch.exists)
    }
    @MainActor func testPrimaryIPv6Clearing() {
        let app = openInventory("virtualMachines", id: 401); app.buttons["inventoryObject-401"].tap()
        app.buttons["editObject"].tap(); app.buttons["editPrimaryIPv6"].tap()
        XCTAssertTrue(app.buttons["structuredReference"].waitForExistence(timeout: 5)); app.buttons["structuredReference"].tap()
        app.buttons["None"].tap(); confirmStructured(app)
        XCTAssertTrue(app.buttons["editObject"].exists)
    }

    @MainActor func testDevicePrimaryIPv4ClearAndSelectScopedAddress() {
        let app = openInventory("devices", id: 301); app.buttons["inventoryObject-301"].tap()
        app.buttons["editObject"].tap(); app.buttons["editPrimaryIPv4"].tap()
        app.buttons["structuredReference"].tap(); app.buttons["None"].tap(); confirmStructured(app)
        app.buttons["editObject"].tap(); app.buttons["editPrimaryIPv4"].tap()
        app.buttons["structuredReference"].tap()
        XCTAssertTrue(app.buttons["reference-11"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reference-12"].exists)
        app.buttons["reference-11"].tap(); confirmStructured(app)
    }
    @MainActor func testIPAssignmentSelectsVMParentAndInterface() {
        let app = openIPWithClearedDevicePrimary()
        app.buttons["ipamField-Assigned object"].tap()
        XCTAssertTrue(app.buttons["assignmentKind"].waitForExistence(timeout: 5))
        app.buttons["assignmentKind"].tap(); app.buttons["Virtual machine"].tap()
        app.buttons["assignmentParent"].tap()
        XCTAssertTrue(app.buttons["reference-401"].waitForExistence(timeout: 5)); app.buttons["reference-401"].tap()
        app.buttons["assignmentInterface"].tap()
        XCTAssertTrue(app.buttons["reference-801"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["reference-501"].exists)
        app.buttons["reference-801"].tap(); confirmStructured(app)
        for _ in 0..<3 { if app.buttons["ipAssignedInterface"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.buttons["ipAssignedInterface"].waitForExistence(timeout: 5)); app.buttons["ipAssignedInterface"].tap()
        XCTAssertTrue(app.buttons["interfaceParent"].waitForExistence(timeout: 5))
    }
    @MainActor func testPrefixStatusContainerReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]; app.launch()
        XCTAssertTrue(app.buttons["browse-prefixes"].waitForExistence(timeout: 5)); app.buttons["browse-prefixes"].tap()
        app.buttons["ipamObject-1"].tap(); app.buttons["editObject"].tap(); app.buttons["editStatus"].tap()
        XCTAssertTrue(app.buttons["statusDraft"].waitForExistence(timeout: 5)); app.buttons["statusDraft"].tap()
        app.buttons["Container"].tap(); confirmStructured(app)
        let value = app.descendants(matching: .any)["ipamField-Status"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.value as? String, "Container")
    }


    @MainActor private func openNewPrefixForDeletion(argument: String? = nil) -> XCUIApplication {
        let app = openCreation(argument: argument)
        app.textFields["creationCIDR"].tap(); app.textFields["creationCIDR"].typeText("203.0.113.0/24")
        reviewCreation(app)
        app.buttons["confirmIPAMCreation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ipamCreated"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let search = app.searchFields.firstMatch; search.tap(); search.typeText("203.0.113.0/24")
        XCTAssertTrue(app.buttons["ipamObject-9001"].waitForExistence(timeout: 5)); app.buttons["ipamObject-9001"].tap()
        XCTAssertTrue(app.buttons["editObject"].waitForExistence(timeout: 5))
        app.buttons["editObject"].tap(); app.buttons["deleteObject"].tap()
        return app
    }
    @MainActor private func confirmDeletion(_ app: XCUIApplication, id: Int) {
        let field = app.textFields["deletionConfirmationID"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["confirmDeletion"].isEnabled)
        field.tap(); field.typeText(String(id))
        app.navigationBars.buttons["Done"].tap()
        let button = app.buttons["confirmDeletion"]
        for _ in 0..<3 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.isEnabled); button.tap()
    }
    @MainActor func testDeleteEmptyPrefixRefreshesOriginatingList() {
        let app = openNewPrefixForDeletion()
        confirmDeletion(app, id: 9001)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "203.0.113.0/24")
        XCTAssertTrue(app.buttons["ipamObject-9001"].waitForNonExistence(timeout: 8))
    }
    @MainActor func testDeleteAssignedIPIsBlockedAndCancelPreservesDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch(); app.buttons["browse-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5)); app.buttons["ipamObject-11"].tap()
        app.buttons["editObject"].tap(); app.buttons["deleteObject"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["deletionBlocked"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["confirmDeletion"].exists)
        app.buttons["Cancel"].tap()
        reveal(app.staticTexts["ipamDetailTitle"], in: app)
    }
    @MainActor func testDeleteUncertainOutcomeOnlyOffersReadCheck() {
        let app = openNewPrefixForDeletion(argument: "--ui-testing-delete-uncertain")
        confirmDeletion(app, id: 9001)
        for _ in 0..<3 { if app.buttons["checkDeletionOutcome"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["checkDeletionOutcome"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["confirmDeletion"].exists)
        app.buttons["checkDeletionOutcome"].tap()
        XCTAssertTrue(app.staticTexts["The object is no longer visible. This does not prove deletion; verify its state in NetBox."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.exists)
    }
    @MainActor private func deleteNewInterface(virtual: Bool) {
        let app = openInventory(virtual ? "virtualMachines" : "devices", id: virtual ? 401 : 301)
        app.buttons[virtual ? "inventoryObject-401" : "inventoryObject-301"].tap(); app.buttons["related-interfaces"].tap()
        XCTAssertTrue(app.buttons["newInterface"].waitForExistence(timeout: 5)); app.buttons["newInterface"].tap()
        let name = app.textFields["interfaceCreationName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("eth9")
        app.navigationBars.buttons["Done"].tap(); app.buttons["reviewInterfaceCreation"].tap()
        XCTAssertTrue(app.buttons["confirmInterfaceCreation"].waitForExistence(timeout: 5)); app.buttons["confirmInterfaceCreation"].tap()
        XCTAssertTrue(app.buttons["Open created object"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["newInterface"].waitForExistence(timeout: 5))
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("eth9")
        XCTAssertTrue(app.buttons["interface-1001"].waitForExistence(timeout: 5)); app.buttons["interface-1001"].tap()
        XCTAssertTrue(app.buttons["editInterface"].waitForExistence(timeout: 5)); app.buttons["editInterface"].tap(); app.buttons["deleteObject"].tap()
        confirmDeletion(app, id: 1001)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "eth9")
        XCTAssertTrue(app.buttons["interface-1001"].waitForNonExistence(timeout: 8))
    }
    @MainActor func testDeleteNewPhysicalInterface() { deleteNewInterface(virtual: false) }
    @MainActor func testDeleteNewVMInterface() { deleteNewInterface(virtual: true) }

    @MainActor func testDashboardShowsInstalledAppVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]
        app.launch()
        let badge = app.descendants(matching: .any)["appVersion"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        let version = badge.value as? String ?? ""
        XCTAssertNotNil(version.range(of: #"^MNetBox \d+\.\d+\.\d+ · Build \d+$"#, options: .regularExpression), version)
    }
    @MainActor func testPhysicalInterfaceNameDescriptionAndTypeReviewSave() {
        let app = openEditableInterface()
        app.buttons["interfaceField-Name"].tap()
        let name = app.descendants(matching: .any)["interfaceTextDraft"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "bond9")
        app.navigationBars.buttons["Done"].tap(); confirmStructured(app)
        XCTAssertTrue(app.staticTexts["interfaceTitle"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["interfaceTitle"].label, "bond9")
        app.buttons["editInterface"].tap(); app.buttons["editInterfaceDescription"].tap()
        let description = app.descendants(matching: .any)["interfaceTextDraft"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5)); app.buttons["clearInterfaceDescription"].tap(); description.tap()
        description.typeText("Updated from iPhone")
        app.navigationBars.buttons["Done"].tap(); confirmStructured(app)
        app.buttons["editInterface"].tap(); app.buttons["editInterfaceType"].tap()
        XCTAssertTrue(app.buttons["interfaceTypeDraft"].waitForExistence(timeout: 5)); app.buttons["interfaceTypeDraft"].tap()
        app.buttons["10GBASE-X SFP+ (10 GbE)"].tap(); confirmStructured(app)
        XCTAssertTrue(app.buttons["interfaceCable"].exists)
        let type = app.descendants(matching: .any)["interfaceField-Type"].firstMatch
        XCTAssertEqual(type.value as? String, "10GBASE-X SFP+ (10 GbE)")
    }
    @MainActor func testVMInterfaceNameCancelAndDescriptionClearing() {
        let app = openEditableInterface(virtual: true)
        app.buttons["editInterface"].tap()
        XCTAssertFalse(app.buttons["editInterfaceType"].exists)
        app.buttons["editInterfaceName"].tap()
        let name = app.descendants(matching: .any)["interfaceTextDraft"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("-draft")
        app.navigationBars.buttons["Done"].tap(); app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["interfaceTitle"].label, "eth0")
        app.buttons["editInterface"].tap(); app.buttons["editInterfaceDescription"].tap()
        let description = app.descendants(matching: .any)["interfaceTextDraft"].firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5)); app.buttons["clearInterfaceDescription"].tap()
        confirmStructured(app)
        app.buttons["editInterface"].tap(); app.buttons["editInterfaceDescription"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["interfaceTextDraft"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["structuredReview"].isEnabled)
        app.buttons["Cancel"].tap()
    }
    @MainActor func testPrimaryIPDetachShowsUsefulMessageWithoutSaving() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard"]; app.launch()
        app.buttons["browse-ipAddresses"].tap()
        XCTAssertTrue(app.buttons["ipamObject-11"].waitForExistence(timeout: 5)); app.buttons["ipamObject-11"].tap()
        app.buttons["ipamField-Assigned object"].tap()
        XCTAssertTrue(app.buttons["clearAssignment"].waitForExistence(timeout: 5)); app.buttons["clearAssignment"].tap()
        app.buttons["structuredReview"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "This IP is a primary address.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["structuredConfirm"].exists)
        app.buttons["Cancel"].tap()
        reveal(app.buttons["ipAssignedInterface"], in: app)
    }
    @MainActor func testDirectDeviceNameEditCancel() {
        let app = openInventory("devices", id: 301); app.buttons["inventoryObject-301"].tap()
        let name = reveal(app.buttons["inventoryField-Name"], in: app); name.tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5)); app.navigationBars.buttons["Cancel"].tap()
        XCTAssertEqual(reveal(app.staticTexts["inventoryDetailTitle"], in: app).label, "Core-switch")
    }
    @MainActor func testPhysicalVLANScopedSelectionsReviewAndModeClearing() {
        let app = openEditableInterface()
        let entry = app.buttons["interfaceField-VLAN mode"]
        for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["vlanModeDraft"].waitForExistence(timeout: 5)); app.buttons["vlanModeDraft"].tap(); app.buttons["Tagged"].tap()
        app.buttons["vlanUntaggedPicker"].tap()
        XCTAssertTrue(app.buttons["vlan-22"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlan-23"].exists)
        app.buttons["vlan-22"].tap()
        app.buttons["vlanTaggedPicker"].tap()
        app.segmentedControls["vlanScope"].buttons["Global"].tap()
        XCTAssertTrue(app.buttons["vlan-21"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlan-22"].exists)
        app.buttons["vlan-21"].tap()
        app.buttons["vlanModeDraft"].tap(); app.buttons["Access"].tap()
        XCTAssertTrue(app.buttons["removeVLAN-21"].exists)
        let review = app.buttons["vlanReview"]
        for _ in 0..<3 where !review.exists { app.swipeUp() }
        XCTAssertFalse(review.isEnabled)
        app.swipeDown(); app.buttons["clearTaggedVLANs"].tap()
        for _ in 0..<3 where !review.isHittable { app.swipeUp() }
        review.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["vlanConfirm"].waitForExistence(timeout: 5)); attach(app, name: "VLAN before after")
        app.buttons["vlanConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vlanSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        let value = app.descendants(matching: .any)["interfaceField-VLAN mode"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.value as? String, "Access")
    }
    @MainActor func testVMVLANGlobalOnlyAndCancel() {
        let app = openEditableInterface(virtual: true)
        app.buttons["editInterface"].tap(); app.buttons["editVLAN"].tap()
        app.buttons["vlanModeDraft"].tap(); app.buttons["Access"].tap()
        app.buttons["vlanUntaggedPicker"].tap()
        XCTAssertTrue(app.buttons["vlan-21"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlan-22"].exists)
        XCTAssertFalse(app.segmentedControls["vlanScope"].exists)
        app.buttons["vlan-21"].tap(); app.buttons["vlanReview"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["vlanConfirm"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["editInterface"].tap(); app.buttons["editVLAN"].tap()
        XCTAssertTrue(app.buttons["vlanReview"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlanReview"].isEnabled)
        app.buttons["Cancel"].tap()
    }

    @MainActor private func waitForNetworkValue(_ element: XCUIElement, _ value: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
    @MainActor private func networkApp(virtual: Bool? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-network-writes"]
        app.launch()
        XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        if let virtual {
            app.buttons[virtual ? "browse-virtualMachines" : "browse-devices"].tap()
            let parent = app.buttons[virtual ? "inventoryObject-401" : "inventoryObject-301"]
            XCTAssertTrue(parent.waitForExistence(timeout: 5)); parent.tap()
            app.buttons["related-interfaces"].tap()
            let link = app.buttons[virtual ? "interface-801" : "interface-501"]
            XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
            XCTAssertTrue(app.buttons["interfaceMACs"].waitForExistence(timeout: 5))
        }
        return app
    }
    @MainActor private func revealNetworkButton(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let button = app.buttons[id]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == YES AND enabled == YES"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        for _ in 0..<6 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); return button
    }
    @MainActor func testVLANCreationGroupReviewAndDirectNameEdit() {
        let app = networkApp()
        app.tabBars.buttons["IPAM"].tap(); app.buttons["ipamCategory-vlans"].tap()
        XCTAssertTrue(app.buttons["createVLAN"].waitForExistence(timeout: 5)); app.buttons["createVLAN"].tap()
        let vid = app.textFields["vlanVIDDraft"], name = app.textFields["vlanNameDraft"]
        XCTAssertTrue(vid.waitForExistence(timeout: 5)); vid.tap(); vid.typeText("250")
        name.tap(); name.typeText("Mobile VLAN")
        app.navigationBars.buttons["Done"].tap()
        app.swipeUp()
        app.buttons["creationReference-VLAN group"].tap()
        XCTAssertTrue(app.buttons["reference-31"].waitForExistence(timeout: 5)); app.buttons["reference-31"].tap()
        revealNetworkButton(app, "networkCreateReview").tap()
        XCTAssertTrue(app.buttons["networkCreateConfirm"].waitForExistence(timeout: 5)); attach(app, name: "VLAN creation review")
        revealNetworkButton(app, "networkCreateConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["networkCreated"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["openCreatedNetwork"].tap()
        XCTAssertTrue(app.buttons["vlanName"].waitForExistence(timeout: 5)); app.buttons["vlanName"].tap()
        let draft = app.textFields["nameDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(); draft.typeText("-renamed")
        app.navigationBars.buttons["Done"].tap(); app.buttons["nameReview"].tap()
        app.buttons["nameConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["nameSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["vlanName"], "Mobile VLAN-renamed")
    }
    @MainActor func testMACCreationNormalizationAndNonprimaryDetach() {
        let app = networkApp(virtual: false)
        app.buttons["interfaceMACs"].tap(); app.buttons["createMAC"].tap()
        let address = app.textFields["macAddressDraft"]
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap(); address.typeText("0200.0000.0099")
        app.navigationBars.buttons["Done"].tap()
        revealNetworkButton(app, "networkCreateReview").tap()
        XCTAssertTrue(app.staticTexts["02:00:00:00:00:99"].waitForExistence(timeout: 5)); attach(app, name: "MAC creation review")
        revealNetworkButton(app, "networkCreateConfirm").tap()
        XCTAssertTrue(app.buttons["openCreatedNetwork"].waitForExistence(timeout: 5)); app.buttons["openCreatedNetwork"].tap()
        app.buttons["macAssignment"].tap()
        XCTAssertTrue(app.buttons["clearAssignment"].waitForExistence(timeout: 5)); app.buttons["clearAssignment"].tap()
        revealNetworkButton(app, "structuredReview").tap()
        XCTAssertTrue(app.buttons["structuredConfirm"].waitForExistence(timeout: 5)); app.buttons["structuredConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["structuredSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["macAssignment"], "None")
        XCTAssertFalse(app.buttons["macInterface"].exists)
    }
    @MainActor func testMACPrimaryConstraintAndExplicitInterfaceClearing() {
        let app = networkApp(virtual: false)
        app.buttons["interfaceMACs"].tap()
        XCTAssertTrue(app.buttons["macObject-11"].waitForExistence(timeout: 5)); app.buttons["macObject-11"].tap()
        app.buttons["macAssignment"].tap(); app.buttons["clearAssignment"].tap()
        revealNetworkButton(app, "structuredReview").tap()
        let blocker = app.staticTexts["This MAC is primary on its interface. Clear that primary designation before removing or changing its assignment."]
        XCTAssertTrue(blocker.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["structuredConfirm"].exists)
        app.buttons["Cancel"].tap(); app.buttons["macInterface"].tap()
        app.buttons["editInterface"].tap(); app.buttons["editPrimaryMAC"].tap()
        app.buttons["structuredReference"].tap()
        XCTAssertTrue(app.buttons["reference-12"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["reference-13"].exists)
        app.buttons["None"].tap()
        revealNetworkButton(app, "structuredReview").tap()
        XCTAssertTrue(app.buttons["structuredConfirm"].waitForExistence(timeout: 5)); app.buttons["structuredConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["structuredSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        _ = revealNetworkButton(app, "interfacePrimaryMAC")
        waitForNetworkValue(app.buttons["interfacePrimaryMAC"], "—")
        attach(app, name: "Cleared primary MAC interface")
    }
    @MainActor func testVMPrimaryMACPickerStaysScopedAndCancelPreservesValue() {
        let app = networkApp(virtual: true)
        app.buttons["editInterface"].tap(); app.buttons["editPrimaryMAC"].tap()
        app.buttons["structuredReference"].tap()
        XCTAssertTrue(app.buttons["reference-13"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["reference-11"].exists)
        app.buttons["None"].tap(); revealNetworkButton(app, "structuredReview").tap()
        XCTAssertTrue(app.buttons["structuredConfirm"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        app.buttons["editInterface"].tap(); app.buttons["editPrimaryMAC"].tap()
        XCTAssertFalse(app.buttons["structuredReview"].isEnabled); app.buttons["Cancel"].tap()
    }

    @MainActor private func administrationApp(_ kind: String, search: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-ipam-administration"]
        app.launch(); XCTAssertTrue(app.buttons["browse-sites"].waitForExistence(timeout: 5))
        app.tabBars.buttons["IPAM"].tap(); app.buttons["ipamCategory-" + kind].tap()
        let field = app.searchFields.firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(search)
        app.swipeUp()
        let id = kind == "prefixes" ? 9005 : 9006
        let target = app.buttons["ipamObject-\(id)"]
        for _ in 0..<5 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap(); return app
    }
    @MainActor private func administrationButton(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let button = app.buttons[id]
        for _ in 0..<8 { if button.exists && button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 5)); return button
    }
    @MainActor private func saveAdministrationEdit(_ app: XCUIApplication) {
        administrationButton(app, "ipamEditReview").tap()
        XCTAssertTrue(app.buttons["ipamEditConfirm"].waitForExistence(timeout: 5)); app.buttons["ipamEditConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ipamEditSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
    }
    @MainActor func testPrefixVLANRoleAndScopeDirectEditing() {
        let app = administrationApp("prefixes", search: "203.0.113.0")
        administrationButton(app, "ipamField-VLAN").tap()
        XCTAssertTrue(app.buttons["ipamEditReference"].waitForExistence(timeout: 5)); app.buttons["ipamEditReference"].tap()
        XCTAssertTrue(app.buttons["reference-1"].waitForExistence(timeout: 5)); app.buttons["reference-1"].tap()
        saveAdministrationEdit(app)
        administrationButton(app, "ipamField-Role").tap(); app.buttons["ipamEditReference"].tap()
        XCTAssertTrue(app.buttons["reference-2"].waitForExistence(timeout: 5)); app.buttons["reference-2"].tap(); saveAdministrationEdit(app)
        administrationButton(app, "ipamField-Scope").tap()
        XCTAssertTrue(app.buttons["prefixScopeKind"].waitForExistence(timeout: 5)); app.buttons["prefixScopeKind"].tap(); app.buttons["Site"].tap()
        app.buttons["ipamEditReference"].tap(); XCTAssertTrue(app.buttons["reference-101"].waitForExistence(timeout: 5)); app.buttons["reference-101"].tap()
        administrationButton(app, "ipamEditReview").tap(); attach(app, name: "Prefix scope review")
        app.buttons["ipamEditConfirm"].tap(); XCTAssertTrue(app.descendants(matching: .any)["ipamEditSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["ipamField-Scope"], "Example Paris")
    }
    @MainActor func testIPRenumberingVRFAndDependencyBlock() {
        let app = administrationApp("ipAddresses", search: "203.0.113.99")
        administrationButton(app, "ipamField-CIDR").tap()
        let draft = app.textFields["ipamCIDRDraft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue); draft.typeText("203.0.113.100/32"); app.navigationBars.buttons["Done"].tap()
        saveAdministrationEdit(app)
        reveal(app.staticTexts["ipamDetailTitle"], in: app); XCTAssertEqual(app.staticTexts["ipamDetailTitle"].label, "203.0.113.100/32")
        administrationButton(app, "ipamField-VRF").tap(); app.buttons["ipamEditReference"].tap()
        XCTAssertTrue(app.buttons["reference-7"].waitForExistence(timeout: 5)); app.buttons["reference-7"].tap(); saveAdministrationEdit(app)
        waitForNetworkValue(app.buttons["ipamField-VRF"], "Blue")
        app.tabBars.buttons["IPAM"].tap(); app.buttons["ipamCategory-ipAddresses"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("192.0.2.10")
        app.swipeUp(); administrationButton(app, "ipamObject-11").tap()
        administrationButton(app, "ipamField-CIDR").tap(); XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue); draft.typeText("192.0.2.11/24"); app.navigationBars.buttons["Done"].tap()
        administrationButton(app, "ipamEditReview").tap()
        XCTAssertFalse(app.buttons["ipamEditConfirm"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Address or VRF changes require an unused prefix")).firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testCableDirectoryPaginationDiagramAndInterfaceNavigation() {
        let app = networkApp()
        app.tabBars.buttons["Inventory"].tap(); app.buttons["inventoryCategory-cables"].tap()
        XCTAssertTrue(app.buttons["cableObject-701"].waitForExistence(timeout: 5))
        administrationButton(app, "cableLoadMore").tap()
        XCTAssertTrue(app.buttons["cableObject-704"].waitForExistence(timeout: 5))
        for _ in 0..<4 { if app.buttons["cableObject-701"].isHittable { break }; app.swipeDown() }
        app.buttons["cableObject-701"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cableDiagram"].firstMatch.waitForExistence(timeout: 5)); attach(app, name: "Cable diagram with multiple terminations")
        XCTAssertTrue(app.staticTexts["Patch-panel port"].firstMatch.exists)
        administrationButton(app, "diagram-Side A-501").tap()
        XCTAssertTrue(app.buttons["interfaceMACs"].waitForExistence(timeout: 5))
    }
    @MainActor private func contextAdministrationApp(_ kind: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-context-administration"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["IPAM"].waitForExistence(timeout: 5)); app.tabBars.buttons["IPAM"].tap(); administrationButton(app, "contextCategory-\(kind)").tap(); return app
    }
    @MainActor private func createContextForm(_ app: XCUIApplication, name: String, slug: String? = nil, rd: String? = nil) {
        administrationButton(app, "createContext").tap()
        let field = app.textFields["contextNameDraft"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(name)
        if let slug { let draft = app.textFields["contextSlugDraft"]; draft.tap(); draft.typeText(slug) }
        if let rd { let draft = app.textFields["contextRDDraft"]; draft.tap(); draft.typeText(rd) }
        app.navigationBars.buttons["Done"].tap()
    }
    @MainActor private func saveContextCreation(_ app: XCUIApplication) {
        administrationButton(app, "contextCreateReview").tap(); administrationButton(app, "contextCreateConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["contextCreated"].firstMatch.waitForExistence(timeout: 5)); administrationButton(app, "openCreatedContext").tap()
        XCTAssertTrue(app.staticTexts["contextGraphicTitle"].waitForExistence(timeout: 5))
    }
    @MainActor private func saveContextEdit(_ app: XCUIApplication, text: String) {
        let draft = app.textFields["contextEditDraft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue); draft.typeText(text); app.navigationBars.buttons["Done"].tap()
        administrationButton(app, "contextEditReview").tap(); administrationButton(app, "contextEditConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["contextEditSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
    }
    @MainActor func testVRFCreationGraphicDetailAndDirectMetadataEdit() {
        let app = contextAdministrationApp("vrfs")
        createContextForm(app, name: "Mobile VRF", rd: "64512:99"); saveContextCreation(app)
        attach(app, name: "Graphical VRF detail")
        administrationButton(app, "contextField-name").tap(); saveContextEdit(app, text: "Mobile VRF edited")
        waitForNetworkValue(app.buttons["contextField-name"], "Mobile VRF edited")
        XCTAssertFalse(app.buttons["contextField-rd"].exists)
    }
    @MainActor func testTenantCreationGroupAndSlugDirectEdit() {
        let app = contextAdministrationApp("tenants")
        createContextForm(app, name: "Mobile tenant", slug: "mobile-tenant"); saveContextCreation(app)
        administrationButton(app, "contextField-group").tap(); administrationButton(app, "contextEditReference").tap()
        XCTAssertTrue(app.buttons["reference-51"].waitForExistence(timeout: 5)); app.buttons["reference-51"].tap()
        administrationButton(app, "contextEditReview").tap(); administrationButton(app, "contextEditConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["contextEditSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["contextField-group"], "Customers")
        administrationButton(app, "contextField-slug").tap(); saveContextEdit(app, text: "mobile-tenant-edited")
        waitForNetworkValue(app.buttons["contextField-slug"], "mobile-tenant-edited")
    }
    @MainActor func testIPAMRoleCreationWeightDirectEditAndCancel() {
        let app = contextAdministrationApp("roles")
        createContextForm(app, name: "Mobile role", slug: "mobile-role"); saveContextCreation(app)
        administrationButton(app, "contextField-weight").tap(); saveContextEdit(app, text: "50")
        waitForNetworkValue(app.buttons["contextField-weight"], "50")
        administrationButton(app, "contextField-name").tap(); app.buttons["Cancel"].tap()
        waitForNetworkValue(app.buttons["contextField-name"], "Mobile role")
    }
    @MainActor func testDeviceAutomaticImagesAndLargePreview() {
        let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-netbox-images"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap(); app.buttons["inventoryCategory-devices"].tap()
        administrationButton(app, "inventoryObject-301").tap()
        let image = administrationButton(app, "netboxImage-attachment-81"); XCTAssertTrue(image.waitForExistence(timeout: 10)); attach(app, name: "Automatic NetBox attachment image")
        image.tap(); XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5)); attach(app, name: "NetBox image large preview"); app.navigationBars.buttons["Done"].tap()
        administrationButton(app, "netboxImage-type-1-Front").tap(); XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
    }
    @MainActor func testPhysicalCableTraceGraphicStepsAndCableNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-cable-trace"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventoryCategory-devices"].tap(); administrationButton(app, "inventoryObject-301").tap()
        administrationButton(app, "related-interfaces").tap(); administrationButton(app, "interface-501").tap()
        administrationButton(app, "interfaceTrace").tap()
        XCTAssertTrue(app.buttons["traceCable-701"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tracePort-rear-ports-901"].firstMatch.exists); attach(app, name: "Physical cable trace with patch panel")
        administrationButton(app, "traceCable-701").tap(); XCTAssertTrue(app.descendants(matching: .any)["cableTitle"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testImageUploadReviewedSyntheticPhotoAndRefreshedGallery() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-image-upload"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventoryCategory-devices"].tap(); administrationButton(app, "inventoryObject-301").tap()
        administrationButton(app, "addNetBoxImage").tap()
        XCTAssertTrue(app.buttons["syntheticUploadImage"].waitForExistence(timeout: 5)); app.buttons["syntheticUploadImage"].tap()
        administrationButton(app, "imageUploadReview").tap(); XCTAssertTrue(app.buttons["imageUploadConfirm"].waitForExistence(timeout: 5)); attach(app, name: "Reviewed NetBox photo upload")
        app.buttons["Back to editing"].tap(); app.navigationBars.buttons["Cancel"].tap()
        administrationButton(app, "addNetBoxImage").tap(); app.buttons["syntheticUploadImage"].tap()
        administrationButton(app, "imageUploadReview").tap(); administrationButton(app, "imageUploadConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["imageUploaded"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["netboxImage-attachment-9901"].waitForExistence(timeout: 8)); app.buttons["netboxImage-attachment-9901"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5)); app.navigationBars.buttons["Done"].tap()
        administrationButton(app, "deleteNetBoxImage-9901").tap()
        XCTAssertTrue(app.textFields["deletionConfirmationID"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["netboxImage-attachment-9901"].waitForExistence(timeout: 5))
        administrationButton(app, "deleteNetBoxImage-9901").tap()
        let confirmation = app.textFields["deletionConfirmationID"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5)); confirmation.tap(); confirmation.typeText("9901")
        attach(app, name: "Reviewed attachment deletion")
        administrationButton(app, "confirmDeletion").tap()
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["No NetBox images"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["deleteNetBoxImage-9901"].exists)
    }
    @MainActor private func portPanelApp(dark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-port-panel"]
        if dark { app.launchArguments.append("--ui-testing-dark") }
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventoryCategory-devices"].tap(); administrationButton(app, "inventoryObject-301").tap()
        administrationButton(app, "devicePortPanel").tap(); return app
    }
    @MainActor func testGraphicalPortPanelAndInterfaceNavigation() {
        let app = portPanelApp()
        let tile = app.buttons["panelPort-interfaces-1501"]
        XCTAssertTrue(tile.waitForExistence(timeout: 6)); XCTAssertTrue(tile.label.contains("Cabled"))
        XCTAssertTrue(app.buttons["panelPort-interfaces-1503"].label.contains("No cable"))
        attach(app, name: "Graphical switch port panel light")
        tile.tap()
        XCTAssertEqual(app.staticTexts["panelSelectedName"].label, "Gi1/0/1")
        attach(app, name: "Selected actual port")
        administrationButton(app, "panelOpenDetails").tap()
        XCTAssertTrue(app.descendants(matching: .any)["interfaceTitle"].firstMatch.waitForExistence(timeout: 6)); XCTAssertEqual(app.descendants(matching: .any)["interfaceTitle"].firstMatch.label, "Gi1/0/1")
    }
    @MainActor func testGraphicalPortPanelSearchFiberAndDarkAppearance() {
        let app = portPanelApp(dark: true)
        XCTAssertTrue(app.buttons["panelPort-interfaces-1501"].waitForExistence(timeout: 6))
        attach(app, name: "Graphical switch port panel dark")
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Te1/0")
        if app.keyboards.buttons["search"].exists { app.keyboards.buttons["search"].tap() }
        XCTAssertTrue(app.buttons["panelPort-interfaces-1549"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["panelPort-interfaces-1501"].exists)
        attach(app, name: "Optical port search results")
    }
    @MainActor func testGraphicalCableCreationReviewAndConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-port-panel", "--ui-testing-cable-creation"]
        app.launch(); app.tabBars.buttons["Inventory"].tap(); app.buttons["inventoryCategory-devices"].tap()
        administrationButton(app, "inventoryObject-301").tap()
        XCTAssertFalse(app.buttons["devicePorts"].exists)
        administrationButton(app, "devicePortPanel").tap()
        administrationButton(app, "panelPort-interfaces-1503").tap()
        administrationButton(app, "connectCable").tap()
        administrationButton(app, "cableDestinationDevice").tap()
        administrationButton(app, "reference-303").tap()
        administrationButton(app, "cableDestinationPort").tap()
        administrationButton(app, "panelPort-interfaces-1601").tap()
        administrationButton(app, "chooseCablePort").tap()
        attach(app, name: "Graphical cable destination selected")
        administrationButton(app, "reviewCableCreation").tap()
        XCTAssertTrue(app.buttons["confirmCableCreation"].waitForExistence(timeout: 6))
        attach(app, name: "Reviewed graphical connection")
        app.buttons["Back to editing"].tap()
        administrationButton(app, "reviewCableCreation").tap()
        administrationButton(app, "confirmCableCreation").tap()
        XCTAssertTrue(app.descendants(matching: .any)["cableCreated"].firstMatch.waitForExistence(timeout: 6))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["connectCable"].exists)
    }
    @MainActor func testPortPanelHidesEmptyFamilies() {
        let app = portPanelApp()
        let family = app.buttons["panelFamily"]
        XCTAssertTrue(family.waitForExistence(timeout: 6)); family.tap()
        XCTAssertTrue(app.buttons["Console ports"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Power ports"].exists)
        XCTAssertFalse(app.buttons["Front ports"].exists)
        XCTAssertFalse(app.buttons["Rear ports"].exists)
        XCTAssertFalse(app.buttons["Power outlets"].exists)
        app.buttons["Console ports"].tap()
        XCTAssertTrue(app.buttons["panelPort-console-ports-1201"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["panelPort-interfaces-1501"].exists)
    }
    @MainActor func testDevicePortDirectoryConsoleDetailAndNativeTrace() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-device-ports"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventoryCategory-devices"].tap(); administrationButton(app, "inventoryObject-301").tap()
        administrationButton(app, "devicePortPanel").tap()
        XCTAssertFalse(app.buttons["devicePorts"].exists)
        app.buttons["panelFamily"].tap(); app.buttons["Console ports"].tap()
        administrationButton(app, "panelPort-console-ports-1201").tap()
        administrationButton(app, "panelOpenDetails").tap()
        XCTAssertTrue(app.staticTexts["devicePortTitle"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["devicePortTitle"].label, "Console A")
        attach(app, name: "Console port detail")
        administrationButton(app, "devicePortTrace").tap()
        XCTAssertTrue(app.buttons["traceDevicePort-1201"].waitForExistence(timeout: 5))
        app.buttons["traceDevicePort-1201"].tap(); XCTAssertTrue(app.staticTexts["devicePortTitle"].waitForExistence(timeout: 5))
    }
    @MainActor func testContextRoleDeletionRefreshAndVRFRouteTargetBlock() {
        let app = contextAdministrationApp("roles")
        administrationButton(app, "contextObject-roles-1").tap(); administrationButton(app, "deleteContext").tap()
        XCTAssertTrue(app.textFields["deletionConfirmationID"].waitForExistence(timeout: 5)); app.navigationBars.buttons["Cancel"].tap()
        administrationButton(app, "deleteContext").tap(); confirmDeletion(app, id: 1)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["contextObject-roles-2"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["contextObject-roles-1"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap(); administrationButton(app, "contextCategory-vrfs").tap()
        administrationButton(app, "contextObject-vrfs-7").tap(); administrationButton(app, "deleteContext").tap()
        XCTAssertTrue(app.descendants(matching: .any)["deletionBlocked"].firstMatch.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["confirmDeletion"].exists)
        attach(app, name: "VRF route target deletion blocked")
    }
    @MainActor func testPassivePortTraceMappingsAndParentNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-cable-trace"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["Inventory"].waitForExistence(timeout: 5)); app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventoryCategory-devices"].tap(); administrationButton(app, "inventoryObject-301").tap()
        administrationButton(app, "related-interfaces").tap(); administrationButton(app, "interface-501").tap(); administrationButton(app, "interfaceTrace").tap()
        let port = app.buttons["tracePort-rear-ports-901"].firstMatch
        XCTAssertTrue(port.waitForExistence(timeout: 5)); for _ in 0..<3 { if port.isHittable { break }; app.swipeUp() }; port.tap()
        XCTAssertTrue(app.descendants(matching: .any)["passivePortTitle"].firstMatch.waitForExistence(timeout: 5)); attach(app, name: "Patch panel rear port mappings")
        administrationButton(app, "portMapping-0").tap()
        XCTAssertTrue(app.staticTexts["passivePortTitle"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["passivePortTitle"].label, "Front 1")
    }
    @MainActor private func vlanAdministrationApp(_ kind: String, search: String, id: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--ui-testing-dashboard", "--ui-testing-vlan-administration"]
        app.launch(); XCTAssertTrue(app.tabBars.buttons["IPAM"].waitForExistence(timeout: 5)); app.tabBars.buttons["IPAM"].tap()
        app.buttons["ipamCategory-\(kind)"].tap()
        let field = app.searchFields.firstMatch; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(search); app.swipeUp()
        administrationButton(app, "vlanObject-\(kind)-\(id)").tap(); return app
    }
    @MainActor private func changeVLANAdminText(_ app: XCUIApplication, to text: String) {
        let draft = app.textFields["vlanAdminDraft"]; XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        draft.typeText(XCUIKeyboardKey.delete.rawValue); draft.typeText(text); app.navigationBars.buttons["Done"].tap()
    }
    @MainActor private func saveVLANAdmin(_ app: XCUIApplication) {
        administrationButton(app, "vlanAdminReview").tap(); administrationButton(app, "vlanAdminConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["vlanAdminSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
    }
    @MainActor func testVLANIdentityDirectEditingAndCancel() {
        let app = vlanAdministrationApp("vlans", search: "Editable", id: 9020)
        administrationButton(app, "vlanVID").tap(); changeVLANAdminText(app, to: "251"); saveVLANAdmin(app)
        waitForNetworkValue(app.buttons["vlanVID"], "251")
        administrationButton(app, "vlanSite").tap(); app.buttons["vlanAdminReference"].tap()
        XCTAssertTrue(app.buttons["reference-101"].waitForExistence(timeout: 5)); app.buttons["reference-101"].tap(); saveVLANAdmin(app)
        waitForNetworkValue(app.buttons["vlanSite"], "Example Paris")
        administrationButton(app, "vlanGroupField").tap(); app.buttons["vlanAdminReference"].tap()
        XCTAssertTrue(app.buttons["reference-31"].waitForExistence(timeout: 5)); app.buttons["reference-31"].tap()
        administrationButton(app, "vlanAdminReview").tap(); attach(app, name: "VLAN group move preview")
        administrationButton(app, "vlanAdminConfirm").tap(); XCTAssertTrue(app.descendants(matching: .any)["vlanAdminSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["vlanGroupField"], "Paris VLANs")
        administrationButton(app, "vlanVID").tap(); changeVLANAdminText(app, to: "252"); app.buttons["Cancel"].tap()
        waitForNetworkValue(app.buttons["vlanVID"], "251")
    }
    @MainActor func testVLANGroupDeletionEmptyOriginRefreshAndOccupiedBlock() {
        let app = vlanAdministrationApp("groups", search: "Editable group", id: 9021)
        XCTAssertTrue(app.buttons["deleteVLANGroup"].waitForExistence(timeout: 5)); app.buttons["deleteVLANGroup"].tap()
        XCTAssertTrue(app.textFields["deletionConfirmationID"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["deleteVLANGroup"].waitForExistence(timeout: 5)); app.buttons["deleteVLANGroup"].tap()
        confirmDeletion(app, id: 9021)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 5)); attach(app, name: "Empty VLAN group deletion")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Editable group")
        XCTAssertTrue(app.staticTexts["0 loaded · 0 total"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vlanObject-groups-9021"].exists)
        app.terminate()
        let occupied = vlanAdministrationApp("groups", search: "Paged group", id: 9022)
        occupied.buttons["deleteVLANGroup"].tap()
        XCTAssertTrue(occupied.descendants(matching: .any)["deletionBlocked"].firstMatch.waitForExistence(timeout: 5)); XCTAssertFalse(occupied.buttons["confirmDeletion"].exists)
        occupied.navigationBars.buttons["Cancel"].tap(); XCTAssertTrue(occupied.buttons["deleteVLANGroup"].waitForExistence(timeout: 5))
    }
    @MainActor func testGroupSlugRangesTenantAndEmptyScopeDirectEditing() {
        let app = vlanAdministrationApp("groups", search: "Editable", id: 9021)
        administrationButton(app, "groupSlug").tap(); changeVLANAdminText(app, to: "mobile-group"); saveVLANAdmin(app)
        waitForNetworkValue(app.buttons["groupSlug"], "mobile-group")
        administrationButton(app, "groupRanges").tap(); changeVLANAdminText(app, to: "1-99,200-299"); saveVLANAdmin(app)
        waitForNetworkValue(app.buttons["groupRanges"], "1–99, 200–299")
        administrationButton(app, "vlanTenant").tap(); app.buttons["vlanAdminReference"].tap()
        XCTAssertTrue(app.buttons["reference-1"].waitForExistence(timeout: 5)); app.buttons["reference-1"].tap(); saveVLANAdmin(app)
        waitForNetworkValue(app.buttons["vlanTenant"], "Example tenant")
        administrationButton(app, "groupScope").tap(); app.buttons["vlanAdminScope"].tap(); app.buttons["Site"].tap()
        app.buttons["vlanAdminReference"].tap(); XCTAssertTrue(app.buttons["reference-101"].waitForExistence(timeout: 5)); app.buttons["reference-101"].tap()
        administrationButton(app, "vlanAdminReview").tap(); attach(app, name: "Empty VLAN group scope preview")
        administrationButton(app, "vlanAdminConfirm").tap(); XCTAssertTrue(app.descendants(matching: .any)["vlanAdminSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["groupScope"], "Example Paris · dcim.site · #101")
    }
    @MainActor func testOccupiedGroupRangesAndScopeBlockedBeforeConfirmation() {
        let app = vlanAdministrationApp("groups", search: "Paris VLANs", id: 31)
        administrationButton(app, "groupRanges").tap(); changeVLANAdminText(app, to: "1-199"); administrationButton(app, "vlanAdminReview").tap()
        let message = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The group contains incompatible VLANs.")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlanAdminConfirm"].exists); app.buttons["Cancel"].tap()
        administrationButton(app, "groupScope").tap(); app.buttons["vlanAdminScope"].tap(); app.buttons["Global"].tap(); administrationButton(app, "vlanAdminReview").tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["vlanAdminConfirm"].exists)
    }
    @MainActor func testVLANGroupCreationAndDirectEditing() {
        let app = networkApp()
        app.tabBars.buttons["IPAM"].tap(); app.buttons["ipamCategory-groups"].tap()
        XCTAssertTrue(app.buttons["createVLANGroup"].waitForExistence(timeout: 5)); app.buttons["createVLANGroup"].tap()
        let name = app.textFields["groupNameDraft"], slug = app.textFields["groupSlugDraft"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Mobile group")
        slug.tap(); slug.typeText("mobile-group")
        app.navigationBars.buttons["Done"].tap()
        revealNetworkButton(app, "groupCreateReview").tap()
        XCTAssertTrue(app.buttons["groupCreateConfirm"].waitForExistence(timeout: 5)); attach(app, name: "Group creation preview")
        revealNetworkButton(app, "groupCreateConfirm").tap()
        XCTAssertTrue(app.descendants(matching: .any)["groupCreated"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["openCreatedGroup"].tap()
        XCTAssertTrue(app.buttons["groupName"].waitForExistence(timeout: 5)); app.buttons["groupName"].tap()
        let draft = app.textFields["nameDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(); draft.typeText("-renamed")
        app.navigationBars.buttons["Done"].tap(); app.buttons["nameReview"].tap(); app.buttons["nameConfirm"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["nameSaved"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        waitForNetworkValue(app.buttons["groupName"], "Mobile group-renamed")
    }
    @MainActor func testUnusedVLANDeletionAndOriginRefresh() {
        let app = networkApp()
        app.tabBars.buttons["IPAM"].tap(); app.buttons["ipamCategory-vlans"].tap()
        app.buttons["createVLAN"].tap()
        let vid = app.textFields["vlanVIDDraft"], name = app.textFields["vlanNameDraft"]
        XCTAssertTrue(vid.waitForExistence(timeout: 5)); vid.tap(); vid.typeText("250")
        name.tap(); name.typeText("Disposable VLAN"); app.navigationBars.buttons["Done"].tap()
        revealNetworkButton(app, "networkCreateReview").tap(); revealNetworkButton(app, "networkCreateConfirm").tap()
        XCTAssertTrue(app.buttons["openCreatedNetwork"].waitForExistence(timeout: 5)); app.buttons["openCreatedNetwork"].tap()
        XCTAssertTrue(app.buttons["deleteVLAN"].waitForExistence(timeout: 5)); app.buttons["deleteVLAN"].tap()
        confirmDeletion(app, id: 1005)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 5)); attach(app, name: "VLAN deletion confirmed")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["openCreatedNetwork"].waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["createVLAN"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["vlanObject-vlans-1005"].exists)
    }
    @MainActor func testMACDeletionBlocksAssignmentAndDeletesUnassignedIdentity() {
        let app = networkApp(virtual: false)
        app.buttons["interfaceMACs"].tap()
        XCTAssertTrue(app.buttons["macObject-11"].waitForExistence(timeout: 5)); app.buttons["macObject-11"].tap()
        XCTAssertTrue(app.buttons["deleteMAC"].waitForExistence(timeout: 5)); app.buttons["deleteMAC"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["deletionBlocked"].firstMatch.waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["confirmDeletion"].exists)
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("00:02")
        let target = app.buttons["global-mac-14"]
        for _ in 0..<12 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
        XCTAssertTrue(app.buttons["deleteMAC"].waitForExistence(timeout: 5)); app.buttons["deleteMAC"].tap()
        confirmDeletion(app, id: 14)
        XCTAssertTrue(app.descendants(matching: .any)["deletionSucceeded"].firstMatch.waitForExistence(timeout: 5)); app.buttons["Done"].tap()
        let popped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: app.staticTexts["macDetailTitle"])
        XCTAssertEqual(XCTWaiter.wait(for: [popped], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["global-mac-12"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["global-mac-14"].exists)
    }
    @MainActor func testGlobalMACSearchKeepsReusedAddressesDistinct() {
        let app = networkApp()
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("00:02")
        let first = app.buttons["global-mac-12"]
        for _ in 0..<12 { if first.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(first.waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["global-mac-14"].exists)
        app.buttons["global-mac-14"].tap()
        XCTAssertTrue(app.staticTexts["macDetailTitle"].waitForExistence(timeout: 5))
        waitForNetworkValue(app.buttons["macAssignment"], "None")
    }

}
