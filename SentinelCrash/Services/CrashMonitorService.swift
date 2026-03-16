import Foundation
import Combine
import Dispatch
import Darwin
import UIKit
import UserNotifications

// MARK: - CrashMonitorService

enum CrashVisibilityScope: String, CaseIterable, Identifiable {
    case visible = "Visible"
    case relevant = "Relevant"
    case system = "System"
    case noise = "Noise"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visible: return "dashboard.visible".localized
        case .relevant: return "dashboard.relevant".localized
        case .system: return "dashboard.system".localized
        case .noise: return "dashboard.noise".localized
        }
    }
}

@MainActor
final class CrashMonitorService: ObservableObject {

    // MARK: - Published Properties
    @Published private(set) var crashLogs: [CrashLog] = []
    @Published private(set) var indexedCrashLogs: [CrashLog] = []
    @Published var isMonitoring: Bool = false
    @Published var lastScanDate: Date?
    @Published var statistics: CrashStatistics?
    @Published var isScanning: Bool = false
    @Published var jailbreakEnvironment: JailbreakEnvironment?
    @Published var newCrashCount: Int = 0

    // MARK: - Private
    private var fileWatcher: FileSystemWatcher?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var allCrashLogs: [CrashLog] = []
    private var notifiedFilePaths = Set<String>()
    private weak var settings: SettingsManager?
    private let parser = CrashLogParser()
    private let jailbreakDetector = JailbreakDetector()

    // MARK: - Crash log paths
    // Verified on rootless jailbreaks (NathanLR, Dopamine, palera1n).
    // Primary paths confirmed via terminal, fallback paths kept for other setups.
    private let crashLogPaths: [String] = [
        "/var/mobile/Library/Logs/CrashReporter",
        "/var/mobile/Library/Logs/CrashReporter/Panics",
        "/var/db/diagnostics",
        "/var/jb/var/log",
        "/var/jb/usr/libexec",
        "/var/jb/etc",
        "/var/jb/var/mobile/Library/Preferences",
        "/private/var/root/Library/Logs",
        "/private/var/logs/AppleSupport",
        "/var/mobile/Library/Logs/DiagnosticPipeline",
        "/var/mobile/Library/Logs/CrashReporter/Retired",
        "/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
    ]

    private let hiddenPathsKey = "hiddenCrashPaths"
    private var hiddenFilePaths: Set<String> = []

    private let readPathsKey = "readCrashPaths"
    private var readFilePaths: Set<String> = []

    // MARK: - Init
    init() {
        loadHiddenPaths()
        loadReadPaths()
        detectJailbreakEnvironment()
    }

    var monitoredPaths: [String] {
        crashLogPaths
    }

    var existingMonitoredPaths: [String] {
        crashLogPaths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    var indexedCrashCount: Int { allCrashLogs.count }
    var hiddenCrashCount: Int { max(0, indexedCrashCount - crashLogs.count) }
    var noiseFilteredCount: Int { allCrashLogs.filter { $0.severityGroup == .noise }.count }
    var userHiddenCount: Int { hiddenFilePaths.count }
    var relevantCrashLogs: [CrashLog] { crashLogs.filter { $0.severityGroup == .relevant } }
    var systemCrashLogs: [CrashLog] { crashLogs.filter { $0.severityGroup == .system } }
    var noiseCrashLogs: [CrashLog] { indexedCrashLogs.filter { $0.severityGroup == .noise && !hiddenFilePaths.contains($0.filePath) } }
    var visibilitySummaryText: String { "dashboard.showing".localized(crashLogs.count, indexedCrashCount) }

    // Cloud sync accessors
    var readPathSet: Set<String> { readFilePaths }
    var hiddenPathSet: Set<String> { hiddenFilePaths }
    var favoritePathSet: Set<String> { Set(allCrashLogs.filter { $0.isFavorited }.map { $0.filePath }) }

    func configure(with settings: SettingsManager) {
        guard self.settings == nil else {
            applySettings()
            return
        }

        self.settings = settings

        settings.$autoScanEnabled
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$scanInterval
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$notificationsEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled {
                    self?.requestNotificationAuthorizationIfNeeded()
                }
            }
            .store(in: &cancellables)
        settings.$showJBCrashesOnly
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$maxLogAge
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$showSystemProcesses
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$hideNoiseLogs
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        settings.$preferRelevantDashboardStats
            .dropFirst()
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        applySettings()
    }

