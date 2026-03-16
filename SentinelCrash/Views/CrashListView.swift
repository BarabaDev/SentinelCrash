import SwiftUI

struct CrashListView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var filter = CrashFilter()
    @State private var showFilterSheet = false
    @State private var showDeleteAlert = false
    @State private var showHideAllAlert = false
    @State private var selectedLog: CrashLog?
    @State private var scope: CrashVisibilityScope = .visible

    private var filteredLogs: [CrashLog] {
        crashMonitor.filteredLogs(using: filter, scope: scope)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    scopePicker
                    summaryStrip

                    if filteredLogs.isEmpty {
                        emptyState
                    } else {
                        List {
                            ForEach(filteredLogs) { log in
                                NavigationLink(destination: CrashDetailView(log: log)) {
                                    CrashRowView(log: log)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.white.opacity(0.08))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        selectedLog = log
                                        showDeleteAlert = true
                                    } label: {
                                        Label("crashlist.hide".localized, systemImage: "eye.slash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        crashMonitor.toggleFavorite(log)
                                    } label: {
                                        Label(
                                            log.isFavorited ? "crashlist.unfav".localized : "crashlist.favorite".localized,
                                            systemImage: log.isFavorited ? "star.slash" : "star.fill"
                                        )
                                    }
                                    .tint(.yellow)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("crashlist.title".localized)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $filter.searchText, prompt: "crashlist.search".localized)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showFilterSheet = true
                    } label: {
                        Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(filter.isEmpty ? .white : .cyan)
                    }

                    Menu {
                        Button("crashlist.hideAll".localized, role: .destructive) {
                            showHideAllAlert = true
                        }
                        Button("crashlist.rescan".localized) {
                            Task {
                                crashMonitor.resetHiddenCrashes()
                                await crashMonitor.scanForCrashes()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    if !filter.isEmpty {
                        Button("crashlist.reset".localized) {
                            filter = CrashFilter()
                        }
                        .foregroundColor(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(filter: $filter)
            }
            .alert("crashlist.hideAlert.title".localized, isPresented: $showDeleteAlert) {
                Button("crashlist.hide".localized, role: .destructive) {
                    if let log = selectedLog {
                        crashMonitor.deleteCrashLog(log)
                    }
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("crashlist.hideAlert.message".localized)
            }
            .alert("crashlist.hideAllAlert.title".localized, isPresented: $showHideAllAlert) {
                Button("crashlist.hideAll".localized, role: .destructive) {
                    crashMonitor.clearAllCrashes()
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("crashlist.hideAllAlert.message".localized)
            }
        }
    }

    private var scopePicker: some View {
        Picker("analytics.scope".localized, selection: $scope) {
            ForEach(CrashVisibilityScope.allCases) { item in
                Text(item.displayName).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var summaryStrip: some View {
        HStack(spacing: 12) {
            summaryPill(title: "dashboard.visibleShort".localized, value: crashMonitor.crashLogs.count, color: .cyan)
            summaryPill(title: "dashboard.relevantShort".localized, value: crashMonitor.relevantCrashLogs.count, color: .green)
            summaryPill(title: "dashboard.systemShort".localized, value: crashMonitor.systemCrashLogs.count, color: .orange)
            summaryPill(title: "dashboard.noiseShort".localized, value: crashMonitor.noiseCrashLogs.count, color: .gray)
        }
        .padding(.horizontal)
    }

    private func summaryPill(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.gray)
            Text("\(value)").font(.caption.bold()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green.opacity(0.7))

            Text(filter.isEmpty ? "crashlist.noLogs".localized : "crashlist.noResults".localized)
                .font(.title2.bold())
                .foregroundColor(.white)

            Text(filter.isEmpty ?
                 "crashlist.tryScope".localized :
                 "crashlist.tryFilter".localized)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if !filter.isEmpty {
                Button("crashlist.clearFilters".localized) {
                    filter = CrashFilter()
                }
                .foregroundColor(.cyan)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CrashRowView: View {
    let log: CrashLog

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(typeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: log.crashType.icon)
                    .foregroundColor(typeColor)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(log.processName)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if !log.isRead {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 7, height: 7)
                    }

                    if log.isFavorited {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }

                    Spacer()
                }

                HStack(spacing: 6) {
                    badge(text: log.crashType.rawValue, color: typeColor)
                    badge(text: log.category.displayName, color: categoryColor)
                    badge(text: log.severityGroup.displayName, color: severityColor)
                }

                // Crash location — shows WHERE it crashed
                if let location = log.crashLocationShort {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange.opacity(0.7))
                        Text(location)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.8))
                            .lineLimit(1)
                    }
                }

                HStack {
                    if !log.bundleID.isEmpty {
                        Text(log.bundleID)
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(log.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var severityColor: Color {
        switch log.severityGroup {
        case .relevant: return .green
        case .system: return .orange
        case .noise: return .gray
        }
    }

    private var categoryColor: Color {
        switch log.category {
        case .appCrash, .springboard, .jailbreak: return .green
        case .jetsam, .resource, .watchdog, .panic: return .orange
        case .dylib: return .purple
        case .unknown: return .gray
        }
    }

    private var typeColor: Color {
        switch log.crashType.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .gray
        }
    }
}

struct FilterSheet: View {
    @Binding var filter: CrashFilter
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("filter.sortOrder".localized) {
                    Picker("filter.sortBy".localized, selection: $filter.sortOrder) {
                        ForEach(CrashFilter.SortOrder.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                Section("filter.crashTypes".localized) {
                    ForEach(CrashType.allCases, id: \.self) { type in
                        Button(action: {
                            if filter.selectedTypes.contains(type) {
                                filter.selectedTypes.remove(type)
                            } else {
                                filter.selectedTypes.insert(type)
                            }
                        }) {
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                                Spacer()
                                if filter.selectedTypes.contains(type) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section("filter.options".localized) {
                    Toggle("filter.unreadOnly".localized, isOn: $filter.showOnlyUnread)
                    Toggle("filter.favoritesOnly".localized, isOn: $filter.showOnlyFavorited)
                }
            }
            .navigationTitle("filter.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("filter.done".localized) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("crashlist.reset".localized) { filter = CrashFilter() }
                        .foregroundColor(.orange)
                }
            }
        }
    }
}
