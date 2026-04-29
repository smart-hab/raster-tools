//
//  PlanetView.swift
//  RasterTools
//
//  Created by Marek on 2026-03-24.
//

import SwiftUI
import SwiftData

// MARK: - Planet View

struct PlanetView: View {
    @Environment(JobRegistry.self) private var registry
    @State private var subscriptions: [PlanetSubscription] = []
    @State private var orders: [PlanetOrderRecord] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var activeDownload: ToolPlanetDownload?
    @State private var downloadedNames: Set<String> = []

    private var apiKey: String { AppSettings.shared.planetApiKey }
    private var downloadDirectory: URL { AppStorage.planetDownloadDirectory() }

    private func isDownloaded(_ order: PlanetOrderRecord) -> Bool {
        downloadedNames.contains(order.name + ".zip")
    }

    var body: some View {
        Form {
            configurationSection
            subscriptionsSection
            ordersSection
        }
        .formStyle(.grouped)
        .navigationTitle("Planet")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await fetchAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await fetchAll() }
    }

    @ViewBuilder
    private var configurationSection: some View {
        Section("Configuration") {
            LabeledContent("Download Dir") {
                Button {
                    NSWorkspace.shared.open(downloadDirectory)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var subscriptionsSection: some View {
        Section("Subscriptions") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if subscriptions.isEmpty {
                Text("No subscriptions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(subscriptions) { sub in
                    SubscriptionRow(subscription: sub)
                }
            }
        }
    }

    @ViewBuilder
    private var ordersSection: some View {
        Section("Orders") {
            if let error {
                ContentUnavailableView(
                    "Could Not Load Orders",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ResourceTableView(
                    items: orders,
                    itemID: \.id,
                    sortOptions: [
                        TableSortOption(
                            id: "date",
                            label: "Date",
                            comparator: { $0.createdAt < $1.createdAt },
                            groupLabel: { order in
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy"
                                return formatter.string(from: order.createdAt)
                            }
                        ),
                        TableSortOption(
                            id: "status",
                            label: "Status",
                            comparator: { $0.status < $1.status },
                            groupLabel: { order in
                                PlanetOrderStatus(rawValue: order.status)?.displayName ?? order.status.capitalized
                            }
                        )
                    ],
                    filterOptions: PlanetOrderStatus.allCases.map { status in
                        TableFilterOption(
                            id: status.rawValue,
                            label: status.displayName,
                            color: status.color,
                            test: { $0.status == status.rawValue }
                        )
                    },
                    selectionActions: [
                        TableSelectionAction<PlanetOrderRecord>(
                            id: "download",
                            icon: "arrow.down.circle",
                            isEnabled: { selected in
                                selected.contains { $0.status == PlanetOrderStatus.success.rawValue && !isDownloaded($0) }
                            },
                            action: { selected in
                                let tool = ToolPlanetDownload()
                                activeDownload = tool
                                registry.register(runner: tool, configName: "Planet Order", projectName: "")
                                tool.start(orders: selected)
                            }
                        )
                    ],
                    selection: $selection,
                    initialSortOptionID: "date",
                    initialSortAscending: false
                ) { order, isSelected in
                    PlanetOrderRow(order: order, isSelected: isSelected, isDownloaded: isDownloaded(order))
                }
            }
        }
    }

    private func refreshDownloadedNames() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: downloadDirectory.path)) ?? []
        downloadedNames = Set(files)
    }

    private func fetchAll() async {
        isLoading = true
        error = nil
        refreshDownloadedNames()
        async let subs = PlanetAPI.listSubscriptions(apiKey: apiKey)
        async let ords = PlanetAPI.listOrders(apiKey: apiKey)
        subscriptions = (try? await subs) ?? []
        do {
            orders = try await ords
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Subscription Row

private struct SubscriptionRow: View {
    let subscription: PlanetSubscription

    private var barColor: Color {
        switch subscription.fraction {
        case ..<0.50: return .green
        case ..<0.75: return .yellow
        default:      return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: subscription.isActive ? "checkmark.circle.fill" : "circle.slash")
                .foregroundStyle(subscription.isActive ? Color.green : Color.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.plan.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(String(subscription.plan.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            
            VStack {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor)
                            .frame(width: geo.size.width * subscription.fraction)
                    }
                    .frame(height: 8)
                }
                .frame(width: 120, height: 8)
                Text("\(subscription.quotaUsed.formatted()) of \(subscription.quotaSqkm.formatted()) sqkm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Planet Order Row

struct PlanetOrderRow: View {
    let order: PlanetOrderRecord
    let isSelected: Bool
    var isDownloaded: Bool = false

    private var status: PlanetOrderStatus {
        PlanetOrderStatus(rawValue: order.status) ?? .unknown
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(order.name)
                .lineLimit(1)
                .foregroundStyle(isDownloaded ? .secondary : .primary)

            Spacer()

            BadgeCapsule(label: status.displayName, color: status.color)

            Text(order.createdAt.displayString)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)

            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .frame(width: 16)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
