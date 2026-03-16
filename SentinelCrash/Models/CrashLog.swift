import Foundation

// MARK: - Classification
enum CrashSeverityGroup: String, Codable, CaseIterable {
    case relevant = "Relevant"
    case system = "System"
    case noise = "Noise"

    var displayName: String {
        switch self {
        case .relevant: return "dashboard.relevant".localized
        case .system: return "dashboard.system".localized
        case .noise: return "dashboard.noise".localized
        }
    }
}

enum CrashCategory: String, Codable, CaseIterable {
    case appCrash = "App Crash"
    case jailbreak = "Jailbreak"
    case springboard = "SpringBoard"
    case jetsam = "Jetsam"
    case resource = "Resource"
    case dylib = "DYLIB"
    case watchdog = "Watchdog"
    case panic = "Panic"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .appCrash: return "category.appCrash".localized
        case .jailbreak: return "Jailbreak"
        case .springboard: return "SpringBoard"
        case .jetsam: return "Jetsam"
        case .resource: return "category.resource".localized
        case .dylib: return "DYLIB"
        case .watchdog: return "Watchdog"
        case .panic: return "Panic"
        case .unknown: return "common.unknown".localized
        }
    }
}

// MARK: - Crash Log Model
struct CrashLog: Identifiable, Codable, Hashable {
    let id: UUID
    let processName: String
    let bundleID: String
    let timestamp: Date
    let crashType: CrashType
    let signal: String
    let exception: String
    let osVersion: String
    let deviceModel: String
    let rawContent: String
    let filePath: String
    let fileSize: Int64
    let category: CrashCategory
    let severityGroup: CrashSeverityGroup
    let isSystemProcess: Bool
    let isJailbreakRelevant: Bool
    var isRead: Bool
    var isFavorited: Bool
    var tags: [String]
    var jailbreakInfo: JailbreakInfo?
    
    init(
        id: UUID = UUID(),
        processName: String,
        bundleID: String = "",
        timestamp: Date,
        crashType: CrashType,
        signal: String = "",
        exception: String = "",
        osVersion: String = "",
        deviceModel: String = "",
        rawContent: String,
        filePath: String,
        fileSize: Int64 = 0,
        category: CrashCategory = .unknown,
        severityGroup: CrashSeverityGroup = .relevant,
        isSystemProcess: Bool = false,
        isJailbreakRelevant: Bool = false,
        isRead: Bool = false,
        isFavorited: Bool = false,
        tags: [String] = [],
        jailbreakInfo: JailbreakInfo? = nil
    ) {
        self.id = id
        self.processName = processName
        self.bundleID = bundleID
        self.timestamp = timestamp
        self.crashType = crashType
        self.signal = signal
        self.exception = exception
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.rawContent = rawContent
        self.filePath = filePath
        self.fileSize = fileSize
        self.category = category
        self.severityGroup = severityGroup
        self.isSystemProcess = isSystemProcess
        self.isJailbreakRelevant = isJailbreakRelevant
        self.isRead = isRead
        self.isFavorited = isFavorited
        self.tags = tags
        self.jailbreakInfo = jailbreakInfo
    }

    // MARK: - Crash Location (extracted from raw content)

    /// Extracts the crashing function/library from the crash log for quick display.
    var crashLocation: String? {
        let content = rawContent
        guard !content.isEmpty else { return nil }

        // 1. Classic crash: find "Thread X Crashed" → frame 0
        let lines = content.components(separatedBy: "\n")
        var inCrashedThread = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Thread") && t.contains("Crashed") {
                inCrashedThread = true
                continue
            }
            if inCrashedThread {
                // First frame line: "0   libsystem_kernel.dylib   0x1234   func + 8"
                if t.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                    // Extract: library + symbol
                    let parts = t.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                    if parts.count >= 4 {
                        let library = String(parts[1])
                        let symbolPart = String(parts[3...].joined(separator: " "))
                        let shortLib = (library as NSString).lastPathComponent
                        return "\(shortLib) → \(symbolPart)"
                    } else if parts.count >= 2 {
                        return String(parts[1])
                    }
                    return nil
                }
            }
        }

        // 2. IPS JSON: extract termination indicator
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            if let range = content.range(of: #""indicator"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                let match = String(content[range])
                if let valStart = match.range(of: ":") {
                    let val = match[valStart.upperBound...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !val.isEmpty { return val }
                }
            }
            // Fallback: procPath
            if let range = content.range(of: #""procPath"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                let match = String(content[range])
                if let val = match.split(separator: ":").last {
                    let path = val.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"\\"))
                    return (path as NSString).lastPathComponent
                }
            }
            // JetsamEvent: largestProcess
            if let range = content.range(of: #""largestProcess"\s*:\s*"([^"]+)""#, options: .regularExpression) {
                let match = String(content[range])
                if let val = match.split(separator: ":").last {
                    let proc = val.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if !proc.isEmpty { return "Memory killer → \(proc)" }
                }
            }
        }

        // 3. Microstackshot: "Event: cpu usage" + first frame
        var eventType: String?
        var inHeaviest = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Event:") {
                eventType = String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
            if t.hasPrefix("Heaviest stack") { inHeaviest = true; continue }
            if inHeaviest && t.contains("(") && t.contains(")") {
                if let libStart = t.range(of: "("), let libEnd = t.range(of: ")") {
                    let inside = String(t[libStart.upperBound..<libEnd.lowerBound])
                    let lib = inside.trimmingCharacters(in: .whitespaces)
                    if let event = eventType {
                        return "\(event) → \(lib)"
                    }
                    return lib
                }
            }
        }

        return nil
    }

    /// Short version for list row display (max ~40 chars)
    var crashLocationShort: String? {
        guard let loc = crashLocation else { return nil }
        if loc.count > 45 {
            return String(loc.prefix(42)) + "…"
        }
        return loc
    }
}

