import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var showScanAnimation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Header
                    headerCard
                    
                    // MARK: - Quick Stats
                    if let stats = crashMonitor.statistics {
                        statsGrid(stats)
                        if !crashMonitor.relevantCrashLogs.isEmpty,
                           stats.totalCrashes != crashMonitor.crashLogs.count {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                    .font(.caption2)
                                Text("dashboard.statsRelevantOnly".localized)
                                    .font(.caption2)
                            }
                            .foregroundColor(.green.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, -12)
                        }
                    }

                    visibilityCard
                    
                    // MARK: - Jailbreak Status
                    jailbreakStatusCard
                    
                    // MARK: - Recent Crashes
                    recentCrashesCard
                    
                    // MARK: - Crash Type Breakdown
                    crashTypeBreakdownCard
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("dashboard.title".localized)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await crashMonitor.scanForCrashes() }
                    }) {
                        if crashMonitor.isScanning {
                            ProgressView()
                                .tint(.cyan)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                )
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🛡️ SentinelCrash")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("dashboard.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                    Spacer()
                    monitoringStatusBadge
                }
                
                if let lastScan = crashMonitor.lastScanDate {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                            .font(.caption)
                        Text("dashboard.lastScan".localized + ": ") + Text(lastScan, formatter: relativeFormatter)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                }

                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text(crashMonitor.visibilitySummaryText)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
            .padding()
        }
    }
    
    private var monitoringStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(crashMonitor.isMonitoring ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(crashMonitor.isMonitoring ? (showScanAnimation ? 1.3 : 1.0) : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: showScanAnimation)
                .onAppear { showScanAnimation = true }
            
            Text(crashMonitor.isMonitoring ? "dashboard.live".localized : "dashboard.stopped".localized)
                .font(.caption.bold())
                .foregroundColor(crashMonitor.isMonitoring ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(crashMonitor.isMonitoring ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
    }
    
    // MARK: - Stats Grid
    private func statsGrid(_ stats: CrashStatistics) -> some View {
        let isRelevantOnly = !crashMonitor.relevantCrashLogs.isEmpty && stats.totalCrashes != crashMonitor.crashLogs.count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: isRelevantOnly ? "dashboard.relevant".localized : "dashboard.totalCrashes".localized,
                value: "\(stats.totalCrashes)",
                icon: isRelevantOnly ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                color: isRelevantOnly ? .green : .red
            )
            StatCard(
                title: "dashboard.today".localized,
                value: "\(stats.todayCrashes)",
                icon: "calendar",
                color: .orange
            )
            StatCard(
                title: "dashboard.mostCrashed".localized,
                value: stats.mostCrashedProcess ?? "None",
                icon: "app.badge.fill",
                color: .purple
            )
            StatCard(
                title: "dashboard.avgDay".localized,
                value: String(format: "%.1f", stats.averageCrashesPerDay),
                icon: "chart.line.uptrend.xyaxis",
                color: stats.recentTrend == .up ? .red : .green
            )
        }
    }
    

    private var visibilityCard: some View {
        HStack(spacing: 12) {
            StatCard(title: "dashboard.visibleShort".localized, value: "\(crashMonitor.crashLogs.count)", icon: "eye.fill", color: .cyan)
            StatCard(title: "dashboard.relevantShort".localized, value: "\(crashMonitor.relevantCrashLogs.count)", icon: "checkmark.shield.fill", color: .green)
            StatCard(title: "dashboard.systemShort".localized, value: "\(crashMonitor.systemCrashLogs.count)", icon: "gearshape.fill", color: .orange)
            StatCard(title: "dashboard.noiseShort".localized, value: "\(crashMonitor.noiseFilteredCount)", icon: "speaker.slash.fill", color: .gray)
        }
    }

    // MARK: - Jailbreak Status Card
    private var jailbreakStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("dashboard.jbEnvironment".localized, systemImage: "lock.open.fill")
                .font(.headline)
                .foregroundColor(.cyan)
            
            if let jbEnv = crashMonitor.jailbreakEnvironment {
                VStack(spacing: 8) {
                    JBInfoRow(key: "jb.type".localized, value: jbEnv.jailbreakName, color: .green)
                    JBInfoRow(key: "jb.mode".localized, value: "Rootless", color: .cyan)
                    JBInfoRow(key: "jb.root".localized, value: jbEnv.jbRoot, color: .yellow)
                    JBInfoRow(key: "jb.bootstrap".localized, value: jbEnv.procursusStrapped ? "Procursus ✓" : "Unknown", color: .orange)
                    JBInfoRow(key: "jb.deviceIOS".localized, value: jbEnv.deviceIOSVersion, color: .white)
                    JBInfoRow(key: "jb.iosRange".localized, value: jbEnv.supportedIOSMax == "?" ? "\(jbEnv.supportedIOSMin)+" : "\(jbEnv.supportedIOSMin) – \(jbEnv.supportedIOSMax)", color: jbEnv.isIOSInRange ? .green : .orange)
                    if !jbEnv.installedJBTools.isEmpty {
                        JBInfoRow(key: "jb.tools".localized, value: jbEnv.installedJBTools.joined(separator: ", "), color: .purple)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("dashboard.noJB".localized)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Recent Crashes Card
    private var recentCrashesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("dashboard.recentCrashes".localized, systemImage: "clock.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            if crashMonitor.crashLogs.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("dashboard.noCrashes".localized)
                        .foregroundColor(.gray)
                }
            } else {
                ForEach((crashMonitor.relevantCrashLogs.isEmpty ? crashMonitor.crashLogs : crashMonitor.relevantCrashLogs).prefix(5)) { log in
                    NavigationLink(destination: CrashDetailView(log: log)) {
                        MiniCrashRow(log: log)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Crash Type Breakdown
    private var crashTypeBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("dashboard.crashTypes".localized, systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundColor(.purple)
            
            if let stats = crashMonitor.statistics, !stats.crashesByType.isEmpty {
                ForEach(stats.crashesByType.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                    CrashTypeBar(type: type, count: count, total: stats.totalCrashes)
                }
            } else {
                Text("dashboard.noData".localized)
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private var relativeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct JBInfoRow: View {
    let key: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(key)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(color)
            Spacer()
        }
    }
}

struct MiniCrashRow: View {
    let log: CrashLog
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: log.crashType.icon)
                .foregroundColor(typeColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(log.processName)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Text(log.crashType.rawValue)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text(log.timestamp, style: .relative)
                .font(.caption2)
                .foregroundColor(.gray)
            
            if !log.isRead {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 4)
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

struct CrashTypeBar: View {
    let type: CrashType
    let count: Int
    let total: Int
    
    var percentage: Double { total > 0 ? Double(count) / Double(total) : 0 }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(barColor)
                    .font(.caption)
                Text(type.rawValue)
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundColor(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.7))
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 4)
        }
    }
    
    private var barColor: Color {
        switch type.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .gray
        }
    }
}
