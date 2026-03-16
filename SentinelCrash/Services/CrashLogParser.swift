import Foundation

// MARK: - CrashLogParser
final class CrashLogParser: Sendable {

    private let rawContentLimit = 250_000

    // MARK: - Main Parse Entry
    func parse(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> CrashLog? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        if let log = parseIPS(content: trimmedContent, filePath: filePath, jbEnv: jbEnv) {
            return log
        }

        if let log = parseClassicCrash(content: trimmedContent, filePath: filePath, jbEnv: jbEnv) {
            return log
        }

        // Try diagnostic/syslog formats from new paths (.txt, .diag, .log from /var/db/diagnostics, /var/jb/var/log, etc.)
        if let log = parseDiagnosticLog(content: trimmedContent, filePath: filePath, jbEnv: jbEnv) {
            return log
        }

        return parseGeneric(content: trimmedContent, filePath: filePath, jbEnv: jbEnv)
    }

    // MARK: - Diagnostic / Syslog Format (.txt, .diag from /var/db/diagnostics, /var/jb/var/log, AppleSupport)
    private func parseDiagnosticLog(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> CrashLog? {
        let lower = filePath.lowercased()
        let isDiagPath = lower.contains("diagnostics") || lower.contains("applesupport") || lower.contains("var/log") || lower.contains("diagnosticpipeline")
        guard isDiagPath else { return nil }

        // Extract process from syslog-style lines: "process[pid]: message" or "date host process[pid]: message"
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        var processName = extractFromFilename(filePath)
        var detectedSignal = ""
        var detectedError = ""
        var timestamp = fileModificationDate(filePath) ?? Date()

        // Scan for crash indicators in diagnostic logs
        let crashKeywords = ["SIGABRT", "SIGSEGV", "SIGBUS", "SIGTRAP", "SIGILL", "SIGFPE",
                           "EXC_BAD_ACCESS", "EXC_CRASH", "EXC_RESOURCE", "EXC_GUARD",
                           "panic", "Panic", "PANIC", "watchdog", "Watchdog",
                           "jetsam", "Jetsam", "JETSAM", "abort", "crash", "fault"]

        var hasCrashIndicator = false
        for line in lines.prefix(200) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Try syslog format: "Mon DD HH:MM:SS host process[pid]:"
            if let syslogMatch = trimmed.range(of: #"\w+\s+\d+\s+[\d:]+\s+\S+\s+(\S+)\[(\d+)\]"#, options: .regularExpression) {
                let matched = String(trimmed[syslogMatch])
                let parts = matched.components(separatedBy: " ")
                if let procPart = parts.last {
                    let name = procPart.components(separatedBy: "[").first ?? procPart
                    if !name.isEmpty && name != "kernel" { processName = name }
                }
                // Try parse timestamp from syslog line
                if let ts = parseSyslogTimestamp(from: trimmed) { timestamp = ts }
            }

            // Check for crash keywords
            for keyword in crashKeywords {
                if trimmed.contains(keyword) {
                    hasCrashIndicator = true
                    if detectedSignal.isEmpty {
                        let upper = keyword.uppercased()
                        if upper.hasPrefix("SIG") || upper.hasPrefix("EXC_") {
                            detectedSignal = upper
                        }
                    }
                    if detectedError.isEmpty && (trimmed.contains("error") || trimmed.contains("fault") || trimmed.contains("abort")) {
                        detectedError = String(trimmed.prefix(200))
                    }
                }
            }
        }

        // Only create a log if we found crash indicators — skip boring diagnostic files
        guard hasCrashIndicator else { return nil }

        let crashType = determineCrashType(signal: detectedSignal, exception: detectedError, content: content)
        let classification = classify(processName: processName, bundleID: "", filePath: filePath, content: content, crashType: crashType)

        return CrashLog(
            processName: processName,
            bundleID: "",
            timestamp: timestamp,
            crashType: crashType,
            signal: detectedSignal,
            exception: detectedError,
            osVersion: "",
            deviceModel: "",
            rawContent: limitedRawContent(content),
            filePath: filePath,
            fileSize: fileByteSize(filePath),
            category: classification.0,
            severityGroup: classification.1,
            isSystemProcess: classification.2,
            isJailbreakRelevant: classification.3,
            jailbreakInfo: buildJailbreakInfo(content: content, filePath: filePath, jbEnv: jbEnv)
        )
    }

