import SwiftUI
import VisionKit

/// Live barcode / QR scanner. Only the payload string leaves this view.
struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    @MainActor static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                                   recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning, !context.coordinator.delivered { try? controller.startScanning() }
    }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private(set) var delivered = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !delivered else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue, !value.isEmpty {
                    delivered = true; dataScanner.stopScanning(); onCode(value); return
                }
            }
        }
    }
}

@MainActor @Observable final class ScanLookupModel {
    let client: APIClient
    var manual = ""
    private(set) var lookup: ScanLookup?
    private(set) var results: [InventoryObject] = []
    private(set) var total = 0
    private(set) var working = false
    private(set) var errorMessage: String?
    init(client: APIClient) { self.client = client }
    func resolve(_ code: String) async {
        errorMessage = nil; results = []; total = 0
        guard let server = URL(string: client.serverDisplay), let value = ScanLookup.interpret(code, server: server) else {
            lookup = nil; errorMessage = L10n.text("This code is not a device name, serial, asset tag or a link to this NetBox server."); return
        }
        lookup = value
        guard case .search(let term) = value else { return }
        working = true; defer { working = false }
        do {
            let page = try await InventoryService(client: client, kind: .devices).page(query: InventoryQuery(search: term), next: nil)
            results = page.results; total = page.count
        } catch { if !Task.isCancelled { errorMessage = readErrorMessage(error) } }
    }
}

struct ScanLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScanLookupModel
    @State private var scanning = BarcodeScanner.isAvailable
    @State private var request: String?
    @FocusState private var typing: Bool
    init(client: APIClient) { _model = State(initialValue: ScanLookupModel(client: client)) }
    private var service: InventoryService { InventoryService(client: model.client, kind: .devices) }
    var body: some View {
        NavigationStack {
            List {
                if scanning {
                    Section {
                        BarcodeScanner { code in scanning = false; request = code }
                            .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16)).listRowInsets(EdgeInsets())
                            .accessibilityLabel(L10n.text("Camera scanner"))
                    } footer: { Text("Point the camera at a QR code or barcode on the equipment label.") }
                } else if BarcodeScanner.isAvailable {
                    Button("Scan again", systemImage: "qrcode.viewfinder") { scanning = true; request = nil }.accessibilityIdentifier("scanAgain")
                }
                Section("Name, serial or asset tag") {
                    TextField("Enter a code", text: $model.manual).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($typing).submitLabel(.search).onSubmit { request = model.manual }.accessibilityIdentifier("scanManualCode")
                    Button("Look up") { typing = false; scanning = false; request = model.manual }
                        .disabled(model.manual.trimmingCharacters(in: .whitespaces).isEmpty || model.working).accessibilityIdentifier("scanLookup")
                }
                if model.working { ProgressView("Loading…") }
                if let error = model.errorMessage { StatusMessage(message: error) }
                if case .device(let id) = model.lookup {
                    Section("Result") {
                        NavigationLink { InventoryDetailView(service: service, id: id) } label: { Label(L10n.identifier("Object #%ld", id), systemImage: "server.rack") }
                            .accessibilityIdentifier("scanDevice-\(id)")
                    }
                } else if case .search(let term) = model.lookup, !model.working, model.errorMessage == nil {
                    Section {
                        if model.results.isEmpty { Text("No matching device.").accessibilityIdentifier("scanNoResult") }
                        ForEach(model.results) { device in
                            NavigationLink { InventoryDetailView(service: service, id: device.id) } label: {
                                VStack(alignment: .leading) { Text(device.title).font(.headline); Text(device.subtitle).font(.caption).foregroundStyle(.secondary) }
                            }.accessibilityIdentifier("scanDevice-\(device.id)")
                        }
                        if model.total > model.results.count { Text(L10n.format("%ld loaded · %ld total", model.results.count, model.total)).font(.caption) }
                    } header: { Text(verbatim: term) }
                }
                if !BarcodeScanner.isAvailable {
                    Text("The camera scanner is not available on this device. Enter the code instead.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scan a label").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task(id: request) { if let request { await model.resolve(request) } }
        }
    }
}
