import Foundation

// MARK: - AutoBlameEngine
final class AutoBlameEngine {

    private let conflictDetector = TweakConflictDetector()
    private let dpkgManager = DpkgPackageManager()

    /// Analyze a single crash and produce blame results.
    func blame(crash: CrashLog, allCrashes: [CrashLog]) -> [TweakBlameResult] {
        let packages = dpkgManager.loadInstalledPackages()
        let dylibMap = dpkgManager.buildDylibToPackageMap(packages: packages)

        var results: [TweakBlameResult] = []

        // 1. Check crashed thread frames for tweak dylibs
        let crashedThreadDylibs = extractCrashedThreadDylibs(from: crash)
        // Pre-compute search-friendly prefixes for O(n) instead of O(n*m) full-text search
        let searchPrefixes = allCrashes.map { (id: $0.id, prefix: String($0.rawContent.prefix(10_000)).lowercased()) }
        for dylib in crashedThreadDylibs {
            let key = (dylib as NSString).lastPathComponent.lowercased()
            if let pkg = dylibMap[key], !pkg.isSystemPackage {
                let dylibLower = dylib.lowercased()
                let otherCrashes = allCrashes.enumerated().filter { idx, other in
                    other.id != crash.id && searchPrefixes[idx].prefix.contains(dylibLower)
                }.map { $0.element }
                let score = computeBlameScore(
                    inCrashedThread: true,
                    framePosition: framePosition(of: dylib, in: crash),
                    recurrenceCount: otherCrashes.count,
                    installProximity: installProximityScore(pkg: pkg, crashDate: crash.timestamp),
                    isCritical: crash.crashType.severity >= 3
                )
                results.append(TweakBlameResult(
                    tweakName: pkg.name,
                    packageID: pkg.identifier,
                    confidence: confidenceFromScore(score),
                    score: score,
                    reason: buildReason(inCrashedThread: true, framePos: framePosition(of: dylib, in: crash), recurrence: otherCrashes.count, pkg: pkg, crash: crash),
                    involvedCrashes: [crash] + otherCrashes.prefix(5),
                    dylibPaths: [dylib]
                ))
            }
        }

        // 2. Check all loaded dylibs (binary images) for suspicious tweaks
        let allLoadedDylibs = extractAllThirdPartyDylibs(from: crash)
        for dylib in allLoadedDylibs {
            let key = (dylib as NSString).lastPathComponent.lowercased()
            guard let pkg = dylibMap[key], !pkg.isSystemPackage else { continue }
            // Skip if already blamed from crashed thread
            guard !results.contains(where: { $0.packageID == pkg.identifier }) else { continue }

            let otherCrashes = allCrashes.enumerated().filter { idx, other in
                other.id != crash.id && searchPrefixes[idx].prefix.contains(key)
            }.map { $0.element }

            // Only blame loaded (not in crashed thread) if there's a pattern
            let recurrence = otherCrashes.count
            guard recurrence >= 2 || installProximityScore(pkg: pkg, crashDate: crash.timestamp) > 0.5 else { continue }

            let score = computeBlameScore(
                inCrashedThread: false,
                framePosition: -1,
                recurrenceCount: recurrence,
                installProximity: installProximityScore(pkg: pkg, crashDate: crash.timestamp),
                isCritical: crash.crashType.severity >= 3
            )

            if score >= 0.15 {
                results.append(TweakBlameResult(
                    tweakName: pkg.name,
                    packageID: pkg.identifier,
                    confidence: confidenceFromScore(score),
                    score: score,
                    reason: buildReason(inCrashedThread: false, framePos: -1, recurrence: recurrence, pkg: pkg, crash: crash),
                    involvedCrashes: [crash] + otherCrashes.prefix(3),
                    dylibPaths: [dylib]
                ))
            }
        }

        // 3. Check for recently installed tweaks (temporal correlation)
        let recentTweaks = packages.filter { pkg in
            guard let installDate = pkg.installedDate, pkg.isTweak else { return false }
            let daysBefore = crash.timestamp.timeIntervalSince(installDate) / 86400
            return daysBefore >= 0 && daysBefore <= 3
        }

        for pkg in recentTweaks {
            guard !results.contains(where: { $0.packageID == pkg.identifier }) else { continue }
            let score = 0.2 + installProximityScore(pkg: pkg, crashDate: crash.timestamp) * 0.3
            if score >= 0.2 {
                results.append(TweakBlameResult(
                    tweakName: pkg.name,
                    packageID: pkg.identifier,
                    confidence: .low,
                    score: score,
                    reason: "blame.temporal".localized(pkg.name, formatDateDiff(pkg.installedDate, crash.timestamp)),
                    involvedCrashes: [crash],
                    dylibPaths: pkg.providedDylibs
                ))
            }
        }

        results.sort { $0.score > $1.score }
        return results
    }

    /// Quick blame for a single crash (lighter weight).
    func quickBlame(crash: CrashLog, dylibMap: [String: DpkgPackage]) -> [TweakBlameResult] {
        let crashedThreadDylibs = extractCrashedThreadDylibs(from: crash)
        var results: [TweakBlameResult] = []

        for dylib in crashedThreadDylibs {
            let key = (dylib as NSString).lastPathComponent.lowercased()
            if let pkg = dylibMap[key], !pkg.isSystemPackage {
                results.append(TweakBlameResult(
                    tweakName: pkg.name,
                    packageID: pkg.identifier,
                    confidence: .high,
                    score: 0.8,
                    reason: "blame.dylibInStack".localized(pkg.name),
                    involvedCrashes: [crash],
                    dylibPaths: [dylib]
                ))
            }
        }

        return results
    }