    private func parseSyslogTimestamp(from line: String) -> Date? {
        // "Mar 15 23:45:12 ..." format
        let pattern = #"^(\w{3})\s+(\d{1,2})\s+([\d:]{8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 4 else { return nil }
        let monthStr = Range(match.range(at: 1), in: line).map { String(line[$0]) } ?? ""
        let dayStr = Range(match.range(at: 2), in: line).map { String(line[$0]) } ?? ""
        let timeStr = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""

        let df = DateFormatter()
        df.dateFormat = "MMM d HH:mm:ss yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")
        let year = Calendar.current.component(.year, from: Date())
        return df.date(from: "\(monthStr) \(dayStr) \(timeStr) \(year)")
    }

    // MARK: - IPS Format (iOS 15+)
    private func parseIPS(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> CrashLog? {
        let lines = content.components(separatedBy: .newlines)
        guard let firstNonEmptyLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              firstNonEmptyLine.trimmingCharacters(in: .whitespaces).hasPrefix("{") else {
            return nil
        }

        guard let headerRange = firstJSONObjectRange(in: content) else { return nil }
        let headerJSON = String(content[headerRange])

        guard let data = headerJSON.data(using: .utf8),
              let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let bodyStart = content.index(after: headerRange.upperBound)
        let body = bodyStart < content.endIndex
            ? String(content[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let processName = preferredString([
            header["procName"],
            header["app_name"],
            header["name"],
            header["largestProcess"],
            extractFromFilename(filePath)
        ]) ?? extractFromFilename(filePath)

        let bundleID = preferredString([
            header["bundleID"],
            header["bundleId"],
            header["bundle_id"]
        ]) ?? ""

        let osVersion = preferredString([
            header["osVersion"],
            header["os_version"],
            header["build"]
        ]) ?? nestedOSVersionString(from: body) ?? ""

        let deviceModel = preferredString([
            header["modelCode"],
            header["product"],
            header["model"]
        ]) ?? nestedJSONStringValue(key: "product", in: body) ?? nestedJSONStringValue(key: "modelCode", in: body) ?? ""

        let timestampString = preferredString([
            header["captureTime"],
            header["timestamp"],
            header["date"]
        ])
        let timestamp = timestampString.flatMap(parseTimestamp) ?? fileModificationDate(filePath) ?? Date()

        let exception = extractException(from: body, header: header)
        let signal = extractSignal(from: body) ?? extractSignal(from: content) ?? signalFromHeader(header) ?? ""
        let crashType = determineCrashType(signal: signal, exception: exception, content: content)
        let classification = classify(processName: processName, bundleID: bundleID, filePath: filePath, content: content, crashType: crashType)

        return CrashLog(
            processName: processName,
            bundleID: bundleID,
            timestamp: timestamp,
            crashType: crashType,
            signal: signal,
            exception: exception,
            osVersion: osVersion,
            deviceModel: deviceModel,
            rawContent: limitedRawContent(content),
            filePath: filePath,
            fileSize: fileByteSize(filePath),
            category: classification.0,
            severityGroup: classification.1,
            isSystemProcess: classification.2,
            isJailbreakRelevant: classification.3,
            jailbreakInfo: buildJailbreakInfo(content: content, filePath: filePath, jbEnv: jbEnv)
        )
    }

    // MARK: - Classic .crash Format
    private func parseClassicCrash(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> CrashLog? {
        let lines = content.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.contains("Process:") || $0.contains("Exception Type:") || $0.contains("Date/Time:") }) else {
            return nil
        }

        var processName = ""
        var bundleID = ""
        var osVersion = ""
        var deviceModel = ""
        var exception = ""
        var signal = ""
        var timestamp = fileModificationDate(filePath) ?? Date()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Process:") || trimmed.hasPrefix("Command:") {
                let key = trimmed.hasPrefix("Process:") ? "Process:" : "Command:"
                processName = extractValue(from: trimmed, key: key)
                if let range = processName.range(of: " [") {
                    processName = String(processName[..<range.lowerBound])
                }
            } else if trimmed.hasPrefix("Identifier:") {
                bundleID = extractValue(from: trimmed, key: "Identifier:")
            } else if trimmed.hasPrefix("OS Version:") {
                osVersion = extractValue(from: trimmed, key: "OS Version:")
            } else if trimmed.hasPrefix("Hardware Model:") || trimmed.hasPrefix("Hardware model:") {
                let key = trimmed.hasPrefix("Hardware Model:") ? "Hardware Model:" : "Hardware model:"
                deviceModel = extractValue(from: trimmed, key: key)
            } else if trimmed.hasPrefix("Exception Type:") || trimmed.hasPrefix("Event:") {
                let key = trimmed.hasPrefix("Exception Type:") ? "Exception Type:" : "Event:"
                exception = extractValue(from: trimmed, key: key)
            } else if trimmed.hasPrefix("Exception Codes:") {
                let codes = extractValue(from: trimmed, key: "Exception Codes:")
                if exception.isEmpty { exception = codes }
            } else if trimmed.hasPrefix("Termination Signal:") {
                signal = extractValue(from: trimmed, key: "Termination Signal:")
                if let sig = signal.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces), sig.hasPrefix("SIG") {
                    signal = sig
                }
            } else if trimmed.hasPrefix("Signal:") {
                signal = extractValue(from: trimmed, key: "Signal:")
            } else if trimmed.hasPrefix("Date/Time:") {
                let dtStr = extractValue(from: trimmed, key: "Date/Time:")
                timestamp = parseTimestamp(dtStr) ?? fileModificationDate(filePath) ?? Date()
            }
        }

        if processName.isEmpty {
            processName = extractFromFilename(filePath)
        }
        if signal.isEmpty {
            signal = extractSignalFromException(exception)
        }

        let crashType = determineCrashType(signal: signal, exception: exception, content: content)
        let classification = classify(processName: processName, bundleID: bundleID, filePath: filePath, content: content, crashType: crashType)

        return CrashLog(
            processName: processName,
            bundleID: bundleID,
            timestamp: timestamp,
            crashType: crashType,
            signal: signal,
            exception: exception,
            osVersion: osVersion,
            deviceModel: deviceModel,
            rawContent: limitedRawContent(content),
            filePath: filePath,
            fileSize: fileByteSize(filePath),
            category: classification.0,
            severityGroup: classification.1,
            isSystemProcess: classification.2,
            isJailbreakRelevant: classification.3,
            jailbreakInfo: buildJailbreakInfo(content: content, filePath: filePath, jbEnv: jbEnv)
        )
    }

    // MARK: - Generic Fallback
    private func parseGeneric(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> CrashLog? {
        let header = extractTopLevelJSONDictionary(from: content)
        let processName = preferredString([
            header?["procName"],
            header?["app_name"],
            header?["name"],
            header?["largestProcess"],
            extractFromFilename(filePath)
        ]) ?? extractFromFilename(filePath)
        let timestamp = preferredString([
            header?["captureTime"],
            header?["timestamp"],
            header?["date"]
        ]).flatMap(parseTimestamp) ?? fileModificationDate(filePath) ?? Date()
        let signal = extractSignal(from: content) ?? signalFromHeader(header ?? [:]) ?? ""
        let exception = extractException(from: content, header: header)
        let crashType = determineCrashType(signal: signal, exception: exception, content: content)
        let bundleID = preferredString([header?["bundleID"], header?["bundleId"], header?["bundle_id"]]) ?? ""
        let classification = classify(processName: processName, bundleID: bundleID, filePath: filePath, content: content, crashType: crashType)

        return CrashLog(
            processName: processName,
            bundleID: bundleID,
            timestamp: timestamp,
            crashType: crashType,
            signal: signal,
            exception: exception,
            osVersion: preferredString([header?["osVersion"], header?["os_version"], header?["build"]]) ?? "",
            deviceModel: preferredString([header?["modelCode"], header?["product"], header?["model"]]) ?? "",
            rawContent: limitedRawContent(content),
            filePath: filePath,
            fileSize: fileByteSize(filePath),
            category: classification.0,
            severityGroup: classification.1,
            isSystemProcess: classification.2,
            isJailbreakRelevant: classification.3,
            jailbreakInfo: buildJailbreakInfo(content: content, filePath: filePath, jbEnv: jbEnv)
        )
    }

    // MARK: - Crash Type Detection
    func determineCrashType(signal: String, exception: String, content: String) -> CrashType {
        let sigUpper = signal.uppercased()
        let excUpper = exception.uppercased()

        // 1. Trust signal and exception first — these are structured fields
        let structured = sigUpper + " " + excUpper

        if structured.contains("JETSAM") || structured.contains("JETSAMEVENT") || structured.contains("SYSTEMMEMORYRESET") { return .jetsam }
        if structured.contains("SIGSEGV") { return .sigsegv }
        if structured.contains("SIGABRT") { return .sigabrt }
        if structured.contains("SIGBUS") { return .sigbus }
        if structured.contains("SIGFPE") { return .sigfpe }
        if structured.contains("SIGILL") { return .sigill }
        if structured.contains("SIGTRAP") { return .sigtrap }
        if structured.contains("EXC_BAD_ACCESS") { return .exc_bad_access }
        if structured.contains("EXC_CRASH") { return .exc_crash }
        if structured.contains("EXC_RESOURCE") || structured.contains("WAKEUPS_RESOURCE") || structured.contains("DISKWRITES_RESOURCE") || structured.contains("CPU_RESOURCE") || structured.contains("WAKEUPS") { return .exc_resource }
        if structured.contains("EXC_GUARD") { return .exc_guard }
        if structured.contains("EXC_BAD_INSTRUCTION") { return .exc_bad_instruction }
        if structured.contains("WATCHDOG") { return .watchdog }
        if structured.contains("PANIC") { return .panic }

        // 2. Scan header/metadata area of content (first 2000 chars) for keywords
        //    that might not appear in structured fields — but use targeted checks
        let contentPrefix = String(content.prefix(min(content.count, 2000))).uppercased()

        // Jetsam/panic are safe to detect from content headers
        if contentPrefix.contains("JETSAMEVENT") || contentPrefix.contains("SYSTEMMEMORYRESET") { return .jetsam }
        // Only match PANIC as a standalone concept, not inside library paths like "libpanic_hooks.dylib"
        if contentPrefix.contains("\"PANIC\"") || contentPrefix.hasPrefix("PANIC") || contentPrefix.contains("KERNEL PANIC") { return .panic }

        // Signals can also appear in content metadata lines
        if contentPrefix.contains("SIGSEGV") { return .sigsegv }
        if contentPrefix.contains("SIGABRT") { return .sigabrt }
        if contentPrefix.contains("SIGBUS") { return .sigbus }
        if contentPrefix.contains("EXC_BAD_ACCESS") { return .exc_bad_access }
        if contentPrefix.contains("EXC_CRASH") { return .exc_crash }
        if contentPrefix.contains("EXC_RESOURCE") || contentPrefix.contains("WAKEUPS") { return .exc_resource }
        if contentPrefix.contains("WATCHDOG") { return .watchdog }

        // 3. JB/tweak/dylib detection from content — only if nothing else matched
        if contentPrefix.contains("SUBSTRATE") || contentPrefix.contains("CYNJECT") || contentPrefix.contains("ELLEKIT") {
            return .jailbreakError
        }
        if contentPrefix.contains("IMAGE NOT FOUND") || contentPrefix.contains("LIBRARY NOT LOADED") {
            return .dylib
        }

        return .unknown
    }

    // MARK: - Helper Methods
    private func preferredString(_ values: [Any?]) -> String? {
        for value in values {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func firstJSONObjectRange(in content: String) -> ClosedRange<String.Index>? {
        var depth = 0
        var start: String.Index?
        var index = content.startIndex

        while index < content.endIndex {
            let char = content[index]
            if char == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0, let start {
                    return start...index
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    private func extractTopLevelJSONDictionary(from content: String) -> [String: Any]? {
        guard let range = firstJSONObjectRange(in: content) else { return nil }
        let json = String(content[range])
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func nestedJSONStringValue(key: String, in body: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escapedKey)"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(body.startIndex..., in: body)
        guard let match = regex.firstMatch(in: body, range: nsRange), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return String(body[range])
    }

    private func nestedOSVersionString(from body: String) -> String? {
        if let train = nestedJSONStringValue(key: "train", in: body),
           let build = nestedJSONStringValue(key: "build", in: body) {
            return "\(train) (\(build))"
        }
        return nil
    }

    private func signalFromHeader(_ header: [String: Any]) -> String? {
        if let bugType = header["bug_type"] as? String {
            switch bugType {
            case "298": return "JETSAM"
            case "142": return "WAKEUPS_RESOURCE"
            case "309": return "WATCHDOG"
            default: break
            }
        }
        return nil
    }

    private func extractException(from content: String, header: [String: Any]? = nil) -> String {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Exception Type:") {
                return extractValue(from: trimmed, key: "Exception Type:")
            }
            if trimmed.hasPrefix("Event:") {
                return extractValue(from: trimmed, key: "Event:")
            }
        }

        if let header,
           let bugType = header["bug_type"] as? String {
            switch bugType {
            case "298": return "JetsamEvent"
            case "142": return "Wakeups Resource"
            case "313": return "Feedback"
            case "210", "211", "212": return "Crash"
            case "309": return "Watchdog"
            default: return "bug_type \(bugType)"
            }
        }

        if let event = nestedJSONStringValue(key: "event", in: content) {
            return event
        }
        return ""
    }

    private func extractValue(from line: String, key: String) -> String {
        var result = line
        if result.hasPrefix(key) {
            result = String(result.dropFirst(key.count))
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private func extractSignal(from content: String) -> String? {
        let patterns = [
            "SIG(SEGV|ABRT|BUS|FPE|ILL|TRAP|KILL|TERM|HUP|INT|QUIT|PIPE|ALRM)",
            "EXC_(BAD_ACCESS|CRASH|RESOURCE|GUARD|BAD_INSTRUCTION)",
            "JETSAM",
            "WATCHDOG",
            "WAKEUPS_RESOURCE",
            "DISKWRITES_RESOURCE"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range, in: content) {
                return String(content[range])
            }
        }
        return nil
    }

    private func extractSignalFromException(_ exception: String) -> String {
        let upper = exception.uppercased()
        if upper.contains("SIGSEGV") { return "SIGSEGV" }
        if upper.contains("SIGABRT") { return "SIGABRT" }
        if upper.contains("SIGBUS") { return "SIGBUS" }
        if upper.contains("SIGFPE") { return "SIGFPE" }
        if upper.contains("SIGILL") { return "SIGILL" }
        if upper.contains("EXC_BAD_ACCESS") { return "EXC_BAD_ACCESS" }
        if upper.contains("EXC_RESOURCE") || upper.contains("WAKEUPS") { return "EXC_RESOURCE" }
        if upper.contains("JETSAM") || upper.contains("JETSAMEVENT") { return "JETSAM" }
        if upper.contains("WATCHDOG") { return "WATCHDOG" }
        return ""
    }

    private func classify(processName: String, bundleID: String, filePath: String, content: String, crashType: CrashType) -> (CrashCategory, CrashSeverityGroup, Bool, Bool) {
        let process = processName.lowercased()
        let bundle = bundleID.lowercased()
        let path = filePath.lowercased()

        let noisyProcesses: Set<String> = [
            "dtdeviceinfod",
            "sirisearchfeedback",
            "stacks",
            "systemmemoryreset",
            "com.apple.mobilesoftwareupdate.updatebrainservice"
        ]

        let combinedMeta = "\(process) \(bundle) \(path)"
        let isDeveloperToolNoise =
            combinedMeta.contains("com.apple.coredevice") ||
            path.contains("/system/developer/") ||
            process.contains("dtdeviceinfod") ||
            combinedMeta.contains("xcode") ||
            combinedMeta.contains("coredevice")

        let isNoise = noisyProcesses.contains(process) || path.contains("/assistant/") || process.contains("feedback") || bundle.contains("feedback") || isDeveloperToolNoise
        // Check JB relevance against a limited prefix to avoid lowercasing entire content
        let contentCheckLimit = min(content.count, 8000)
        let contentPrefix = String(content.prefix(contentCheckLimit)).lowercased()
        let combinedForJB = "\(combinedMeta) \(contentPrefix)"

        let isJBRelevant = ["/var/jb", "ellekit", "substrate", "substitute", "tweak", "hook", "procursus", "dopamine", "palera1n", "nathanlr", "sileo", "zebra"].contains { combinedForJB.contains($0) }
        let knownDaemons: Set<String> = [
            "springboard", "backboardd", "runningboardd", "launchd", "kernel",
            "mediaserverd", "installd", "assertiond", "aggregated", "apsd",
            "bluetoothd", "cfprefsd", "containermanagerd", "corespeechd",
            "dasd", "distnoted", "fileproviderd", "fseventsd", "healthd",
            "healthappd", "identityservicesd", "locationd", "logd", "mdnsresponder",
            "mobileassetd", "nsurlsessiond", "powerd", "rapportd",
            "routined", "searchd", "symptomsd", "thermalmonitord",
            "usermanagerd", "wifid", "wirelessproxd",
            "commcenter", "accessoryd", "audiomxd", "biomesyncd",
            "contextstored", "callservicesd", "duetexpertd", "lsd",
            "notifyd", "passd", "replayd", "sharingd", "siriknowledged",
            "suggestd", "timed", "translationd", "weatherd",
        ]
        let isSystem = bundle.hasPrefix("com.apple.") || knownDaemons.contains(process)

        let category: CrashCategory
        switch crashType {
        case .jetsam:
            category = .jetsam
        case .exc_resource:
            category = .resource
        case .watchdog:
            category = .watchdog
        case .panic:
            category = .panic
        case .dylib:
            category = .dylib
        case .jailbreakError, .tweak:
            category = .jailbreak
        default:
            category = process == "springboard" ? .springboard : .appCrash
        }

        let severity: CrashSeverityGroup
        if isNoise {
            severity = .noise
        } else {
            switch category {
            case .appCrash, .jailbreak, .springboard, .dylib:
                severity = .relevant
            case .jetsam, .resource, .watchdog, .panic:
                severity = .system
            case .unknown:
                severity = isSystem ? .system : .relevant
            }
        }

        return (category, severity, isSystem, isJBRelevant)
    }

    private func extractFromFilename(_ path: String) -> String {
        let filename = (path as NSString).lastPathComponent
        var name = (filename as NSString).deletingPathExtension
        if let range = name.range(of: "_20") { name = String(name[..<range.lowerBound]) }
        if let range = name.range(of: "-20") { name = String(name[..<range.lowerBound]) }
        return name.isEmpty ? filename : name
    }

    private static let timestampFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss.SSSZZ",
            "yyyy-MM-dd HH:mm:ss.SS ZZ",
            "yyyy-MM-dd HH:mm:ss.S ZZ",
            "yyyy-MM-dd HH:mm:ss ZZ",
            "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yy HH:mm:ss"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()

    private func parseTimestamp(_ str: String) -> Date? {
        for formatter in Self.timestampFormatters {
            if let date = formatter.date(from: str) { return date }
        }
        return nil
    }

    private func fileModificationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    private func fileByteSize(_ path: String) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
    }

    private func limitedRawContent(_ content: String) -> String {
        guard content.count > rawContentLimit else { return content }
        let end = content.index(content.startIndex, offsetBy: rawContentLimit)
        return String(content[..<end]) + "\n\n[SentinelCrash truncated preview for performance]"
    }

    private func buildJailbreakInfo(content: String, filePath: String, jbEnv: JailbreakEnvironment?) -> JailbreakInfo? {
        guard let env = jbEnv else { return nil }

        let dylibs = extractDylibs(from: content)
        let tweaks = dylibs.filter {
            let lower = $0.lowercased()
            return lower.contains("tweak") || lower.contains("substrate") || lower.contains("ellekit") || lower.contains("substitute")
        }

        return JailbreakInfo(
            jailbreakType: env.jailbreakName,
            isRootless: env.isRootless,
            jbRoot: env.jbRoot,
            installedTweaks: tweaks,
            dylibs: dylibs,
            bootstrapVersion: env.procursusStrapped ? "Procursus" : "Unknown"
        )
    }

    private func extractDylibs(from content: String) -> [String] {
        var dylibs: [String] = []
        let lines = content.components(separatedBy: .newlines)
        var inBinaryImages = false

        for line in lines {
            if line.contains("Binary Images:") {
                inBinaryImages = true
                continue
            }
            if inBinaryImages {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Exit when we hit an empty line or a new section header after binary images
                if trimmed.isEmpty {
                    if !dylibs.isEmpty { break }
                    continue
                }
                // Binary image lines start with 0x address; stop if we hit non-binary-image content
                if !trimmed.hasPrefix("0x") && !trimmed.hasPrefix("0X") && !dylibs.isEmpty {
                    break
                }
                if let lastComponent = line.components(separatedBy: "/").last?.trimmingCharacters(in: .whitespaces),
                   !lastComponent.isEmpty {
                    dylibs.append(lastComponent)
                }
            }
        }

        return Array(Set(dylibs)).sorted()
    }
}
