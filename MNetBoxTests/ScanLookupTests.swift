import XCTest
@testable import MNetBox

final class ScanLookupTests: XCTestCase {
    private let server = URL(string: "https://netbox.example.test/api/")!

    func testDeviceLinkOnConfiguredServerOpensByID() {
        XCTAssertEqual(ScanLookup.interpret("https://netbox.example.test/dcim/devices/301/", server: server), .device(301))
        XCTAssertEqual(ScanLookup.interpret("  https://NETBOX.example.test/dcim/devices/42  ", server: server), .device(42))
    }
    func testForeignOrUnsafeLinksAreRefused() {
        for code in ["https://evil.example.test/dcim/devices/301/", "http://netbox.example.test/dcim/devices/301/",
                     "https://user:secret@netbox.example.test/dcim/devices/301/", "https://netbox.example.test:8443/dcim/devices/301/",
                     "https://netbox.example.test/dcim/racks/12/", "https://netbox.example.test/dcim/devices/0/"] {
            XCTAssertNil(ScanLookup.interpret(code, server: server), code)
        }
    }
    func testPlainCodesBecomeBoundedSearchTerms() {
        XCTAssertEqual(ScanLookup.interpret(" SN-ABC123 ", server: server), .search("SN-ABC123"))
        XCTAssertEqual(ScanLookup.interpret("Core-switch", server: server), .search("Core-switch"))
        XCTAssertNil(ScanLookup.interpret("", server: server))
        XCTAssertNil(ScanLookup.interpret("line\nbreak", server: server))
        XCTAssertNil(ScanLookup.interpret(String(repeating: "x", count: 201), server: server))
    }
    func testCustomFieldsAreReadableAndSkipEmptyValues() throws {
        let json = #"{"custom_fields": {"warranty_end": "2027-01-31", "rack_power_w": 450, "monitored": true, "owner": {"id": 3, "display": "Ops"}, "empty": null, "blank": "", "zones": ["A", "B"]}}"#
        struct Wrapper: Decodable { let custom_fields: NetBoxCustomFields }
        let fields = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8)).custom_fields
        XCTAssertEqual(fields.entries.map(\.key), ["monitored", "owner", "rack_power_w", "warranty_end", "zones"])
        XCTAssertEqual(fields.entries.first { $0.key == "owner" }?.text, "Ops")
        XCTAssertEqual(fields.entries.first { $0.key == "zones" }?.text, "A, B")
        XCTAssertEqual(fields.entries.first { $0.key == "rack_power_w" }?.text, "450")
        XCTAssertEqual(fields.entries.first { $0.key == "warranty_end" }?.title, "Warranty end")
    }
}
