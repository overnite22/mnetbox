import SwiftUI

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dashboard: DashboardModel
    @State private var refreshID = UUID()
    let connection: ConnectionModel
    let client: APIClient

    init(client: APIClient, connection: ConnectionModel) {
        _dashboard = State(initialValue: DashboardModel(client: client))
        self.connection = connection
        self.client = client
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionHeader
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(DashboardMetric.allCases) { metric in
                        if metric == .prefixes || metric == .ipAddresses {
                            NavigationLink {
                                IPAMListView(service: IPAMService(client: client, kind: metric == .prefixes ? .prefixes : .ipAddresses))
                            } label: { metricCard(metric) }
                            .accessibilityIdentifier("browse-\(metric.rawValue)")
                        } else if let kind = InventoryKind(rawValue: metric.rawValue) {
                            NavigationLink {
                                InventoryListView(service: InventoryService(client: client, kind: kind))
                            } label: { metricCard(metric) }
                            .accessibilityIdentifier("browse-\(metric.rawValue)")
                        }
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    if let updated = dashboard.lastUpdated {
                        Label(L10n.format("Last checked %@", updated.formatted(date: .omitted, time: .shortened)), systemImage: "clock")
                    }
                    Text("Totals include objects visible to your account.")
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(size.isAccessibilitySize ? .inline : .large)
        .accessibilityIdentifier("dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AppInformationView(client: client) } label: { Label("App information", systemImage: "info.circle") }.accessibilityIdentifier("appInformation")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Disconnect", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { connection.disconnect() }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    // SwiftUI owns the loading task, including cancellation when this view disappears.
                    refreshID = UUID()
                }
                .disabled(dashboard.isLoading)
                .accessibilityIdentifier("refreshDashboard")
            }
        }
        .task(id: refreshID) { await dashboard.refresh() }
        .refreshable { await dashboard.refresh() }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: size.isAccessibilitySize ? 1 : 2)
    }

    private var connectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Connected to NetBox", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your infrastructure at a glance")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                AppVersionLabel()
            }
            Spacer(minLength: 0)
            if !size.isAccessibilitySize {
                Image(systemName: "network")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(12)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private func metricCard(_ metric: DashboardMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: metric.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color(metric))
                    .frame(width: 38, height: 38)
                    .background(color(metric).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)
            if case .count(let count) = dashboard.values[metric] {
                Text(count, format: .number)
                    .font(.largeTitle.weight(.bold)).monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: count)
                    .accessibilityIdentifier("dashboardCount-\(metric.rawValue)")
            } else if dashboard.isLoading {
                ProgressView().frame(minHeight: 38)
                    .accessibilityLabel(L10n.format("Loading %@", metric.title))
            } else {
                Text("—").font(.largeTitle).foregroundStyle(.secondary)
            }
            Text(metric.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !dashboard.isLoading, case .failed(let message) = dashboard.values[metric] {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboardError-\(metric.rawValue)")
            }
            if dashboard.isLoading, dashboard.values[metric] != nil {
                ProgressView().accessibilityLabel(L10n.format("Loading %@", metric.title))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LinearGradient(colors: [color(metric).opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
    }

    private func color(_ metric: DashboardMetric) -> Color {
        switch metric {
        case .sites: .teal
        case .racks: .indigo
        case .devices: .blue
        case .virtualMachines: .purple
        case .prefixes: .orange
        case .ipAddresses: .cyan
        }
    }
}
