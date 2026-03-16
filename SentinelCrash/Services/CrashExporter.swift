import Foundation

// MARK: - CrashExporter
final class CrashExporter {

    // MARK: - Single Log Export

    func export(crash: CrashLog, format: ExportFormat) -> String {
        switch format {
        case .json:
            return exportJSON(crashes: [crash])
        case .text:
            return exportText(crash: crash)
        case .report:
            return exportReport(crash: crash)
        }
    }

    // MARK: - Batch Export

    func exportBatch(crashes: [CrashLog], format: ExportFormat) -> String {
        // Limit batch export to 50 crashes to prevent memory issues
        let limited = Array(crashes.prefix(50))
        switch format {
        case .json:
            return exportJSON(crashes: limited)
        case .text:
            return limited.map { exportText(crash: $0) }.joined(separator: "\n\n" + String(repeating: "=", count: 80) + "\n\n")
        case .report:
            return exportBatchReport(crashes: limited)
        }
    }

    /// Write export to a temporary file and return the URL.
    func exportToFile(content: String, filename: String) -> URL? {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent(filename)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("[SentinelCrash] Export write failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - JSON Export

    private func exportJSON(crashes: [CrashLog]) -> String {
        var entries: [[String: Any]] = []

        for crash in crashes {
            var entry: [String: Any] = [
                "processName": crash.processName,
                "bundleID": crash.bundleID,
                "timestamp": ISO8601DateFormatter().string(from: crash.timestamp),
                "crashType": crash.crashType.rawValue,
                "signal": crash.signal,
                "exception": crash.exception,
                "osVersion": crash.osVersion,
                "deviceModel": crash.deviceModel,
                "filePath": crash.filePath,
                "fileSize": crash.fileSize,
                "category": crash.category.rawValue,
                "severityGroup": crash.severityGroup.rawValue,
                "isSystemProcess": crash.isSystemProcess,
                "isJailbreakRelevant": crash.isJailbreakRelevant,
            ]

            if let jbInfo = crash.jailbreakInfo {
                entry["jailbreakInfo"] = [
                    "jailbreakType": jbInfo.jailbreakType,
                    "isRootless": jbInfo.isRootless,
                    "jbRoot": jbInfo.jbRoot,
                    "installedTweaks": jbInfo.installedTweaks,
                    "dylibs": jbInfo.dylibs,
                    "bootstrapVersion": jbInfo.bootstrapVersion,
                ]
            }

            entries.append(entry)
        }

        let wrapper: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "exportVersion": "1.0",
            "generator": "SentinelCrash v1.1.0",
            "crashCount": entries.count,
            "crashes": entries,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to serialize\"}"
        }

        return json
    }

    // MARK: - Plain Text Export

    private func exportText(crash: CrashLog) -> String {
        var text = """
        SentinelCrash Export — \(crash.processName)
        =============================================
        Process:    \(crash.processName)
        Bundle ID:  \(crash.bundleID.isEmpty ? "N/A" : crash.bundleID)
        Timestamp:  \(crash.timestamp.formatted(date: .complete, time: .standard))
        Crash Type: \(crash.crashType.rawValue)
        Signal:     \(crash.signal.isEmpty ? "N/A" : crash.signal)
        Exception:  \(crash.exception.isEmpty ? "N/A" : crash.exception)
        iOS:        \(crash.osVersion.isEmpty ? "N/A" : crash.osVersion)
        Device:     \(crash.deviceModel.isEmpty ? "N/A" : crash.deviceModel)
        Category:   \(crash.category.rawValue)
        Severity:   \(crash.severityGroup.rawValue)
        JB Related: \(crash.isJailbreakRelevant ? "Yes" : "No")
        File:       \(crash.filePath)
        File Size:  \(ByteCountFormatter.string(fromByteCount: crash.fileSize, countStyle: .file))
        """

        if let jbInfo = crash.jailbreakInfo {
            text += """
            
            
            Jailbreak Context:
              Type:      \(jbInfo.jailbreakType)
              Rootless:  \(jbInfo.isRootless ? "Yes" : "No")
              JB Root:   \(jbInfo.jbRoot)
              Bootstrap: \(jbInfo.bootstrapVersion)
              Tweaks:    \(jbInfo.installedTweaks.joined(separator: ", "))
            """
        }

        text += "\n\n--- Raw Log ---\n\n" + crash.rawContent

        return text
    }

    // MARK: - Formatted Report (Markdown)

    private func exportReport(crash: CrashLog) -> String {
        var md = """
        # SentinelCrash Report
        
        **Generated:** \(Date().formatted(date: .complete, time: .standard))
        **Generator:** SentinelCrash v1.1.0
        
        ---
        
        ## Crash Summary
        
        | Field | Value |
        |-------|-------|
        | Process | `\(crash.processName)` |
        | Bundle ID | `\(crash.bundleID.isEmpty ? "N/A" : crash.bundleID)` |
        | Timestamp | \(crash.timestamp.formatted(date: .complete, time: .standard)) |
        | Crash Type | **\(crash.crashType.rawValue)** |
        | Signal | `\(crash.signal.isEmpty ? "N/A" : crash.signal)` |
        | Exception | `\(crash.exception.isEmpty ? "N/A" : crash.exception)` |
        | iOS Version | \(crash.osVersion.isEmpty ? "N/A" : crash.osVersion) |
        | Device | \(crash.deviceModel.isEmpty ? "N/A" : crash.deviceModel) |
        | Category | \(crash.category.rawValue) |
        | Severity | **\(crash.severityGroup.rawValue)** |
        | JB Related | \(crash.isJailbreakRelevant ? "✅ Yes" : "❌ No") |
        | File | `\(crash.filePath)` |
        
        """

        if let jbInfo = crash.jailbreakInfo {
            md += """
            
            ## Jailbreak Context
            
            | Field | Value |
            |-------|-------|
            | JB Type | \(jbInfo.jailbreakType) |
            | Mode | \("Rootless") |
            | JB Root | `\(jbInfo.jbRoot)` |
            | Bootstrap | \(jbInfo.bootstrapVersion) |
            | Active Tweaks | \(jbInfo.installedTweaks.isEmpty ? "None detected" : jbInfo.installedTweaks.joined(separator: ", ")) |
            
            """
        }

        // Extract stack trace for report
        let frames = extractCrashedThreadFrames(from: crash.rawContent)
        if !frames.isEmpty {
            md += "\n## Crashed Thread Stack Trace\n\n```\n"
            md += frames.joined(separator: "\n")
            md += "\n```\n"
        }

        md += "\n---\n*Exported by SentinelCrash — Rootless CrashReporter for iOS 15+*\n"

        return md
    }

    // MARK: - Batch Report

    private func exportBatchReport(crashes: [CrashLog]) -> String {
        let sorted = crashes.sorted { $0.timestamp > $1.timestamp }

        var md = """
        # SentinelCrash Batch Report
        
        **Generated:** \(Date().formatted(date: .complete, time: .standard))
        **Total Crashes:** \(crashes.count)
        **Date Range:** \(sorted.last?.timestamp.formatted(date: .abbreviated, time: .omitted) ?? "?") — \(sorted.first?.timestamp.formatted(date: .abbreviated, time: .omitted) ?? "?")
        
        ---
        
        ## Summary by Type
        
        | Type | Count |
        |------|-------|
        """

        let byType = Dictionary(grouping: crashes, by: { $0.crashType }).mapValues { $0.count }.sorted { $0.value > $1.value }
        for (type, count) in byType {
            md += "| \(type.rawValue) | \(count) |\n"
        }

        md += "\n## Summary by Process\n\n| Process | Crashes | Last Seen |\n|---------|---------|----------|\n"

        let byProcess = Dictionary(grouping: crashes, by: { $0.processName })
        let processSorted = byProcess.map { ($0.key, $0.value.count, $0.value.map { $0.timestamp }.max() ?? Date()) }
            .sorted { $0.1 > $1.1 }

        for (name, count, lastSeen) in processSorted.prefix(20) {
            md += "| `\(name)` | \(count) | \(lastSeen.formatted(date: .abbreviated, time: .shortened)) |\n"
        }

        md += "\n---\n\n## Individual Crashes\n\n"

        for (idx, crash) in sorted.prefix(50).enumerated() {
            md += """
            ### \(idx + 1). \(crash.processName) — \(crash.crashType.rawValue)
            
            - **Time:** \(crash.timestamp.formatted(date: .abbreviated, time: .standard))
            - **Signal:** `\(crash.signal.isEmpty ? "N/A" : crash.signal)`
            - **Exception:** `\(crash.exception.isEmpty ? "N/A" : crash.exception)`
            - **Category:** \(crash.category.rawValue) · **Severity:** \(crash.severityGroup.rawValue)
            
            
            """
        }

        if crashes.count > 50 {
            md += "\n> *... and \(crashes.count - 50) more crashes not shown.*\n"
        }

        md += "\n---\n*Exported by SentinelCrash — Rootless CrashReporter for iOS 15+*\n"

        return md
    }

    // MARK: - Helpers

    private func extractCrashedThreadFrames(from content: String) -> [String] {
        var frames: [String] = []
        var inCrashedThread = false
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Thread") && trimmed.contains("Crashed") {
                inCrashedThread = true
                frames.append(trimmed) // Include the thread header
                continue
            }
            if inCrashedThread && trimmed.hasPrefix("Thread ") && !trimmed.contains("Crashed") { break }
            if trimmed.hasPrefix("Binary Images:") { break }

            if inCrashedThread {
                if trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                    frames.append(trimmed)
                }
            }
        }
        return frames
    }
}