// MARK: - Crash Type
enum CrashType: String, Codable, CaseIterable {
    case sigsegv = "SIGSEGV"
    case sigabrt = "SIGABRT"
    case sigbus = "SIGBUS"
    case sigfpe = "SIGFPE"
    case sigill = "SIGILL"
    case sigtrap = "SIGTRAP"
    case exc_bad_access = "EXC_BAD_ACCESS"
    case exc_crash = "EXC_CRASH"
    case exc_resource = "EXC_RESOURCE"
    case exc_guard = "EXC_GUARD"
    case exc_bad_instruction = "EXC_BAD_INSTRUCTION"
    case watchdog = "WATCHDOG"
    case jetsam = "JETSAM"
    case panic = "PANIC"
    case jailbreakError = "JB_ERROR"
    case tweak = "TWEAK_CRASH"
    case dylib = "DYLIB_ERROR"
    case unknown = "UNKNOWN"
    
    var displayName: String { rawValue }
    
    var icon: String {
        switch self {
        case .sigsegv, .sigbus: return "memorychip"
        case .sigabrt: return "xmark.octagon.fill"
        case .sigfpe: return "function"
        case .sigill, .exc_bad_instruction: return "cpu"
        case .sigtrap: return "ant.fill"
        case .exc_bad_access: return "lock.slash.fill"
        case .exc_crash: return "bolt.fill"
        case .exc_resource: return "speedometer"
        case .exc_guard: return "shield.slash.fill"
        case .watchdog: return "timer"
        case .jetsam: return "memorychip.fill"
        case .panic: return "flame.fill"
        case .jailbreakError: return "lock.open.fill"
        case .tweak: return "puzzlepiece.fill"
        case .dylib: return "link"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var color: String {
        switch self {
        case .sigsegv, .sigbus, .sigabrt, .exc_crash: return "red"
        case .sigfpe, .sigill, .exc_bad_instruction: return "orange"
        case .exc_bad_access, .exc_guard: return "yellow"
        case .exc_resource, .watchdog, .jetsam: return "purple"
        case .panic: return "red"
        case .jailbreakError, .tweak, .dylib: return "cyan"
        default: return "gray"
        }
    }
    
    var severity: Int {
        switch self {
        case .sigabrt, .exc_crash, .sigsegv: return 3
        case .sigbus, .exc_bad_access, .exc_guard: return 2
        case .watchdog, .exc_resource, .jetsam: return 2
        case .panic: return 3
        case .jailbreakError, .tweak, .dylib: return 2
        default: return 1
        }
    }
}

// MARK: - Jailbreak Info
struct JailbreakInfo: Codable, Hashable {
    let jailbreakType: String       // dopamine, nathanlr, etc.
    let isRootless: Bool
    let jbRoot: String              // /var/jb
    let installedTweaks: [String]
    let dylibs: [String]
    let bootstrapVersion: String
}

// MARK: - Crash Statistics
struct CrashStatistics {
    let totalCrashes: Int
    let todayCrashes: Int
    let mostCrashedProcess: String?
    let averageCrashesPerDay: Double
    let crashesByType: [CrashType: Int]
    let recentTrend: TrendDirection
    
    enum TrendDirection {
        case up, down, stable
    }
}

// MARK: - Filter Options
struct CrashFilter {
    var searchText: String = ""
    var selectedTypes: Set<CrashType> = []
    var showOnlyUnread: Bool = false
    var showOnlyFavorited: Bool = false
    var processName: String = ""
    var sortOrder: SortOrder = .newest
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest First"
        case oldest = "Oldest First"
        case processName = "Process Name"
        case severity = "Severity"

        var displayName: String {
            switch self {
            case .newest: return "filter.newestFirst".localized
            case .oldest: return "filter.oldestFirst".localized
            case .processName: return "filter.processName".localized
            case .severity: return "diff.severity".localized
            }
        }
    }
    
    var isEmpty: Bool {
        searchText.isEmpty &&
        selectedTypes.isEmpty &&
        !showOnlyUnread &&
        !showOnlyFavorited &&
        processName.isEmpty
    }
}