    // MARK: - Public Methods
    func startMonitoring() {
        guard !isMonitoring else {
            scheduleTimerIfNeeded()
            return
        }

        isMonitoring = true

        Task { @MainActor in
            await scanForCrashes()
        }

        setupFileWatcher()
        scheduleTimerIfNeeded()
    }

    func stopMonitoring() {
        isMonitoring = false
        fileWatcher?.stop()
        fileWatcher = nil
        timer?.invalidate()
        timer = nil
    }

    func scanForCrashes() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        var scannedLogs: [CrashLog] = []

        for path in crashLogPaths {
            let logs = await scanDirectory(path)
            scannedLogs.append(contentsOf: logs)
        }

        let unique = Dictionary(grouping: scannedLogs, by: { $0.filePath })
            .compactMapValues { $0.max(by: { $0.timestamp < $1.timestamp }) }
            .values
            .filter { !hiddenFilePaths.contains($0.filePath) }
            .sorted { $0.timestamp > $1.timestamp }

        let previousPaths = Set(allCrashLogs.map { $0.filePath })
        let newPaths = Set(unique.map { $0.filePath })
        let inserted = unique.filter { !previousPaths.contains($0.filePath) }
        let hasChanges = previousPaths != newPaths

        // CRITICAL: Only update @Published arrays if content actually changed.
        // Otherwise SwiftUI re-renders ForEach → NavigationLink pops → user loses detail view.
        if hasChanges {
            allCrashLogs = Array(unique)
            indexedCrashLogs = Array(unique)

            // Restore read state from persisted data
            for idx in allCrashLogs.indices {
                if readFilePaths.contains(allCrashLogs[idx].filePath) {
                    allCrashLogs[idx].isRead = true
                }
            }
            for idx in indexedCrashLogs.indices {
                if readFilePaths.contains(indexedCrashLogs[idx].filePath) {
                    indexedCrashLogs[idx].isRead = true
                }
            }

            pruneExpiredLogsIfNeeded()
            applyVisibilityFilters()
        }

        lastScanDate = Date()
        newCrashCount = inserted.count

