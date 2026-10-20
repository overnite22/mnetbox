import SwiftUI

struct InterfaceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var deleted = false
    var onDeleted: (() -> Void)?
    let service: InterfaceService
    @State private var model: ReadDetailModel<InterfaceObject>
    @State private var refreshID = UUID()
    @State private var editingVLAN = false
    @State private var editingField: StructuredEditField?
    init(service: InterfaceService, id: Int, onDeleted: (() -> Void)? = nil) {
        self.service = service
        self.onDeleted = onDeleted
        _model = State(initialValue: ReadDetailModel(fetch: { try await service.detail(id: id) }))
    }
    private var canEdit: Bool {
        !model.isLoading && model.object.flatMap { service.parent($0)?.id }.map { $0 > 0 } == true
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { refreshID = UUID() }
            }
            if let object = model.object {
                Section("Explore") {
                    if service.kind == .physical {
                        NavigationLink { CableTraceView(client: service.client, interfaceID: object.id, title: object.name) } label: { Label("Cable trace", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.accessibilityIdentifier("interfaceTrace")
                    }
                    if let parent = service.parent(object)?.id, parent > 0 {
                        NavigationLink { MACListView(service: MACService(client: service.client, interface: InterfaceSelection(kind: service.kind, id: object.id, title: object.name, parentID: parent))) } label: { Label("MAC addresses", systemImage: "network") }.accessibilityIdentifier("interfaceMACs")
                    }
                    ForEach(object.relatedVLANs, id: \.id) { vlan in
                        NavigationLink { VLANDetailView(service: VLANBrowseService(client: service.client, kind: .vlans), id: vlan.id ?? 0) } label: { Label(vlan.text, systemImage: "square.stack.3d.up") }.accessibilityIdentifier("interfaceVLAN-\(vlan.id ?? 0)")
                    }
                    if let parent = service.parent(object), let id = parent.id, id > 0 {
                        NavigationLink {
                            InventoryDetailView(service: InventoryService(client: service.client, kind: service.kind.parentKind), id: id)
                        } label: { Label(parent.text, systemImage: service.kind.parentKind.symbol) }
                        .accessibilityIdentifier("interfaceParent")
                    }
                    NavigationLink {
                        IPAMListView(service: IPAMService(client: service.client, kind: .ipAddresses,
                            context: .interface(kind: service.kind, id: object.id, title: object.name)))
                    } label: { Label("Assigned IP addresses", systemImage: "number") }
                    .accessibilityIdentifier("interfaceIPs")
                    if let cableID = object.cable?.id, cableID > 0 {
                        NavigationLink {
                            CableDetailView(client: service.client, id: cableID) { refreshID = UUID() }
                        } label: { Label(object.cable?.text ?? L10n.text("Cable"), systemImage: "cable.connector") }
                        .accessibilityIdentifier("interfaceCable")
                    }
                }
                Section("Overview") {
                    Label(object.name, systemImage: "network").font(.title3.bold()).accessibilityIdentifier("interfaceTitle")
                    DetailField(title: "Name", value: object.name, action: { editingField = .name }, identifier: "interfaceField-Name")
                    DetailField(title: "Type", value: object.type?.text ?? (service.kind == .virtual ? L10n.text("Virtual") : "—"), action: service.kind == .physical ? { editingField = .type } : nil, identifier: "interfaceField-Type")
                    DetailField(title: "Enabled", value: object.enabled.map { $0 ? L10n.text("Yes") : L10n.text("No") } ?? "—", action: { editingField = .enabled }, identifier: "interfaceField-Enabled")
                    DetailField(title: "MTU", value: object.mtu.map(String.init) ?? "—", action: { editingField = .mtu }, identifier: "interfaceField-MTU")
                    DetailField(title: "Speed (kbps)", value: object.speed.map(String.init) ?? "—")
                    DetailField(title: "Primary MAC", value: object.primaryMACAddress?.text ?? object.macAddress ?? "—", action: { editingField = .primaryMAC }, identifier: "interfacePrimaryMAC")
                    DetailField(title: "VLAN mode", value: object.mode?.text ?? "—", action: { editingVLAN = true }, identifier: "interfaceField-VLAN mode")
                    DetailField(title: "Untagged VLAN", value: object.untaggedVLAN?.text ?? "—", action: { editingVLAN = true }, identifier: "interfaceField-Untagged VLAN")
                    DetailField(title: "Tagged VLANs", value: object.taggedVLANs?.map(\.text).joined(separator: ", ") ?? "—", action: { editingVLAN = true }, identifier: "interfaceField-Tagged VLANs")
                }
                .disabled(!canEdit)
                if let macs = object.macAddresses, !macs.isEmpty {
                    Section("MAC addresses") {
                        ForEach(Array(macs.enumerated()), id: \.offset) { _, mac in
                            if let id = mac.id, id > 0 {
                                NavigationLink { MACDetailView(client: service.client, id: id) } label: { Text(mac.text).monospaced() }
                            } else { Text(mac.text).monospaced() }
                        }
                    }
                }
                if service.kind == .physical {
                    Section("Direct peers") { peers(object.linkPeers ?? [], type: object.linkPeersType) }
                    Section("Connected endpoints") {
                        DetailField(title: "Reachable", value: object.connectedEndpointsReachable.map { $0 ? L10n.text("Yes") : L10n.text("No") } ?? "—")
                        peers(object.connectedEndpoints ?? [], type: object.connectedEndpointsType)
                    }
                }
                Section("Description") {
                    DetailField(title: "Description", value: object.description?.isEmpty == false ? object.description ?? "" : "—", action: { editingField = .description }, identifier: "interfaceDescription")
                }.disabled(!canEdit)
            }
        }
        .disabled(model.isLoading)
        .navigationTitle("Interface").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object, let parentID = service.parent(object)?.id, parentID > 0 {
                StructuredEditView(client: service.client,
                    target: StructuredEditTarget(collection: service.kind == .physical ? .physicalInterfaces : .virtualInterfaces,
                                                 id: object.id, parentID: parentID), field: field)
            }
        }
        .sheet(isPresented: $editingVLAN, onDismiss: { refreshID = UUID() }) {
            if let object = model.object, let parent = service.parent(object)?.id, parent > 0 {
                VLANEditView(client: service.client, target: StructuredEditTarget(collection: service.kind == .physical ? .physicalInterfaces : .virtualInterfaces, id: object.id, parentID: parent))
            }
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss() } else { refreshID = UUID() } }) {
            if let object = model.object, let parent = service.parent(object)?.id, parent > 0 {
                DeletionView(client: service.client, target: DeletionTarget(collection: service.kind == .physical ? .physicalInterfaces : .virtualInterfaces, id: object.id, parentID: parent)) { deleted = true; onDeleted?() }
            }
        }
        .toolbar {
            Menu {
                Button("Delete object", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteObject")
                Button("Edit name") { editingField = .name }.accessibilityIdentifier("editInterfaceName")
                Button("Edit description") { editingField = .description }.accessibilityIdentifier("editInterfaceDescription")
                if service.kind == .physical { Button("Edit type") { editingField = .type }.accessibilityIdentifier("editInterfaceType") }
                Button("Edit enabled") { editingField = .enabled }.accessibilityIdentifier("editEnabled")
                Button("Edit primary MAC") { editingField = .primaryMAC }.accessibilityIdentifier("editPrimaryMAC")
                Button("Edit VLAN configuration") { editingVLAN = true }.accessibilityIdentifier("editVLAN")
                Button("Edit MTU") { editingField = .mtu }.accessibilityIdentifier("editMTU")
            } label: { Label("Edit", systemImage: "square.and.pencil") }
            .disabled(model.isLoading || model.object.flatMap({ service.parent($0)?.id }).map({ $0 > 0 }) != true)
            .accessibilityIdentifier("editInterface")
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }.disabled(model.isLoading)
        }
        .task(id: refreshID) { await model.reload() }.refreshable { await model.reload() }
    }
    @ViewBuilder private func peers(_ peers: [InterfacePeer], type: String?) -> some View {
        if peers.isEmpty { Text("No visible endpoints").foregroundStyle(.secondary) }
        ForEach(Array(peers.enumerated()), id: \.offset) { _, peer in
            if let type, let kind = InterfaceKind(rawValue: type), peer.id > 0 {
                NavigationLink {
                    InterfaceDetailView(service: InterfaceService(client: service.client, kind: kind), id: peer.id)
                } label: { Label(peer.title, systemImage: "network") }
            } else { Label(peer.title, systemImage: "cable.connector") }
        }
    }
}

