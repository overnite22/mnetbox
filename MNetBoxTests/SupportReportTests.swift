import XCTest
@testable import MNetBox

final class SupportReportTests: XCTestCase {
    func testDiagnosticVersionsRejectArbitraryServerText() {
        for version in ["4.7.2", "4.8.0rc1", "27.2", "0.5.0"] { XCTAssertNotNil(TechnicalVersion(version)) }
        for version in ["", "https://private.example.test", "4.7.2\nAuthorization: synthetic-placeholder", "4.7.2+private-host", "9999.1.1", "4.7.2 ", "４.７.２"] { XCTAssertNil(TechnicalVersion(version)) }
    }
    func testSupportReportOnlyContainsWhitelistedTechnicalMetadata() {
        let report = SupportReport(appVersion: "0.5.0", build: "18", osVersion: "27.2", netBox: TechnicalVersion("4.7.2"))
        XCTAssertEqual(report.text, "MNetBox 0.5.0 (build 18)\niOS 27.2\nNetBox 4.7.2\nReference NetBox 4.7.2\nCompatibility: reference version")
        let invalid = SupportReport(appVersion: "synthetic-placeholder", build: "private-user", osVersion: "https://private.test", netBox: nil)
        XCTAssertFalse(invalid.text.contains("synthetic-placeholder")); XCTAssertFalse(invalid.text.contains("private-user")); XCTAssertFalse(invalid.text.contains("private.test"))
        XCTAssertTrue(invalid.text.contains("unverified"))
        let other = SupportReport(appVersion: "0.5.0", build: "18", osVersion: "27.2", netBox: TechnicalVersion("4.8.0"))
        XCTAssertTrue(other.text.contains("unverified"))
    }
    func testPackagedPrivacyManifestHasNoTrackingOrThirdPartyCollection() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        for key in ["NSPrivacyTrackingDomains", "NSPrivacyCollectedDataTypes", "NSPrivacyAccessedAPITypes"] {
            XCTAssertEqual((manifest[key] as? [Any])?.count, 0)
        }
    }
}
