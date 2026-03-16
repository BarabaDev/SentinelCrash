import Foundation

// MARK: - TweakConflictDetector
final class TweakConflictDetector {

    private let dpkgManager = DpkgPackageManager()

    struct AnalysisResult {
        let conflicts: [TweakConflictReport]
        let dylibToPackage: [String: DpkgPackage]
        let packages: [DpkgPackage]
        let analysisDate: Date
        let totalCrashesAnalyzed: Int
    }

    // MARK: - Public

    /// Full conflict analysis across all crash logs.
    func analyze(crashes: [CrashLog]) -> AnalysisResult {
        let packages = dpkgManager.loadInstalledPackages()
        let dylibMap = dpkgManager.buildDylibToPackageMap(packages: packages)

        // For each crash, extract dylibs and map to packages
        var packageCrashMap: [String: (package: DpkgPackage, crashes: [CrashLog], dylibs: Set<String>)] = [:]

        for crash in crashes {
            let dylibs = extractLoadedDylibs(from: crash)

            for dylib in dylibs {
                let key = (dylib as NSString).lastPathComponent.lowercased()
                guard let pkg = dylibMap[key] else { continue }

                if packageCrashMap[pkg.identifier] == nil {
                    packageCrashMap[pkg.identifier] = (package: pkg, crashes: [], dylibs: Set())
                }
                packageCrashMap[pkg.identifier]?.crashes.append(crash)
                packageCrashMap[pkg.identifier]?.dylibs.insert(dylib)
            }
        }

        // Build conflict reports
        var conflicts: [TweakConflictReport] = []

        for (_, entry) in packageCrashMap {
            let pkg = entry.package
            let crashList = entry.crashes
            let dylibs = Array(entry.dylibs)

            // Skip system/bootstrap packages
            guard !pkg.isSystemPackage else { continue }

            let affectedProcesses = Array(Set(crashList.map { $0.processName })).sorted()
            let dangerScore = computeDangerScore(
                crashCount: crashList.count,
                totalCrashes: crashes.count,
                affectedProcessCount: affectedProcesses.count,
                hasCriticalCrashes: crashList.contains { $0.crashType.severity >= 3 },
                crashesSpringBoard: affectedProcesses.contains("SpringBoard")
            )

            let report = TweakConflictReport(
                tweakName: pkg.name,
                packageID: pkg.identifier,
                crashCount: crashList.count,
                affectedProcesses: affectedProcesses,
                dylibsLoaded: dylibs.sorted(),
                dangerScore: dangerScore,
                firstCrash: crashList.map { $0.timestamp }.min(),
                lastCrash: crashList.map { $0.timestamp }.max()
            )
            conflicts.append(report)
        }

        conflicts.sort { $0.dangerScore > $1.dangerScore }

        return AnalysisResult(
            conflicts: conflicts,
            dylibToPackage: dylibMap,
            packages: packages,
            analysisDate: Date(),
            totalCrashesAnalyzed: crashes.count
        )
    }

    /// Quick check: which tweaks appear in a single crash.
    func tweaksInCrash(_ crash: CrashLog, dylibMap: [String: DpkgPackage]) -> [DpkgPackage] {
        let dylibs = extractLoadedDylibs(from: crash)
        var seen = Set<String>()
        var result: [DpkgPackage] = []

        for dylib in dylibs {
            let key = (dylib as NSString).lastPathComponent.lowercased()
            if let pkg = dylibMap[key], !seen.contains(pkg.identifier) {
                seen.insert(pkg.identifier)
                result.append(pkg)
            }
        }
        return result
    }

    // MARK: - Private

    private func extractLoadedDylibs(from crash: CrashLog) -> [String] {
        var dylibs: [String] = []
        let content = crash.rawContent
        let lines = content.components(separatedBy: .newlines)
        var inBinaryImages = false

        for line in lines {
            if line.contains("Binary Images:") {
                inBinaryImages = true
                continue
            }
            if inBinaryImages {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty && !dylibs.isEmpty { break }
                if !trimmed.hasPrefix("0x") && !trimmed.hasPrefix("0X") && !dylibs.isEmpty { break }

                // Extract full path from binary image line
                if let pathStart = line.range(of: "/") {
                    let path = String(line[pathStart.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    // Filter for non-system dylibs
                    if isThirdPartyDylib(path) {
                        dylibs.append(path)
                    }
                }
            }
        }

        // Also check crashed thread frames for dylib references
        let framePattern = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil
        }
        for frame in framePattern {
            let lower = frame.lowercased()
            if lower.contains("/var/jb") || lower.contains("substrate") || lower.contains("ellekit")
                || lower.contains("substitute") || lower.contains(".dylib") {
                // Extract the library name from the frame
                let components = frame.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 2 {
                    let libName = components[1]
                    if !dylibs.contains(where: { $0.contains(libName) }) {
                        dylibs.append(libName)
                    }
                }
            }
        }

        return dylibs
    }

    private func isThirdPartyDylib(_ path: String) -> Bool {
        let lower = path.lowercased()
        // Skip Apple system frameworks
        if lower.hasPrefix("/system/") || lower.hasPrefix("/usr/lib/system/") { return false }
        if lower.contains("/privatefram") { return false }
        // Include jailbreak paths
        if lower.contains("/var/jb") || lower.contains("substrate") || lower.contains("ellekit")
            || lower.contains("substitute") || lower.contains("mobilesubstrate")
            || lower.contains("dynamiclibraries") {
            return true
        }
        // Include any non-system dylib
        if lower.hasSuffix(".dylib") && !lower.hasPrefix("/usr/lib/") && !lower.hasPrefix("/system/") {
            return true
        }
        return false
    }

    private func computeDangerScore(
        crashCount: Int,
        totalCrashes: Int,
        affectedProcessCount: Int,
        hasCriticalCrashes: Bool,
        crashesSpringBoard: Bool
    ) -> Double {
        var score = 0.0

        // Frequency component (0.0 - 0.4)
        let frequency = totalCrashes > 0 ? Double(crashCount) / Double(totalCrashes) : 0
        score += min(0.4, frequency * 2.0)

        // Breadth component (0.0 - 0.2)
        score += min(0.2, Double(affectedProcessCount) * 0.04)

        // Severity component (0.0 - 0.25)
        if hasCriticalCrashes { score += 0.15 }
        if crashesSpringBoard { score += 0.10 }

        // Volume component (0.0 - 0.15)
        score += min(0.15, Double(crashCount) * 0.01)

        return min(1.0, score)
    }
}
