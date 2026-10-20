import SwiftUI

struct InventoryDetailView: View {
    @State private var model: InventoryDetailModel
    @State private var refreshID = UUID()
    @State private var uploadingImage = false
    private struct ImageDeletion: Identifiable { let id: Int }
    @State private var deletingImage: ImageDeletion?
    @State private var editingField: EditableTextField?
    @State private var structuredField: StructuredEditField?
    private let service: InventoryService
    private let kind: InventoryKind
    init(service: InventoryService, id: Int) {
        self.service = service
        kind = service.kind
        _model = State(initialValue: InventoryDetailModel(service: service, id: id))
    }

    private struct Field: Identifiable { let id: String; let value: String }
    private func fields(_ object: InventoryObject) -> [Field] {
        var fields = [Field(id: "ID", value: String(object.id)),
                      Field(id: "Status", value: object.status?.text ?? "—"),
                      Field(id: "Tenant", value: object.tenant?.text ?? "—")]
        switch kind {
        case .sites:
            fields += [Field(id: "Region", value: object.region?.text ?? "—"),
                       Field(id: "Group", value: object.group?.text ?? "—"),
                       Field(id: "Facility", value: object.facility ?? "—"),
                       Field(id: "Physical address", value: object.physicalAddress ?? "—"),
                       Field(id: "Time zone", value: object.timeZone ?? "—")]
        case .racks:
            fields += [Field(id: "Site", value: object.site?.text ?? "—"),
                       Field(id: "Location", value: object.location?.text ?? "—"),
                       Field(id: "Role", value: object.role?.text ?? "—"),
                       Field(id: "Height (U)", value: object.height?.text ?? "—"),
                       Field(id: "Serial", value: object.serial ?? "—"),
                       Field(id: "Asset tag", value: object.assetTag ?? "—")]
        case .devices:
            fields += [Field(id: "Role", value: object.role?.text ?? "—"),
                       Field(id: "Device type", value: object.deviceType?.text ?? "—"),
                       Field(id: "Site", value: object.site?.text ?? "—"),
                       Field(id: "Location", value: object.location?.text ?? "—"),
                       Field(id: "Rack", value: object.rack?.text ?? "—"),
                       Field(id: "Position (U)", value: object.position?.text ?? "—"),
                       Field(id: "Face", value: object.face?.text ?? "—"),
                       Field(id: "Serial", value: object.serial ?? "—"),
                       Field(id: "Asset tag", value: object.assetTag ?? "—"),
                       Field(id: "Platform", value: object.platform?.text ?? "—"),
                       Field(id: "Primary IPv4", value: object.primaryIP4?.text ?? "—"),
                       Field(id: "Primary IPv6", value: object.primaryIP6?.text ?? "—")]
        case .virtualMachines:
            fields += [Field(id: "Site", value: object.site?.text ?? "—"),
                       Field(id: "Cluster", value: object.cluster?.text ?? "—"),
                       Field(id: "Host device", value: object.device?.text ?? "—"),
                       Field(id: "Role", value: object.role?.text ?? "—"),
                       Field(id: "Platform", value: object.platform?.text ?? "—"),
                       Field(id: "vCPUs", value: object.vcpus?.text ?? "—"),
                       Field(id: "Memory (MB)", value: object.memory?.text ?? "—"),
                       Field(id: "Disk (MB)", value: object.disk?.text ?? "—"),
                       Field(id: "Primary IPv4", value: object.primaryIP4?.text ?? "—"),
                       Field(id: "Primary IPv6", value: object.primaryIP6?.text ?? "—")]
        }
        return fields
    }

    private func editAction(_ field: String) -> (() -> Void)? {
        guard kind == .devices || kind == .virtualMachines else { return nil }
        if field == "Status" { return { editingField = .status } }
        let fields: [String: StructuredEditField] = ["Tenant": .tenant, "Role": .role, "Platform": .platform, "Primary IPv4": .primaryIP4, "Primary IPv6": .primaryIP6]
        guard let selected = fields[field] else { return nil }
        return { structuredField = selected }
    }