struct CableDetailView: View {
    let client: APIClient
    var onDeleted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var model: ReadDetailModel<CableObject>
    @State private var refreshID = UUID()
    @State private var deleting = false
    @State private var deleted = false
    @State private var editingField: EditableTextField?
    @State private var movingSide: CableSide?
    init(client: APIClient, id: Int, onDeleted: (() -> Void)? = nil) {
        self.client = client
        self.onDeleted = onDeleted
        _model = State(initialValue: ReadDetailModel(fetch: {
            guard id > 0 else { throw APIError.invalidURL }
            let cable: CableObject = try await client.get("dcim/cables/\(id)/")
            try cable.validate()
            guard cable.id == id else { throw APIError.invalidResponse }
            return cable
        }))
    }
    var body: some View {
        List {
            if model.isLoading { ProgressView("Loading…") }
            if let error = model.errorMessage {
                StatusMessage(message: error)
                if model.object != nil { Text("Previously loaded details").font(.caption).foregroundStyle(.secondary) }
                Button("Retry") { refreshID = UUID() }
            }
            if let cable = model.object {
                Section("Overview") {
                    Label(cable.label?.isEmpty == false ? (cable.label ?? "") : cable.display ?? L10n.identifier("Cable #%ld", cable.id), systemImage: "cable.connector")
                        .font(.title3.bold()).accessibilityIdentifier("cableTitle")
                    DetailField(title: "Label", value: cable.label?.isEmpty == false ? cable.label ?? "" : "—", action: { editingField = .label }, identifier: "cableField-label")
                    DetailField(title: "Status", value: cable.status?.text ?? "—", action: { editingField = .status }, identifier: "cableField-status")
                    DetailField(title: "Type", value: EditableTextField.type.displayValue(cable.type ?? ""), action: { editingField = .type }, identifier: "cableField-type")
                    DetailField(title: "Color", value: EditableTextField.color.displayValue(cable.color ?? ""), action: { editingField = .color }, identifier: "cableField-color")
                    DetailField(title: "Length", value: cable.length?.text ?? "—", action: { editingField = .length }, identifier: "cableField-length")
                    DetailField(title: "Length unit", value: cable.lengthUnit?.text ?? L10n.text("None"), action: { editingField = .lengthUnit }, identifier: "cableField-lengthUnit")
                }
                Section("Connection overview") { CableDiagram(client: client, cable: cable) }
                Section("Side A") { terminations(cable.aTerminations ?? []) }
                Section("Side B") { terminations(cable.bTerminations ?? []) }
                if let tenant = cable.tenant, let id = tenant.id, id > 0 {
                    Section("Tenant") { NavigationLink { ContextDetailView(service: ContextService(client: client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: ContextKind.tenants.symbol) } }
                }
                if let bundle = cable.bundle { Section("Cable bundle") { Text(bundle.text) } }
                Section("Description") { DetailField(title: "Description", value: cable.description?.isEmpty == false ? cable.description ?? "" : "—", action: { editingField = .description }, identifier: "cableField-description") }
                Section("Comments") { DetailField(title: "Comments", value: cable.comments?.isEmpty == false ? cable.comments ?? "" : "—", action: { editingField = .comments }, identifier: "cableField-comments") }
            }
        }
        .navigationTitle("Cable").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $movingSide, onDismiss: { refreshID = UUID() }) { side in
            // The originating list or port no longer holds this cable once an end moved.
            if let cable = model.object { CableRewireView(client: client, cableID: cable.id, side: side) { onDeleted?() } }
        }
        .sheet(item: $editingField, onDismiss: { refreshID = UUID() }) { field in
            if let cable = model.object { TextEditView(client: client, target: TextEditTarget(collection: .cables, id: cable.id), field: field) }
        }
        .sheet(isPresented: $deleting, onDismiss: { if deleted { dismiss(); onDeleted?() } else { refreshID = UUID() } }) {
            if let cable = model.object { DeletionView(client: client, target: .init(collection: .cables, id: cable.id)) { deleted = true } }
        }
        .toolbar {
            if model.object != nil, !model.isLoading, model.errorMessage == nil {
                Menu {
                    ForEach([EditableTextField.label, .status, .type, .color, .length, .lengthUnit, .description, .comments]) { field in
                        Button(field.editTitle) { editingField = field }.accessibilityIdentifier("editCable-\(field.rawValue)")
                    }
                    Divider()
                    ForEach(CableSide.allCases) { side in
                        Button(L10n.format("Move end %@", side.title), systemImage: "arrow.triangle.swap") { movingSide = side }.accessibilityIdentifier("moveCableEnd-\(side.rawValue)")
                    }
                } label: { Label("Edit", systemImage: "pencil") }.accessibilityIdentifier("editCable")
                Button("Delete cable", systemImage: "trash", role: .destructive) { deleting = true }.accessibilityIdentifier("deleteCable")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }.disabled(model.isLoading)
        }
        .task(id: refreshID) { await model.reload() }.refreshable { await model.reload() }
    }
    @ViewBuilder private func terminations(_ values: [CableTermination]) -> some View {
        if values.isEmpty { Text("No visible terminations").foregroundStyle(.secondary) }
        ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            if let kind = InterfaceKind(rawValue: value.objectType), value.objectID > 0,
               value.object?.id == value.objectID {
                NavigationLink {
                    InterfaceDetailView(service: InterfaceService(client: client, kind: kind), id: value.objectID)
                } label: { Label(value.object?.title ?? L10n.text("Interface"), systemImage: "network") }
                .accessibilityIdentifier("cableTermination-\(index)-\(value.objectID)")
            } else { Text(value.object?.title ?? "\(value.objectType) #\(value.objectID)") }
        }
    }
}