    // MARK: - Private Helpers

    private func extractCrashedThreadDylibs(from crash: CrashLog) -> [String] {
        let lines = crash.rawContent.components(separatedBy: .newlines)
        var inCrashedThread = false
        var dylibs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Thread") && trimmed.contains("Crashed") {
                inCrashedThread = true
                continue
            }
            if inCrashedThread && trimmed.hasPrefix("Thread ") && !trimmed.contains("Crashed") {
                break
            }
            if trimmed.hasPrefix("Binary Images:") { break }

            if inCrashedThread, trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 2 {
                    let lib = components[1]
                    if isThirdParty(lib) {
                        dylibs.append(lib)
                    }
                }
            }
        }
        return Array(Set(dylibs))
    }

    private func extractAllThirdPartyDylibs(from crash: CrashLog) -> [String] {
        let lines = crash.rawContent.components(separatedBy: .newlines)
        var dylibs: [String] = []
        var inBinaryImages = false

        for line in lines {
            if line.contains("Binary Images:") { inBinaryImages = true; continue }
            if inBinaryImages {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty && !dylibs.isEmpty { break }
                if !trimmed.hasPrefix("0x") && !trimmed.hasPrefix("0X") && !dylibs.isEmpty { break }

                if let pathStart = line.range(of: "/") {
                    let path = String(line[pathStart.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    let filename = (path as NSString).lastPathComponent
                    if isThirdParty(filename) || isThirdParty(path) {
                        dylibs.append(filename)
                    }
                }
            }
        }
        return Array(Set(dylibs))
    }

    private func isThirdParty(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("substrate") || lower.contains("ellekit") || lower.contains("substitute")
            || lower.contains("mobilesubstrate") || lower.contains("/var/jb")
            || lower.contains("dynamiclibraries") || lower.contains("tweak") {
            return true
        }
        // Non-Apple dylib
        if lower.hasSuffix(".dylib") && !lower.hasPrefix("lib") && !lower.contains("system") {
            return true
        }
        return false
    }

    private func framePosition(of dylib: String, in crash: CrashLog) -> Int {
        let lines = crash.rawContent.components(separatedBy: .newlines)
        var inCrashedThread = false
        var frameIdx = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Thread") && trimmed.contains("Crashed") { inCrashedThread = true; continue }
            if inCrashedThread && trimmed.hasPrefix("Thread ") && !trimmed.contains("Crashed") { break }
            if inCrashedThread, trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                if trimmed.localizedCaseInsensitiveContains(dylib) {
                    return frameIdx
                }
                frameIdx += 1
            }
        }
        return -1
    }

    private func computeBlameScore(
        inCrashedThread: Bool,
        framePosition: Int,
        recurrenceCount: Int,
        installProximity: Double,
        isCritical: Bool
    ) -> Double {
        var score = 0.0

        // In crashed thread is strong signal (0.0 - 0.45)
        if inCrashedThread {
            score += 0.3
            // Higher frames (closer to crash point) are more suspicious
            if framePosition >= 0 && framePosition <= 2 { score += 0.15 }
            else if framePosition >= 0 && framePosition <= 5 { score += 0.08 }
        }

        // Recurrence (0.0 - 0.25)
        score += min(0.25, Double(recurrenceCount) * 0.05)

        // Install proximity (0.0 - 0.2)
        score += installProximity * 0.2

        // Critical crash bonus (0.0 - 0.1)
        if isCritical { score += 0.1 }

        return min(1.0, score)
    }

    private func installProximityScore(pkg: DpkgPackage, crashDate: Date) -> Double {
        guard let installDate = pkg.installedDate else { return 0 }
        let daysBetween = crashDate.timeIntervalSince(installDate) / 86400.0
        guard daysBetween >= 0 else { return 0 }
        if daysBetween <= 1 { return 1.0 }
        if daysBetween <= 3 { return 0.7 }
        if daysBetween <= 7 { return 0.3 }
        return 0
    }

    private func confidenceFromScore(_ score: Double) -> TweakBlameResult.BlameConfidence {
        if score >= 0.6 { return .high }
        if score >= 0.35 { return .medium }
        return .low
    }

    private func buildReason(inCrashedThread: Bool, framePos: Int, recurrence: Int, pkg: DpkgPackage, crash: CrashLog) -> String {
        var parts: [String] = []

        if inCrashedThread {
            if framePos >= 0 && framePos <= 2 {
                parts.append("blame.topOfStack".localized(pkg.name, framePos))
            } else {
                parts.append("blame.dylibInStack".localized(pkg.name))
            }
        }

        if recurrence > 0 {
            parts.append("blame.seenInOther".localized(recurrence))
        }

        if let installDate = pkg.installedDate {
            let days = crash.timestamp.timeIntervalSince(installDate) / 86400.0
            if days >= 0 && days <= 7 {
                parts.append("blame.installedRecently".localized(formatDateDiff(pkg.installedDate, crash.timestamp)))
            }
        }

        return parts.isEmpty ? "blame.loadedInProcess".localized : parts.joined(separator: ". ") + "."
    }

    private func formatDateDiff(_ from: Date?, _ to: Date) -> String {
        guard let from else { return "common.unknown".localized }
        let hours = Int(to.timeIntervalSince(from) / 3600)
        if hours < 1 { return "blame.lessThan1h".localized }
        if hours < 24 { return "blame.hoursBeforeCrash".localized(hours) }
        let days = hours / 24
        return "blame.daysBeforeCrash".localized(days)
    }
}
