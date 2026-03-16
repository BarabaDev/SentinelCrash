import Foundation
import Combine

@MainActor
final class SettingsManager: ObservableObject {
    @Published var autoScanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoScanEnabled, forKey: Keys.autoScan) }
    }
    @Published var scanInterval: Double {
        didSet { UserDefaults.standard.set(scanInterval, forKey: Keys.scanInterval) }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    @Published var showJBCrashesOnly: Bool {
        didSet { UserDefaults.standard.set(showJBCrashesOnly, forKey: Keys.jbOnly) }
    }
    @Published var maxLogAge: Int {
        didSet { UserDefaults.standard.set(maxLogAge, forKey: Keys.maxLogAge) }
    }
    @Published var showSystemProcesses: Bool {
        didSet { UserDefaults.standard.set(showSystemProcesses, forKey: Keys.showSystem) }
    }
    @Published var hideNoiseLogs: Bool {
        didSet { UserDefaults.standard.set(hideNoiseLogs, forKey: Keys.hideNoise) }
    }
    @Published var preferRelevantDashboardStats: Bool {
        didSet { UserDefaults.standard.set(preferRelevantDashboardStats, forKey: Keys.preferRelevantDashboardStats) }
    }

    private enum Keys {
        static let autoScan = "autoScan"
        static let scanInterval = "scanInterval"
        static let notifications = "notifications"
        static let jbOnly = "jbOnly"
        static let maxLogAge = "maxLogAge"
        static let showSystem = "showSystem"
        static let hideNoise = "hideNoise"
        static let preferRelevantDashboardStats = "preferRelevantDashboardStats"
    }

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.autoScan) == nil {
            defaults.set(true, forKey: Keys.autoScan)
        }
        if defaults.object(forKey: Keys.scanInterval) == nil {
            defaults.set(30.0, forKey: Keys.scanInterval)
        }
        if defaults.object(forKey: Keys.notifications) == nil {
            defaults.set(false, forKey: Keys.notifications)
        }
        if defaults.object(forKey: Keys.jbOnly) == nil {
            defaults.set(false, forKey: Keys.jbOnly)
        }
        if defaults.object(forKey: Keys.maxLogAge) == nil {
            defaults.set(30, forKey: Keys.maxLogAge)
        }
        if defaults.object(forKey: Keys.showSystem) == nil {
            defaults.set(true, forKey: Keys.showSystem)
        }
        if defaults.object(forKey: Keys.hideNoise) == nil {
            defaults.set(true, forKey: Keys.hideNoise)
        }
        if defaults.object(forKey: Keys.preferRelevantDashboardStats) == nil {
            defaults.set(true, forKey: Keys.preferRelevantDashboardStats)
        }

        self.autoScanEnabled = defaults.bool(forKey: Keys.autoScan)
        self.scanInterval = max(10.0, defaults.double(forKey: Keys.scanInterval).nonZero ?? 30.0)
        self.notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        self.showJBCrashesOnly = defaults.bool(forKey: Keys.jbOnly)
        self.maxLogAge = min(90, max(1, defaults.integer(forKey: Keys.maxLogAge).nonZero ?? 30))
        self.showSystemProcesses = defaults.bool(forKey: Keys.showSystem)
        self.hideNoiseLogs = defaults.bool(forKey: Keys.hideNoise)
        self.preferRelevantDashboardStats = defaults.bool(forKey: Keys.preferRelevantDashboardStats)
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
