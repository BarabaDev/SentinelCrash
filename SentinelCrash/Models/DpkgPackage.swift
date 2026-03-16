import Foundation

// MARK: - Dpkg Package Model
struct DpkgPackage: Identifiable, Hashable {
    var id: String { identifier }
    let identifier: String       // com.example.tweak
    let name: String             // Display name
    let version: String
    let author: String
    let description: String
    let section: String
    let installedSize: Int64     // in KB
    let status: PackageStatus
    let installedDate: Date?
    let depends: [String]
    let providedDylibs: [String] // dylibs this package installs

    enum PackageStatus: String {
        case installed = "install ok installed"
        case halfInstalled = "install ok half-installed"
        case configFiles = "deinstall ok config-files"
        case removed = "deinstall ok not-installed"
        case unknown = "unknown"

        init(raw: String) {
            switch raw.lowercased() {
            case let s where s.contains("install ok installed"):
                self = .installed
            case let s where s.contains("half-installed"):
                self = .halfInstalled
            case let s where s.contains("config-files"):
                self = .configFiles
            case let s where s.contains("deinstall"):
                self = .removed
            default:
                self = .unknown
            }
        }
    }

    var isTweak: Bool {
        let s = section.lowercased()
        return s.contains("tweak") || s.contains("addon") || s.contains("theme")
    }

    var isSystemPackage: Bool {
        let id = identifier.lowercased()
        return id.hasPrefix("apt") || id.hasPrefix("base-") || id.hasPrefix("dpkg")
            || id.hasPrefix("coreutils") || id.hasPrefix("firmware")
            || id.hasPrefix("org.coolstar") || id.hasPrefix("shshd")
            || section.lowercased() == "packaging" || section.lowercased() == "system"
    }
}

// MARK: - Crash Group Model
struct CrashGroup: Identifiable {
    let id: String              // grouping key
    let processName: String
    let crashType: CrashType
    let primaryException: String
    var crashes: [CrashLog]
    let firstSeen: Date
    let lastSeen: Date

    var count: Int { crashes.count }

    var trend: GroupTrend {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now) else {
            return .stable
        }
        let thisWeek = crashes.filter { $0.timestamp >= weekAgo }.count
        let lastWeek = crashes.filter { $0.timestamp >= twoWeeksAgo && $0.timestamp < weekAgo }.count
        if thisWeek > lastWeek + 1 { return .increasing }
        if thisWeek < lastWeek - 1 { return .decreasing }
        return .stable
    }

    enum GroupTrend: String {
        case increasing = "Increasing"
        case decreasing = "Decreasing"
        case stable = "Stable"

        var displayName: String {
            switch self {
            case .increasing: return "groups.increasing".localized
            case .decreasing: return "groups.decreasing".localized
            case .stable: return "groups.stable".localized
            }
        }

        var icon: String {
            switch self {
            case .increasing: return "arrow.up.right"
            case .decreasing: return "arrow.down.right"
            case .stable: return "arrow.right"
            }
        }

        var color: String {
            switch self {
            case .increasing: return "red"
            case .decreasing: return "green"
            case .stable: return "gray"
            }
        }
    }
}

// MARK: - Tweak Blame Result
struct TweakBlameResult: Identifiable {
    let id = UUID()
    let tweakName: String
    let packageID: String
    let confidence: BlameConfidence
    let score: Double             // 0.0 – 1.0
    let reason: String
    let involvedCrashes: [CrashLog]
    let dylibPaths: [String]

    enum BlameConfidence: String, CaseIterable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"

        var displayName: String {
            switch self {
            case .high: return "confidence.high".localized
            case .medium: return "confidence.medium".localized
            case .low: return "confidence.low".localized
            }
        }

        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "orange"
            case .low: return "yellow"
            }
        }

        var icon: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .low: return "info.circle.fill"
            }
        }
    }
}

// MARK: - Tweak Conflict Report
struct TweakConflictReport {
    let tweakName: String
    let packageID: String
    let crashCount: Int
    let affectedProcesses: [String]
    let dylibsLoaded: [String]
    let dangerScore: Double       // 0.0 – 1.0
    let firstCrash: Date?
    let lastCrash: Date?
}

// MARK: - Export Format
enum ExportFormat: String, CaseIterable, Identifiable {
    case json = "JSON"
    case text = "Plain Text"
    case report = "Formatted Report"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: return "export.json".localized
        case .text: return "export.plainText".localized
        case .report: return "export.formattedReport".localized
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "txt"
        case .report: return "md"
        }
    }

    var mimeType: String {
        switch self {
        case .json: return "application/json"
        case .text: return "text/plain"
        case .report: return "text/markdown"
        }
    }
}

// MARK: - Timeline Event
struct TimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let kind: EventKind
    let title: String
    let subtitle: String
    let color: String

    enum EventKind {
        case crash(CrashLog)
        case tweakInstall(DpkgPackage)
        case tweakUpdate(DpkgPackage)
        case tweakRemove(String)
    }
}
