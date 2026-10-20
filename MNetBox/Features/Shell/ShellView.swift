import SwiftUI

struct ShellView: View {
    let model: ConnectionModel
    private enum TabSection: Hashable { case home, inventory, ipam, search }
    @State private var section: TabSection = .home
    @State private var homeID = UUID()
    @State private var inventoryID = UUID()
    @State private var ipamID = UUID()
    @State private var searchID = UUID()

    // Re-selecting a tab returns to its root; switching sections keeps their navigation.
    private var selection: Binding<TabSection> {
        Binding(get: { section }, set: { next in
            if next == .home { homeID = UUID() }
            else if next == section {
                switch next {
                case .inventory: inventoryID = UUID()
                case .ipam: ipamID = UUID()
                case .search: searchID = UUID()
                case .home: break
                }
            }
            section = next
        })
    }
    var body: some View {
        if let client = model.client {
            TabView(selection: selection) {
                NavigationStack {
                    DashboardView(client: client, connection: model)
                }.id(homeID)
                    .tabItem { Label("Home", systemImage: "house.fill") }.tag(TabSection.home)
                NavigationStack {
                    List {
                        ForEach(InventoryKind.allCases, id: \.self) { kind in
                            NavigationLink {
                                InventoryListView(service: InventoryService(client: client, kind: kind))
                            } label: { Label(kind.title, systemImage: kind.symbol) }
                            .accessibilityIdentifier("inventoryCategory-\(kind.rawValue)")
                        }
                        NavigationLink { MACListView(service: MACService(client: client)) } label: { Label("MAC addresses", systemImage: "network") }.accessibilityIdentifier("inventoryCategory-macAddresses")
                        NavigationLink { CableListView(service: CableService(client: client)) } label: { Label("Cables", systemImage: "cable.connector") }.accessibilityIdentifier("inventoryCategory-cables")
                        Section("Contexts") {
                            ForEach([ContextKind.tenants, .clusters, .clusterGroups, .locations, .regions, .siteGroups, .rackGroups], id: \.self) { kind in
                                NavigationLink { ContextListView(service: ContextService(client: client, kind: kind)) } label: { Label(kind.title, systemImage: kind.symbol) }.accessibilityIdentifier("contextCategory-\(kind.rawValue)")
                            }
                        }
                    }.navigationTitle("Inventory")
                }.id(inventoryID)
                    .tabItem { Label("Inventory", systemImage: "server.rack") }.tag(TabSection.inventory)
                NavigationStack {
                    List {
                        ForEach([IPAMKind.prefixes, .ipAddresses], id: \.self) { kind in
                            NavigationLink {
                                IPAMListView(service: IPAMService(client: client, kind: kind))
                            } label: { Label(kind.title, systemImage: kind == .prefixes ? "square.stack.3d.up.fill" : "network") }
                            .accessibilityIdentifier("ipamCategory-\(kind.rawValue)")
                        }
                        NavigationLink { IPRangeListView(client: client) } label: { Label("IP ranges", systemImage: "arrow.left.and.right") }.accessibilityIdentifier("ipamCategory-ipRanges")
                        ForEach(VLANBrowseKind.allCases, id: \.self) { kind in
                            NavigationLink { VLANListView(service: VLANBrowseService(client: client, kind: kind)) } label: { Label(kind.title, systemImage: kind == .vlans ? "square.stack.3d.up" : "folder") }.accessibilityIdentifier("ipamCategory-\(kind.rawValue)")
                        }
                        Section("Contexts") {
                            ForEach([ContextKind.vrfs, .tenants, .roles], id: \.self) { kind in
                                NavigationLink { ContextListView(service: ContextService(client: client, kind: kind)) } label: { Label(kind.title, systemImage: kind.symbol) }.accessibilityIdentifier("contextCategory-\(kind.rawValue)")
                            }
                        }
                    }.navigationTitle("IPAM")
                }.id(ipamID)
                    .tabItem { Label("IPAM", systemImage: "network") }.tag(TabSection.ipam)
                NavigationStack { GlobalSearchView(client: client) }.id(searchID)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(TabSection.search)
            }
        }
    }
}