    @ViewBuilder private func relatedObjects(_ object: InventoryObject) -> some View {
        Section("Explore") {
            if kind == .devices { NavigationLink { PortPanelView(client: service.client, deviceID: object.id, title: object.title) } label: { Label("Port panel", systemImage: "rectangle.split.3x3") }.accessibilityIdentifier("devicePortPanel") }
            if kind == .devices { NavigationLink { CableListView(service: CableService(client: service.client, deviceID: object.id)) } label: { Label("Cables", systemImage: "cable.connector") }.accessibilityIdentifier("deviceCables") }
            if let tenant = object.tenant, let id = tenant.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .tenants), id: id) } label: { Label(tenant.text, systemImage: ContextKind.tenants.symbol) }
            }
            if let location = object.location, let id = location.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .locations), id: id) } label: { Label(location.text, systemImage: ContextKind.locations.symbol) }.accessibilityIdentifier("inventoryLocation")
            }
            if kind == .virtualMachines, let cluster = object.cluster, let id = cluster.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .clusters), id: id) } label: { Label(cluster.text, systemImage: ContextKind.clusters.symbol) }.accessibilityIdentifier("inventoryCluster")
            }
            if kind == .sites, let region = object.region, let id = region.id, id > 0 {
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: .regions), id: id) } label: { Label(region.text, systemImage: ContextKind.regions.symbol) }.accessibilityIdentifier("inventoryRegion")
            }
            if (kind == .sites || kind == .racks), let group = object.group, let id = group.id, id > 0 {
                let groupKind: ContextKind = kind == .sites ? .siteGroups : .rackGroups
                NavigationLink { ContextDetailView(service: ContextService(client: service.client, kind: groupKind), id: id) } label: { Label(group.text, systemImage: groupKind.symbol) }
            }
            if kind == .sites {
                NavigationLink { ContextListView(service: ContextService(client: service.client, kind: .locations, scope: .init(relation: .site, id: object.id, title: object.title))) } label: { Label("Locations", systemImage: ContextKind.locations.symbol) }.accessibilityIdentifier("siteLocations")
                NavigationLink { IPAMListView(service: IPAMService(client: service.client, kind: .prefixes, context: .scope(type: "dcim.site", id: object.id, title: object.title)), allowsCreation: false) } label: { Label("Prefixes", systemImage: "network") }
                NavigationLink { VLANListView(service: VLANBrowseService(client: service.client, kind: .vlans, fixedSite: ReferenceSelection(id: object.id, title: object.title))) } label: { Label("VLANs", systemImage: "square.stack.3d.up") }.accessibilityIdentifier("siteVLANs")
                scopedLink(.racks, scope: InventoryScope(parent: .site, id: object.id, title: object.title))
                scopedLink(.devices, scope: InventoryScope(parent: .site, id: object.id, title: object.title))
            }
            if kind == .racks {
                NavigationLink {
                    RackElevationView(client: service.client, rackID: object.id, title: object.title)
                } label: { Label("Rack elevation", systemImage: "rectangle.split.3x3") }
                .accessibilityIdentifier("rackElevation")
                scopedLink(.devices, scope: InventoryScope(parent: .rack, id: object.id, title: object.title))
            }
            if kind == .devices || kind == .virtualMachines {
                NavigationLink {
                    InterfaceListView(service: InterfaceService(client: service.client,
                        kind: kind == .devices ? .physical : .virtual, parentID: object.id), title: object.title)
                } label: { Label("Interfaces", systemImage: "network") }
                .accessibilityIdentifier("related-interfaces")
            }
            parentLink(object.site, kind: .sites)
            parentLink(object.rack, kind: .racks)
            if kind == .virtualMachines { parentLink(object.device, kind: .devices) }
        }
    }

    private func scopedLink(_ target: InventoryKind, scope: InventoryScope) -> some View {
        NavigationLink {
            InventoryListView(service: InventoryService(client: service.client, kind: target, scope: scope))
        } label: { Label(target.title, systemImage: target.symbol) }
        .accessibilityIdentifier("related-\(target.rawValue)")
    }

    @ViewBuilder private func parentLink(_ relation: NetBoxLabel?, kind target: InventoryKind) -> some View {
        if let relation, let id = relation.id, id > 0 {
            NavigationLink {
                InventoryDetailView(service: InventoryService(client: service.client, kind: target), id: id)
            } label: { Label(relation.text, systemImage: target.symbol) }
            .accessibilityIdentifier("parent-\(target.rawValue)")
        }
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
                Section { InventoryGraphicHeader(kind: kind, object: object) }
                NetBoxImageGallery(client: service.client, kind: kind, id: object.id, deviceTypeID: kind == .devices ? object.deviceType?.id : nil, onAdd: { uploadingImage = true }, onDelete: { deletingImage = ImageDeletion(id: $0) }).id(refreshID)
                relatedObjects(object)
                Section("Overview") {
                    Label(object.title, systemImage: kind.symbol).font(.title3.weight(.semibold)).textSelection(.enabled)
                        .accessibilityIdentifier("inventoryDetailTitle")
                    if kind == .devices || kind == .virtualMachines {
                        DetailField(title: "Name", value: object.name ?? "—", action: { editingField = .name }, identifier: "inventoryField-Name")
                            .disabled(model.isLoading)
                    }
                    ForEach(fields(object)) { field in
                        DetailField(title: field.id, value: field.value, action: editAction(field.id), identifier: "inventoryField-\(field.id)").disabled(model.isLoading)
                    }
                }
                Section("Description") {
                    DetailField(title: "Description", value: object.description?.isEmpty == false ? object.description ?? "" : "—", action: { editingField = .description }, identifier: "inventoryField-Description")
                        .disabled(model.isLoading)
                }
                if let tags = object.tags, !tags.isEmpty {
                    Section("Tags") { Text(tags.map(\.text).joined(separator: ", ")) }
                }
                if let custom = object.customFields, !custom.entries.isEmpty {
                    Section("Custom fields") {
                        ForEach(custom.entries) { DetailField(title: $0.title, value: $0.text, identifier: "customField-\($0.key)") }
                    }.accessibilityIdentifier("customFields")
                }
                Section("Comments") {
                    DetailField(title: "Comments", value: object.comments?.isEmpty == false ? object.comments ?? "" : "—", action: { editingField = .comments }, identifier: "inventoryField-Comments")
                        .disabled(model.isLoading)
                }
            }
        }
        .navigationTitle(kind.singular).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $uploadingImage, onDismiss: { refreshID = UUID() }) {
            if let object = model.object { ImageUploadView(client: service.client, target: .init(kind: kind, id: object.id)) }
        }
        .sheet(item: $deletingImage, onDismiss: { refreshID = UUID() }) { image in
            if let object = model.object { DeletionView(client: service.client, target: .init(collection: .imageAttachments, id: image.id, imageParent: .init(kind: kind, id: object.id)), onDeleted: {}) }
        }
        .sheet(item: $editingField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object, let collection = TextEditTarget.Collection(rawValue: kind.path) {
                TextEditView(client: service.client, target: TextEditTarget(collection: collection, id: object.id), field: field)
            }
        }
        .toolbar {
            Menu {
                if kind == .devices || kind == .virtualMachines {
                    Button("Edit name") { editingField = .name }.accessibilityIdentifier("editName")
                    Button("Edit status") { editingField = .status }.accessibilityIdentifier("editStatus")
                    Button("Edit tenant") { structuredField = .tenant }.accessibilityIdentifier("editTenant")
                    Button("Edit role") { structuredField = .role }.accessibilityIdentifier("editRole")
                    Button("Edit primary IPv4") { structuredField = .primaryIP4 }.accessibilityIdentifier("editPrimaryIPv4")
                    Button("Edit primary IPv6") { structuredField = .primaryIP6 }.accessibilityIdentifier("editPrimaryIPv6")
                    Button("Edit platform") { structuredField = .platform }.accessibilityIdentifier("editPlatform")
                }
                Button("Edit description") { editingField = .description }.accessibilityIdentifier("editDescription")
                Button("Edit comments") { editingField = .comments }.accessibilityIdentifier("editComments")
            } label: { Label("Edit", systemImage: "square.and.pencil") }
            .disabled(model.object == nil || model.isLoading).accessibilityIdentifier("editObject")
            Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }
                .disabled(model.isLoading).accessibilityIdentifier("refreshInventoryDetail")
        }
        .sheet(item: $structuredField, onDismiss: { refreshID = UUID() }) { field in
            if let object = model.object, let collection = StructuredEditTarget.Collection(rawValue: kind.path) {
                StructuredEditView(client: service.client, target: StructuredEditTarget(collection: collection, id: object.id), field: field)
            }
        }
        .task(id: refreshID) { await model.reload() }
        .refreshable { await model.reload() }
    }
}
