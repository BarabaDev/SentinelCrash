import SwiftUI

struct ToolsHubView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Analysis tools
                    sectionHeader(title: "tools.analysis".localized, icon: "magnifyingglass", color: .red)

                    NavigationLink(destination: TweakConflictView()) {
                        toolCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "tools.tweakConflict".localized,
                            subtitle: "tools.tweakConflictDesc".localized,
                            color: .red
                        )
                    }

                    NavigationLink(destination: AutoBlameView()) {
                        toolCard(
                            icon: "person.fill.questionmark",
                            title: "tools.autoBlame".localized,
                            subtitle: "tools.autoBlameDesc".localized,
                            color: .orange
                        )
                    }

                    NavigationLink(destination: CrashGroupListView()) {
                        toolCard(
                            icon: "rectangle.stack.fill",
                            title: "tools.crashGroups".localized,
                            subtitle: "tools.crashGroupsDesc".localized,
                            color: .purple,
                            badge: "\(groupCount)"
                        )
                    }

                    // Visualization
                    sectionHeader(title: "tools.visualization".localized, icon: "chart.xyaxis.line", color: .cyan)

                    NavigationLink(destination: TimelineView()) {
                        toolCard(
                            icon: "calendar.badge.clock",
                            title: "tools.timeline".localized,
                            subtitle: "tools.timelineDesc".localized,
                            color: .orange
                        )
                    }

                    NavigationLink(destination: CrashDiffView()) {
                        toolCard(
                            icon: "arrow.left.and.right",
                            title: "tools.crashDiff".localized,
                            subtitle: "tools.crashDiffDesc".localized,
                            color: .purple
                        )
                    }

                    NavigationLink(destination: LiveConsoleView()) {
                        toolCard(
                            icon: "terminal.fill",
                            title: "tools.liveConsole".localized,
                            subtitle: "tools.liveConsoleDesc".localized,
                            color: .green,
                            badge: crashMonitor.isMonitoring ? "LIVE" : nil
                        )
                    }

                    // Data
                    sectionHeader(title: "tools.data".localized, icon: "externaldrive.fill", color: .green)

                    NavigationLink(destination: ExportView()) {
                        toolCard(
                            icon: "square.and.arrow.up",
                            title: "tools.export".localized,
                            subtitle: "tools.exportDesc".localized,
                            color: .green
                        )
                    }

                    NavigationLink(destination: DpkgPackageListView()) {
                        toolCard(
                            icon: "shippingbox.fill",
                            title: "tools.packages".localized,
                            subtitle: "tools.packagesDesc".localized,
                            color: .cyan
                        )
                    }

                    NavigationLink(destination: JailbreakInfoView()) {
                        toolCard(
                            icon: "lock.open.fill",
                            title: "tools.jbInfo".localized,
                            subtitle: "tools.jbInfoDesc".localized,
                            color: .green,
                            badge: crashMonitor.jailbreakEnvironment != nil ? "OK" : nil
                        )
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("tools.title".localized)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var groupCount: String {
        let grouper = CrashGrouper()
        return "\(grouper.group(crashes: crashMonitor.crashLogs).count)"
    }

    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func toolCard(icon: String, title: String, subtitle: String, color: Color, badge: String? = nil) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.15)))
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.15), lineWidth: 1)))
    }
}

// MARK: - Dpkg Package List View

struct DpkgPackageListView: View {
    @State private var packages: [DpkgPackage] = []
    @State private var isLoading = true
    @State private var search = ""
    @State private var showTweaksOnly = false

    private let dpkgManager = DpkgPackageManager()

    private var filteredPackages: [DpkgPackage] {
        var result = packages
        if showTweaksOnly {
            result = result.filter { $0.isTweak || !$0.providedDylibs.isEmpty }
        }
        if !search.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.identifier.localizedCaseInsensitiveContains(search)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    summaryPill(title: "packages.total".localized, value: "\(packages.count)", color: .cyan)
                    summaryPill(title: "packages.tweaks".localized, value: "\(packages.filter { $0.isTweak }.count)", color: .purple)
                    summaryPill(title: "packages.withDylibs".localized, value: "\(packages.filter { !$0.providedDylibs.isEmpty }.count)", color: .orange)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Toggle("packages.tweaksDylibsOnly".localized, isOn: $showTweaksOnly)
                .font(.caption)
                .tint(.purple)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if isLoading {
                ProgressView("Loading dpkg status…").tint(.cyan).padding(40)
                Spacer()
            } else if filteredPackages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36))
                        .foregroundColor(.gray.opacity(0.5))
                    Text("packages.noPackages".localized)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(40)
                Spacer()
            } else {
                List(filteredPackages) { pkg in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(pkg.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Spacer()
                            Text("v\(pkg.version)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.gray)
                        }
                        Text(pkg.identifier)
                            .font(.caption2.monospaced())
                            .foregroundColor(.cyan.opacity(0.7))
                        if !pkg.section.isEmpty {
                            Text(pkg.section)
                                .font(.caption2)
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.purple.opacity(0.12)))
                        }
                        if !pkg.providedDylibs.isEmpty {
                            let dylibList = pkg.providedDylibs.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                            Text("packages.dylibs".localized + " " + dylibList)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .lineLimit(2)
                        }
                        if let date = pkg.installedDate {
                            let dateStr = date.formatted(date: .abbreviated, time: .shortened)
                            Text("packages.installed".localized + " " + dateStr)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("packages.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, prompt: "packages.search".localized)
        .onAppear { loadPackages() }
    }

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.bold()).foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    }

    private func loadPackages() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let pkgs = dpkgManager.loadInstalledPackages().sorted { $0.name.lowercased() < $1.name.lowercased() }
            DispatchQueue.main.async {
                packages = pkgs
                isLoading = false
            }
        }
    }
}
