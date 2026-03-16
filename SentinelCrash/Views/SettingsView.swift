import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var showClearAlert = false
    @State private var showClearCloudAlert = false
    @StateObject private var cloudSync = CloudSyncService()
    @State private var isRescanning = false
    @State private var rescanResult: String?
    @State private var showRescanDone = false
    @State private var showHideDone = false
    @State private var hiddenCount = 0

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }

    var body: some View {
        NavigationView {
            Form {
                Section("settings.monitoring".localized) {
                    Toggle("settings.autoScan".localized, isOn: $settings.autoScanEnabled)
                    HStack {
                        Text("settings.scanInterval".localized)
                        Spacer()
                        Text("\(Int(settings.scanInterval))s")
                            .foregroundColor(.gray)
                    }
                    Slider(value: $settings.scanInterval, in: 10...120, step: 10)
                        .tint(.cyan)
                    Toggle("settings.showSystem".localized, isOn: $settings.showSystemProcesses)
                    Toggle("settings.jbOnly".localized, isOn: $settings.showJBCrashesOnly)
                }

                Section("settings.notifications".localized) {
                    Toggle("settings.newCrashAlerts".localized, isOn: $settings.notificationsEnabled)
                }

                Section("settings.filtering".localized) {
                    Toggle("settings.hideNoise".localized, isOn: $settings.hideNoiseLogs)
                    Toggle("settings.preferRelevant".localized, isOn: $settings.preferRelevantDashboardStats)
                }

                Section("settings.logRetention".localized) {
                    HStack {
                        Text("settings.maxLogAge".localized)
                        Spacer()
                        Text("settings.days".localized(settings.maxLogAge))
                            .foregroundColor(.gray)
                    }
                    Stepper("", value: $settings.maxLogAge, in: 1...90)
                }

                Section("settings.cloudSync".localized) {
                    Toggle("settings.syncEnabled".localized, isOn: $cloudSync.syncEnabled)
                    HStack {
                        Text("settings.syncStatus".localized)
                        Spacer()
                        Text(cloudSync.syncStatus)
                            .foregroundColor(cloudSync.syncStatus == "Synced" ? .green : .gray)
                            .font(.caption)
                    }
                    if let lastSync = cloudSync.lastSyncDate {
                        HStack {
                            Text("settings.lastSync".localized)
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    Button(action: {
                        cloudSync.pushToCloud(
                            readPaths: crashMonitor.readPathSet,
                            hiddenPaths: crashMonitor.hiddenPathSet,
                            favoritePaths: crashMonitor.favoritePathSet
                        )
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("settings.syncNow".localized)
                        }
                    }
                    .foregroundColor(.cyan)
                    .disabled(!cloudSync.syncEnabled)

                    Button(action: { showClearCloudAlert = true }) {
                        HStack {
                            Image(systemName: "icloud.slash")
                            Text("settings.clearCloud".localized)
                        }
                    }
                    .foregroundColor(.red)
                    .disabled(!cloudSync.syncEnabled)
                }

                Section {
                    // Live stats row
                    HStack(spacing: 16) {
                        dataStatPill(label: "settings.indexed".localized, value: crashMonitor.indexedCrashCount, color: .cyan)
                        dataStatPill(label: "dashboard.visibleShort".localized, value: crashMonitor.crashLogs.count, color: .green)
                        dataStatPill(label: "dashboard.noiseShort".localized, value: crashMonitor.noiseFilteredCount, color: .orange)
                        dataStatPill(label: "dashboard.hidden".localized, value: crashMonitor.userHiddenCount, color: .gray)
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)

                    // Rescan button
                    Button(action: {
                        isRescanning = true
                        rescanResult = nil
                        let beforeCount = crashMonitor.indexedCrashCount
                        crashMonitor.resetHiddenCrashes()
                        Task {
                            await crashMonitor.scanForCrashes()
                            let afterCount = crashMonitor.indexedCrashCount
                            let newFound = max(0, afterCount - beforeCount)
                            rescanResult = newFound > 0 ? "settings.foundNew".localized(afterCount, newFound) : "settings.found".localized(afterCount)
                            isRescanning = false
                            showRescanDone = true
                            // Auto-dismiss after 3s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { showRescanDone = false }
                            }
                        }
                    }) {
                        HStack {
                            if isRescanning {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.cyan)
                                Text("settings.scanning".localized)
                                    .foregroundColor(.cyan)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("settings.rescanAll".localized)
                            }
                            Spacer()
                            if showRescanDone, let result = rescanResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .foregroundColor(.cyan)
                    .disabled(isRescanning)

                    // Hide all button
                    Button(action: {
                        hiddenCount = crashMonitor.indexedCrashCount
                        showClearAlert = true
                    }) {
                        HStack {
                            Image(systemName: "eye.slash")
                            Text("settings.hideAllLogs".localized)
                            Spacer()
                            if showHideDone {
                                Text("settings.hidden".localized(hiddenCount))
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .foregroundColor(.red)

                    // Monitored paths info
                    HStack {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Text("settings.monitoredPaths".localized)
                            .font(.subheadline)
                        Spacer()
                        Text("settings.active".localized(crashMonitor.existingMonitoredPaths.count, crashMonitor.monitoredPaths.count))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } header: {
                    Text("settings.data".localized)
                } footer: {
                    if let lastScan = crashMonitor.lastScanDate {
                        Text("settings.lastScan".localized + " " + lastScan.formatted(date: .omitted, time: .standard))
                    }
                }

                Section("settings.about".localized) {
                    HStack {
                        Text("settings.version".localized)
                        Spacer()
                        Text(appVersion).foregroundColor(.gray)
                    }
                    HStack {
                        Text("settings.author".localized)
                        Spacer()
                        Text("BarabaDev").foregroundColor(.cyan)
                    }
                    HStack {
                        Text("Twitter")
                        Spacer()
                        Text("@BarabaDev").foregroundColor(.cyan)
                    }
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Text("github.com/BarabaDev").foregroundColor(.cyan)
                    }
                    HStack {
                        Text("settings.jbSupport".localized)
                        Spacer()
                        Text("Rootless (/var/jb)").foregroundColor(.cyan)
                    }
                    HStack {
                        Text("iOS")
                        Spacer()
                        Text("15.0+").foregroundColor(.gray)
                    }
                    NavigationLink(destination: AboutView()) {
                        Text("settings.aboutApp".localized)
                    }
                }
            }
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.large)
            .alert("crashlist.hideAllAlert.title".localized, isPresented: $showClearAlert) {
                Button("crashlist.hideAll".localized + " (\(hiddenCount))", role: .destructive) {
                    crashMonitor.clearAllCrashes()
                    showHideDone = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation { showHideDone = false }
                    }
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("crashlist.hideAllAlert.message".localized)
            }
            .alert("settings.clearCloud".localized, isPresented: $showClearCloudAlert) {
                Button("common.confirm".localized, role: .destructive) {
                    cloudSync.clearCloudData()
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("settings.clearCloudMsg".localized)
            }
        }
    }

    private func dataStatPill(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}