        if !inserted.isEmpty {
            notifyAboutNewCrashes(inserted)
        }
    }

    func deleteCrashLog(_ log: CrashLog) {
        hiddenFilePaths.insert(log.filePath)
        saveHiddenPaths()
        allCrashLogs.removeAll { $0.id == log.id || $0.filePath == log.filePath }
        indexedCrashLogs.removeAll { $0.id == log.id || $0.filePath == log.filePath }
        crashLogs.removeAll { $0.id == log.id || $0.filePath == log.filePath }
        updateStatistics(using: crashLogs)
    }

    func markAsRead(_ log: CrashLog) {
        guard !readFilePaths.contains(log.filePath) else { return }
        readFilePaths.insert(log.filePath)
        saveReadPaths()
        if let idx = allCrashLogs.firstIndex(where: { $0.filePath == log.filePath }) {
            allCrashLogs[idx].isRead = true
        }
        if let idx = crashLogs.firstIndex(where: { $0.filePath == log.filePath }) {
            crashLogs[idx].isRead = true
        }
    }

    func toggleFavorite(_ log: CrashLog) {
        if let idx = allCrashLogs.firstIndex(where: { $0.filePath == log.filePath }) {
            allCrashLogs[idx].isFavorited.toggle()
        }
        if let idx = crashLogs.firstIndex(where: { $0.filePath == log.filePath }) {
            crashLogs[idx].isFavorited.toggle()
        }
    }

    func clearAllCrashes() {
        // Hide from SentinelCrash without deleting original system crash logs from disk.
        hiddenFilePaths.formUnion(allCrashLogs.map(\.filePath))
        saveHiddenPaths()
        readFilePaths.removeAll()
        saveReadPaths()
        allCrashLogs = []
        indexedCrashLogs = []
        crashLogs = []
        updateStatistics(using: [])
    }

    func resetHiddenCrashes() {
        hiddenFilePaths.removeAll()
        saveHiddenPaths()
        readFilePaths.removeAll()
        saveReadPaths()
    }

    func logs(for scope: CrashVisibilityScope) -> [CrashLog] {
        switch scope {
        case .visible:
            return crashLogs
        case .relevant:
            return indexedCrashLogs.filter { $0.severityGroup == .relevant && !hiddenFilePaths.contains($0.filePath) }
        case .system:
            return indexedCrashLogs.filter { $0.severityGroup == .system && !hiddenFilePaths.contains($0.filePath) }
        case .noise:
            return indexedCrashLogs.filter { $0.severityGroup == .noise && !hiddenFilePaths.contains($0.filePath) }
        }
    }

    func filteredLogs(using filter: CrashFilter, scope: CrashVisibilityScope = .visible) -> [CrashLog] {
        var result = logs(for: scope)

        if !filter.searchText.isEmpty {
            let query = filter.searchText.lowercased()
            result = result.filter {
                $0.processName.localizedCaseInsensitiveContains(query) ||
                $0.bundleID.localizedCaseInsensitiveContains(query) ||
                $0.exception.localizedCaseInsensitiveContains(query) ||
                (query.count >= 3 && String($0.rawContent.prefix(10_000)).localizedCaseInsensitiveContains(query))
            }
        }

        if !filter.selectedTypes.isEmpty {
            result = result.filter { filter.selectedTypes.contains($0.crashType) }
        }

        if filter.showOnlyUnread {
            result = result.filter { !$0.isRead }
        }

        if filter.showOnlyFavorited {
            result = result.filter { $0.isFavorited }
        }

        if !filter.processName.isEmpty {
            result = result.filter { $0.processName.localizedCaseInsensitiveContains(filter.processName) }
        }

        switch filter.sortOrder {
        case .newest:
            result.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            result.sort { $0.timestamp < $1.timestamp }
        case .processName:
            result.sort { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
        case .severity:
            result.sort { $0.crashType.severity > $1.crashType.severity }
        }

        return result
    }

    // MARK: - Private Methods
    private func scanDirectory(_ path: String) async -> [CrashLog] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return [] }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var logs: [CrashLog] = []
        let urls = (enumerator.allObjects as? [URL]) ?? []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else { continue }

            let filename = url.lastPathComponent.lowercased()
            guard filename.hasSuffix(".ips") || filename.hasSuffix(".crash") || filename.hasSuffix(".log") || filename.hasSuffix(".txt") || filename.hasSuffix(".diag") else {
                continue
            }

            if let log = await parseFile(at: url.path), shouldIndexLog(log) {
                logs.append(log)
            }
        }

        return logs
    }

    private func parseFile(at path: String) async -> CrashLog? {
        // Guard against oversized files (>5MB) to prevent memory issues
        let maxFileSize: UInt64 = 5_000_000
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? UInt64, fileSize > maxFileSize {
            return nil
        }

        let parser = self.parser
        let jbEnv = self.jailbreakEnvironment
        return await Task.detached(priority: .background) {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                guard let data = FileManager.default.contents(atPath: path),
                      let content = String(data: data, encoding: .isoLatin1) else {
                    return nil
                }
                return parser.parse(content: content, filePath: path, jbEnv: jbEnv)
            }
            return parser.parse(content: content, filePath: path, jbEnv: jbEnv)
        }.value
    }

    private func detectJailbreakEnvironment() {
        jailbreakEnvironment = jailbreakDetector.detect()
    }

    private func setupFileWatcher() {
        fileWatcher?.stop()
        fileWatcher = FileSystemWatcher(paths: crashLogPaths) { [weak self] in
            Task { @MainActor in
                await self?.scanForCrashes()
            }
        }
        fileWatcher?.start()
    }

    private func scheduleTimerIfNeeded() {
        timer?.invalidate()
        timer = nil

        guard isMonitoring else { return }
        guard settings?.autoScanEnabled ?? true else { return }

        let interval = max(10.0, settings?.scanInterval ?? 30.0)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.scanForCrashes()
            }
        }
    }

    private func applySettings() {
        requestNotificationAuthorizationIfNeeded()
        pruneExpiredLogsIfNeeded()
        applyVisibilityFilters()
        scheduleTimerIfNeeded()
    }

    private func pruneExpiredLogsIfNeeded() {
        let retentionDays = min(90, max(1, settings?.maxLogAge ?? 30))
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? .distantPast

        allCrashLogs.removeAll { $0.timestamp < cutoff }
        indexedCrashLogs = allCrashLogs.sorted { $0.timestamp > $1.timestamp }
    }

    private func applyVisibilityFilters() {
        let showSystemProcesses = settings?.showSystemProcesses ?? true
        let showJBCrashesOnly = settings?.showJBCrashesOnly ?? false
        let hideNoiseLogs = settings?.hideNoiseLogs ?? true

        let sorted = allCrashLogs.sorted { $0.timestamp > $1.timestamp }
        indexedCrashLogs = sorted
        crashLogs = sorted.filter { log in
            if hiddenFilePaths.contains(log.filePath) { return false }
            if hideNoiseLogs && log.severityGroup == .noise { return false }
            let systemPass = showSystemProcesses || log.severityGroup != .system
            let jailbreakPass = !showJBCrashesOnly || log.isJailbreakRelevant
            return systemPass && jailbreakPass
        }

        updateStatistics(using: crashLogs)
    }

    private func updateStatistics(using logs: [CrashLog]) {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        let preferredLogs: [CrashLog]
        if settings?.preferRelevantDashboardStats ?? true, !relevantCrashLogs.isEmpty {
            preferredLogs = relevantCrashLogs
        } else {
            preferredLogs = logs
        }

        let todayCrashes = preferredLogs.filter { $0.timestamp >= todayStart }.count
        let processCounts = Dictionary(grouping: preferredLogs, by: { $0.processName })
        let mostCrashed = processCounts.max(by: { $0.value.count < $1.value.count })?.key
        let crashesByType = Dictionary(grouping: preferredLogs, by: { $0.crashType }).mapValues { $0.count }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let thisWeek = preferredLogs.filter { $0.timestamp >= weekAgo }.count
        let lastWeek = preferredLogs.filter { $0.timestamp >= twoWeeksAgo && $0.timestamp < weekAgo }.count

        let trend: CrashStatistics.TrendDirection
        if thisWeek > lastWeek + 2 { trend = .up }
        else if thisWeek < lastWeek - 2 { trend = .down }
        else { trend = .stable }

        let avgPerDay: Double
        if preferredLogs.isEmpty {
            avgPerDay = 0
        } else if let oldest = preferredLogs.map({ $0.timestamp }).min() {
            let daySpan = max(1.0, now.timeIntervalSince(oldest) / 86400.0)
            avgPerDay = Double(preferredLogs.count) / daySpan
        } else {
            avgPerDay = Double(preferredLogs.count)
        }

        statistics = CrashStatistics(
            totalCrashes: preferredLogs.count,
            todayCrashes: todayCrashes,
            mostCrashedProcess: mostCrashed,
            averageCrashesPerDay: avgPerDay,
            crashesByType: crashesByType,
            recentTrend: trend
        )
    }

    private func shouldIndexLog(_ log: CrashLog) -> Bool {
        let path = log.filePath.lowercased()
        // Skip assistant/siri diagnostic noise
        if path.contains("/assistant/") { return false }
        // Skip empty/tiny files that couldn't be real crash logs
        if log.rawContent.count < 50 { return false }
        // Skip oversized files that slipped through (safety net)
        if log.fileSize > 5_000_000 { return false }
        return true
    }

    private func isNoiseLog(_ log: CrashLog) -> Bool {
        log.severityGroup == .noise
    }

    private func isSystemProcess(_ log: CrashLog) -> Bool {
        log.isSystemProcess
    }

    private func isJailbreakRelated(_ log: CrashLog) -> Bool {
        log.isJailbreakRelevant
    }

    private func loadHiddenPaths() {
        hiddenFilePaths = Set(UserDefaults.standard.stringArray(forKey: hiddenPathsKey) ?? [])
    }

    private func saveHiddenPaths() {
        // Prune stale paths that no longer exist on disk to prevent unbounded growth
        if hiddenFilePaths.count > 1000 {
            let fm = FileManager.default
            hiddenFilePaths = hiddenFilePaths.filter { fm.fileExists(atPath: $0) }
        }
        UserDefaults.standard.set(Array(hiddenFilePaths).sorted(), forKey: hiddenPathsKey)
    }

    private func loadReadPaths() {
        readFilePaths = Set(UserDefaults.standard.stringArray(forKey: readPathsKey) ?? [])
    }

    private func saveReadPaths() {
        // Keep only paths that still exist in indexed logs to prevent unbounded growth
        let currentPaths = Set(allCrashLogs.map { $0.filePath })
        if readFilePaths.count > 500 {
            readFilePaths = readFilePaths.intersection(currentPaths)
        }
        UserDefaults.standard.set(Array(readFilePaths).sorted(), forKey: readPathsKey)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard settings?.notificationsEnabled == true else { return }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    private func notifyAboutNewCrashes(_ logs: [CrashLog]) {
        guard settings?.notificationsEnabled == true else { return }

        let visibleNewLogs = logs.filter { log in
            guard !notifiedFilePaths.contains(log.filePath) else { return false }
            let noisePass = !(settings?.hideNoiseLogs ?? true) || log.severityGroup != .noise
            let systemPass = (settings?.showSystemProcesses ?? true) || log.severityGroup != .system
            let jailbreakPass = !(settings?.showJBCrashesOnly ?? false) || log.isJailbreakRelevant
            return noisePass && systemPass && jailbreakPass
        }
        guard !visibleNewLogs.isEmpty else { return }

        visibleNewLogs.forEach { notifiedFilePaths.insert($0.filePath) }

        // Prune notification tracking set to prevent unbounded memory growth
        if notifiedFilePaths.count > 500 {
            let currentPaths = Set(allCrashLogs.map { $0.filePath })
            notifiedFilePaths = notifiedFilePaths.intersection(currentPaths)
        }

        let relevant = visibleNewLogs.filter { $0.severityGroup == .relevant }
        let system = visibleNewLogs.filter { $0.severityGroup == .system }

        // Individual notifications for relevant crashes (user cares about these)
        for crash in relevant.prefix(3) {
            let content = UNMutableNotificationContent()
            let severity = crash.crashType.severity >= 3 ? "🔴 " + "notify.critical".localized : crash.crashType.severity >= 2 ? "🟠 " + "notify.high".localized : "🟡 " + "notify.medium".localized
            content.title = "\(severity) — \(crash.processName)"
            var body = "\(crash.crashType.rawValue)"
            if !crash.signal.isEmpty { body += " (\(crash.signal))" }
            if !crash.exception.isEmpty { body += "\n\(crash.exception)" }
            if crash.isJailbreakRelevant { body += "\n⚠ " + "notify.jbRelevant".localized }
            body += "\n\(crash.timestamp.formatted(date: .abbreviated, time: .shortened))"
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "CRASH_DETAIL"

            let request = UNNotificationRequest(
                identifier: "sentinelcrash.crash.\(crash.id.uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        // Summary notification for system/bulk crashes
        let summaryCount = (relevant.count > 3 ? relevant.count - 3 : 0) + system.count
        if summaryCount > 0 {
            let content = UNMutableNotificationContent()
            content.title = "notify.moreCrashes".localized(summaryCount)
            var parts: [String] = []
            if relevant.count > 3 { parts.append("\(relevant.count - 3) " + "dashboard.relevantShort".localized) }
            if !system.isEmpty { parts.append("\(system.count) " + "dashboard.systemShort".localized) }
            content.body = parts.joined(separator: ", ")
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "sentinelcrash.summary.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - Jailbreak Environment
struct JailbreakEnvironment: Sendable {
    let isRootless: Bool
    let jbRoot: String
    let jailbreakName: String
    let hasBootstrap: Bool
    let bootstrapPath: String
    let procursusStrapped: Bool
    let installedJBTools: [String]
    let supportedIOSMin: String      // e.g. "15.0"
    let supportedIOSMax: String      // e.g. "16.6.1"
    let deviceIOSVersion: String     // actual iOS version running
    let isIOSInRange: Bool           // whether device iOS falls within supported range
}

// MARK: - Jailbreak Detector
final class JailbreakDetector {

    // Known rootless jailbreaks with exact supported iOS ranges
    private struct JBProfile {
        let name: String
        let markerFile: String       // relative to /var/jb
        let minIOS: String
        let maxIOS: String
    }

    private let knownJailbreaks: [JBProfile] = [
        JBProfile(name: "Dopamine",  markerFile: ".installed_dopamine",  minIOS: "15.0",  maxIOS: "16.6.1"),
        JBProfile(name: "palera1n",  markerFile: ".installed_palera1n",  minIOS: "15.0",  maxIOS: "18.7"),
        JBProfile(name: "NathanLR",  markerFile: ".installed_nathanlr",  minIOS: "16.5.1",  maxIOS: "17.0"),
    ]

    func detect() -> JailbreakEnvironment? {
        let fm = FileManager.default
        let jbRoot = "/var/jb"

        guard fm.fileExists(atPath: jbRoot) else { return nil }

        // Detect actual iOS version
        let systemVersion = UIDevice.current.systemVersion  // e.g. "17.0"

        // Find ALL matching markers on disk
        var foundProfiles: [JBProfile] = []
        for profile in knownJailbreaks {
            if fm.fileExists(atPath: "\(jbRoot)/\(profile.markerFile)") {
                foundProfiles.append(profile)
            }
        }

        // Pick the best match:
        // 1. Prefer the profile whose iOS range includes the device version
        // 2. If none match range, use the first found marker
        var jbName = "Unknown Rootless"
        var minIOS = "15.0"
        var maxIOS = "?"
        var matched = false

        // First pass: find one that matches device iOS
        for profile in foundProfiles {
            if isVersion(systemVersion, inRangeMin: profile.minIOS, max: profile.maxIOS) {
                jbName = profile.name
                minIOS = profile.minIOS
                maxIOS = profile.maxIOS
                matched = true
                break
            }
        }

        // Second pass: if no range match, use first found marker (will show warning)
        if !matched, let first = foundProfiles.first {
            jbName = first.name
            minIOS = first.minIOS
            maxIOS = first.maxIOS
            matched = true
        }

        // Fallback: Procursus bootstrap without specific JB marker
        if !matched && fm.fileExists(atPath: "\(jbRoot)/.procursus_strapped") {
            jbName = "Procursus Rootless"
            minIOS = "15.0"
            maxIOS = "?"
        }

        let procursusStrapped = fm.fileExists(atPath: "\(jbRoot)/.procursus_strapped")
        let bootstrapPath = "\(jbRoot)/usr"
        let hasBootstrap = fm.fileExists(atPath: bootstrapPath)

        var tools: [String] = []
        let toolPaths: [(String, String)] = [
            ("\(jbRoot)/usr/bin/dpkg", "dpkg"),
            ("\(jbRoot)/usr/bin/apt", "apt"),
            ("\(jbRoot)/Applications/Sileo.app", "Sileo"),
            ("\(jbRoot)/Applications/Zebra.app", "Zebra"),
            ("\(jbRoot)/usr/bin/bash", "bash"),
            ("\(jbRoot)/usr/bin/ssh", "ssh"),
            ("\(jbRoot)/usr/lib/ellekit.dylib", "ElleKit"),
            ("\(jbRoot)/usr/lib/libsubstitute.dylib", "Substitute"),
        ]
        for (path, name) in toolPaths where fm.fileExists(atPath: path) {
            tools.append(name)
        }

        let inRange = isVersion(systemVersion, inRangeMin: minIOS, max: maxIOS)

        return JailbreakEnvironment(
            isRootless: true,
            jbRoot: jbRoot,
            jailbreakName: jbName,
            hasBootstrap: hasBootstrap,
            bootstrapPath: bootstrapPath,
            procursusStrapped: procursusStrapped,
            installedJBTools: tools,
            supportedIOSMin: minIOS,
            supportedIOSMax: maxIOS,
            deviceIOSVersion: systemVersion,
            isIOSInRange: inRange
        )
    }

    /// Compare semantic version strings: returns true if `version` is between `min` and `max`.
    private func isVersion(_ version: String, inRangeMin min: String, max: String) -> Bool {
        guard max != "?" else { return true }  // unknown max = assume compatible
        let v = versionTuple(version)
        let lo = versionTuple(min)
        let hi = versionTuple(max)
        return v >= lo && v <= hi
    }

    private func versionTuple(_ str: String) -> (Int, Int, Int) {
        let parts = str.split(separator: ".").compactMap { Int($0) }
        return (
            parts.count > 0 ? parts[0] : 0,
            parts.count > 1 ? parts[1] : 0,
            parts.count > 2 ? parts[2] : 0
        )
    }
}

// MARK: - File System Watcher
final class FileSystemWatcher {
    private let paths: [String]
    private let callback: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var fds: [Int32] = []
    private var pendingWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 1.0

    init(paths: [String], callback: @escaping () -> Void) {
        self.paths = paths
        self.callback = callback
    }

    func start() {
        stop()

        for path in paths {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            fds.append(fd)

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                self?.scheduleCallback()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            sources.append(source)
        }
    }

    private func scheduleCallback() {
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.callback()
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
        fds.removeAll()
    }

    deinit {
        stop()
    }
}
