import SwiftUI

struct CrashDetailView: View {
    let log: CrashLog
    @State private var selectedTab: Int
    @State private var showShareSheet = false
    @State private var showCopyAlert = false
    @State private var symbolicationResult: SymbolicationService.SymbolicationResult?
    @EnvironmentObject var crashMonitor: CrashMonitorService
    private let symbolicator = SymbolicationService()

    init(log: CrashLog) {
        self.log = log
        // Smart default: show the most useful tab for this crash type
        let initialTab: Int
        switch log.crashType {
        case .sigsegv, .sigabrt, .sigbus, .sigfpe, .sigill, .sigtrap,
             .exc_bad_access, .exc_bad_instruction, .exc_guard:
            // Real crashes with stack traces → Stack Trace
            initialTab = 1
        case .exc_resource:
            // Resource limits (Microstackshot) → Stack Trace (heat map)
            initialTab = 1
        case .tweak, .dylib, .jailbreakError:
            // Tweak/dylib crashes → Stack Trace
            initialTab = 1
        case .jetsam:
            // Memory events → Summary (has Memory Pressure section)
            initialTab = 0
        case .exc_crash, .watchdog:
            // IPS crashes → Summary (has Termination reason)
            initialTab = 0
        case .panic:
            // Kernel panics → Raw Log (full context needed)
            initialTab = 2
        case .unknown:
            // Unknown → Raw Log (user sees everything)
            initialTab = 2
        }
        _selectedTab = State(initialValue: initialTab)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                crashHeader
                
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("detail.summary".localized).tag(0)
                    Text("detail.stackTrace".localized).tag(1)
                    Text("detail.rawLog".localized).tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content — no page-swipe to avoid conflicting with nav back gesture
                Group {
                    switch selectedTab {
                    case 0: summaryTab
                    case 1: stackTraceTab
                    case 2: rawLogTab
                    default: summaryTab
                    }
                }
            }
        }
        .navigationTitle(log.processName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            crashMonitor.markAsRead(log)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    crashMonitor.toggleFavorite(log)
                } label: {
                    Image(systemName: log.isFavorited ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                }
                
                Button {
                    UIPasteboard.general.string = log.rawContent
                    showCopyAlert = true
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.cyan)
                }
                
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.cyan)
                }
            }
        }
        .alert("detail.copied".localized, isPresented: $showCopyAlert) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("detail.copiedMsg".localized)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [log.rawContent])
        }
    }
    
    // MARK: - Header
    private var crashHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(typeColor.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: log.crashType.icon)
                    .foregroundColor(typeColor)
                    .font(.title2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(log.processName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    SeverityBadge(log: log)
                    
                    if !log.exception.isEmpty {
                        Text(log.exception.prefix(30) + (log.exception.count > 30 ? "..." : ""))
                            .font(.caption.monospaced())
                            .foregroundColor(.gray)
                    }
                }
                
                Text(log.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundColor(.gray)

                // Crash location — WHERE it crashed
                if let location = log.crashLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text(location)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.orange)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.04))
    }
    
    // MARK: - Summary Tab
    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Key info
                DetailSection(title: "detail.processInfo".localized) {
                    DetailRow(key: "detail.process".localized, value: log.processName)
                    if !log.bundleID.isEmpty {
                        DetailRow(key: "detail.bundleID".localized, value: log.bundleID)
                    }
                    if !log.osVersion.isEmpty {
                        DetailRow(key: "detail.iosVersion".localized, value: log.osVersion)
                    }
                    if !log.deviceModel.isEmpty {
                        DetailRow(key: "detail.device".localized, value: log.deviceModel)
                    }
                }
                
                DetailSection(title: "detail.crashInfo".localized) {
                    DetailRow(key: "detail.type".localized, value: log.crashType.rawValue, valueColor: typeColor)
                    if !log.signal.isEmpty {
                        DetailRow(key: "detail.signal".localized, value: log.signal, valueColor: .orange)
                    }
                    if !log.exception.isEmpty {
                        DetailRow(key: "detail.exception".localized, value: log.exception, valueColor: .red)
                    }
                    // Show termination reason for IPS logs
                    if let termination = extractTerminationReason(from: log.rawContent) {
                        DetailRow(key: "detail.termination".localized, value: termination, valueColor: .orange)
                    }
                    DetailRow(key: "detail.time".localized, value: log.timestamp.formatted(date: .complete, time: .standard))
                    DetailRow(key: "detail.fileSize".localized, value: ByteCountFormatter.string(fromByteCount: log.fileSize, countStyle: .file))
                }

                // Jetsam-specific memory info
                if log.crashType == .jetsam, let jetsamInfo = extractJetsamInfo(from: log.rawContent) {
                    DetailSection(title: "detail.memoryPressure".localized) {
                        if let largest = jetsamInfo.largestProcess {
                            DetailRow(key: "detail.largestProcess".localized, value: largest, valueColor: .red)
                        }
                        if let pages = jetsamInfo.pageSize {
                            DetailRow(key: "detail.pageSize".localized, value: pages)
                        }
                        if let free = jetsamInfo.freePages {
                            DetailRow(key: "detail.freePages".localized, value: free, valueColor: .orange)
                        }
                        if let reason = jetsamInfo.reason {
                            DetailRow(key: "detail.reason".localized, value: reason, valueColor: .red)
                        }
                        if let killed = jetsamInfo.killedCount {
                            DetailRow(key: "detail.processesKilled".localized, value: "\(killed)", valueColor: .orange)
                        }
                    }
                }
                
                if let jbInfo = log.jailbreakInfo {
                    DetailSection(title: "detail.jbContext".localized) {
                        DetailRow(key: "jb.type".localized, value: jbInfo.jailbreakType, valueColor: .cyan)
                        DetailRow(key: "jb.mode".localized, value: "Rootless", valueColor: .cyan)
                        DetailRow(key: "jb.root".localized, value: jbInfo.jbRoot, valueColor: .yellow)
                        DetailRow(key: "jb.bootstrap".localized, value: jbInfo.bootstrapVersion, valueColor: .orange)
                        if !jbInfo.installedTweaks.isEmpty {
                            DetailRow(key: "detail.activeTweaks".localized, value: jbInfo.installedTweaks.joined(separator: "\n"), valueColor: .purple)
                        }
                    }
                }
                
                DetailSection(title: "detail.fileLocation".localized) {
                    Text(log.filePath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.cyan)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Stack Trace Tab
    private var stackTraceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                // 1. Try classic text format (Thread X Crashed)
                let classicFrames = extractStackTrace(from: log.rawContent)

                if !classicFrames.isEmpty {
                    Label("detail.crashedThread".localized, systemImage: "flame.fill")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                        .padding(.bottom, 4)

                    ForEach(Array(classicFrames.enumerated()), id: \.offset) { idx, frame in
                        StackFrameRow(index: idx, frame: frame)
                    }
                } else {
                    // 2. Try Microstackshot format (Heaviest stack)
                    let microResult = extractMicrostackshot(from: log.rawContent)

                    if !microResult.frames.isEmpty {
                        // Event info header
                        if let event = microResult.event {
                            HStack(spacing: 6) {
                                Image(systemName: "cpu")
                                    .foregroundColor(.purple)
                                    .font(.caption)
                                Text(event)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.purple)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.1)))
                            .padding(.bottom, 4)
                        }

                        if let cpu = microResult.cpuInfo {
                            Text(cpu)
                                .font(.caption2.monospaced())
                                .foregroundColor(.orange)
                                .padding(.bottom, 8)
                        }

                        Label("detail.heaviestStack".localized(microResult.frames.count), systemImage: "chart.bar.fill")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                            .padding(.bottom, 4)

                        ForEach(Array(microResult.frames.enumerated()), id: \.offset) { idx, frame in
                            MicrostackFrameRow(frame: frame, maxSamples: microResult.maxSamples)
                        }
                    } else {
                        // 3. Try IPS JSON format
                        let ipsFrames = extractIPSStackTrace(from: log.rawContent)

                        if !ipsFrames.isEmpty {
                            Label("Thread 0 (Triggered)", systemImage: "flame.fill")
                                .font(.caption.bold())
                                .foregroundColor(.red)
                                .padding(.bottom, 2)

                            if let termination = extractTerminationReason(from: log.rawContent) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.octagon.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Text(termination)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.orange)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                                .padding(.bottom, 8)
                            }

                            ForEach(Array(ipsFrames.enumerated()), id: \.offset) { idx, frame in
                                StackFrameRow(index: idx, frame: frame)
                            }
                        } else {
                            // 4. Nothing found
                            VStack(spacing: 12) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.title)
                                    .foregroundColor(.gray.opacity(0.4))
                                Text("detail.noStackTrace".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                if let termination = extractTerminationReason(from: log.rawContent) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("detail.terminationReason".localized)
                                            .font(.caption2.bold())
                                            .foregroundColor(.gray)
                                        Text(termination)
                                            .font(.caption.monospaced())
                                            .foregroundColor(.orange)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                                }
                            }
                            .padding()
                        }
                    }
                }

                // Symbolication section
                Divider().background(Color.white.opacity(0.1)).padding(.vertical, 8)

                if let result = symbolicationResult {
                    HStack {
                        Label("detail.symbolication".localized, systemImage: "wand.and.stars")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                        Spacer()
                        let pct = String(format: "%.0f%%", result.resolvedPercentage)
                        Text("\(result.resolvedCount)/\(result.totalCount) (\(pct))")
                            .font(.caption2.monospaced())
                            .foregroundColor(result.resolvedPercentage > 50 ? .green : .orange)
                    }
                    .padding(.bottom, 4)

                    ForEach(Array(result.frames.enumerated()), id: \.offset) { idx, frame in
                        HStack(alignment: .top, spacing: 6) {
                            Text("#\(frame.index)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.gray)
                                .frame(width: 22, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(frame.symbol)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(frame.isResolved ? .green : .orange)
                                    .lineLimit(2)
                                if !frame.sourceInfo.isEmpty {
                                    Text(frame.sourceInfo)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }
                            Spacer()
                            if frame.isResolved {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Button(action: {
                        symbolicationResult = symbolicator.symbolicate(rawContent: log.rawContent)
                    }) {
                        Label("detail.runSymbolication".localized, systemImage: "wand.and.stars")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.3), lineWidth: 1)))
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Raw Log Tab
    private var rawLogTab: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                let isJSON = log.rawContent.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                Label(isJSON ? "detail.ipsJSON".localized : "detail.classicLog".localized, systemImage: isJSON ? "doc.text.fill" : "terminal.fill")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(log.rawContent.utf8.count), countStyle: .file))
                    .font(.caption2.monospaced())
                    .foregroundColor(.gray)
                Text("\(log.rawContent.components(separatedBy: "\n").count) lines")
                    .font(.caption2.monospaced())
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))

            // Content
            ScrollView([.horizontal, .vertical]) {
                if sanitizedRawLogText.isEmpty {
                    Text("detail.rawLogUnavailable".localized)
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    rawLogContentView
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .background(Color.black.opacity(0.5))
        }
    }

    @ViewBuilder
    private var rawLogContentView: some View {
        let content = sanitizedRawLogText
        let isJSON = content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
        let byteCount = content.utf8.count

        // Large files (>50KB): plain text only — syntax coloring would freeze UI
        if byteCount > 50_000 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("detail.largeLog".localized(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)))
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                // Show first 30KB in plain text to avoid SwiftUI freeze
                let displayLimit = 30_000
                let truncated = content.count > displayLimit
                let displayText = truncated ? String(content.prefix(displayLimit)) + "\n\n[… truncated for performance — \(content.count - displayLimit) chars hidden …]\n\nUse Copy (top right) for full log." : content

                Text(verbatim: displayText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if isJSON, let prettyJSON = prettyPrintedJSON(content) {
            // Medium files with syntax coloring — cap at 500 lines
            let lines = prettyJSON.components(separatedBy: "\n")
            let cappedLines = lines.count > 500 ? Array(lines.prefix(500)) : lines
            let cappedJSON = cappedLines.joined(separator: "\n") + (lines.count > 500 ? "\n\n// … \(lines.count - 500) more lines …" : "")
            coloredJSONView(cappedJSON)
        } else {
            Text(verbatim: content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.green.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prettyPrintedJSON(_ raw: String) -> String? {
        // IPS files have two JSON blocks: header + body
        // Try to pretty-print each one
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""

        // Find first JSON object (header)
        if let firstClose = findFirstJSONClose(in: trimmed) {
            let headerStr = String(trimmed[trimmed.startIndex...firstClose])
            if let data = headerStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                result += "// ─── IPS HEADER ───\n" + str
            } else {
                result += headerStr
            }

            // Body (second JSON object)
            let bodyStart = trimmed.index(after: firstClose)
            if bodyStart < trimmed.endIndex {
                let bodyStr = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = bodyStr.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: pretty, encoding: .utf8) {
                    result += "\n\n// ─── IPS BODY ───\n" + str
                } else {
                    result += "\n" + bodyStr
                }
            }
            return result.isEmpty ? nil : result
        }

        // Single JSON object
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return nil
    }

    private func findFirstJSONClose(in str: String) -> String.Index? {
        var depth = 0
        for idx in str.indices {
            if str[idx] == "{" { depth += 1 }
            else if str[idx] == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
        }
        return nil
    }

    private func coloredJSONView(_ json: String) -> some View {
        let lines = json.components(separatedBy: "\n")

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineNum, line in
                HStack(alignment: .top, spacing: 6) {
                    // Line number
                    Text("\(lineNum + 1)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.3))
                        .frame(width: 30, alignment: .trailing)

                    // Colored line
                    coloredLine(line)
                }
            }
        }
    }

    private func coloredLine(_ line: String) -> Text {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indent = String(line.prefix(while: { $0 == " " }))

        // Comment lines
        if trimmed.hasPrefix("//") {
            return Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.6))
        }

        // Key-value pair: "key" : value
        if let colonRange = trimmed.range(of: #"^\s*"[^"]+"\s*:"#, options: .regularExpression) {
            let keyPart = String(trimmed[colonRange])
            let rest = String(trimmed[colonRange.upperBound...])

            return Text(indent)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white) +
            Text(keyPart)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.cyan) +
            coloredValue(rest)
        }

        // Array/object brackets, other
        return Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
    }

    private func coloredValue(_ value: String) -> Text {
        let trimmed = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ","))
        let trailing = value.hasSuffix(",") ? "," : ""

        if trimmed.hasPrefix("\"") {
            // String value — green
            return Text(" " + value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.green)
        } else if trimmed == "true" || trimmed == "false" {
            // Boolean — yellow
            return Text(" " + trimmed)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.yellow) +
            Text(trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        } else if trimmed == "null" {
            return Text(" null" + trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.red.opacity(0.6))
        } else if Double(trimmed) != nil || Int(trimmed) != nil {
            // Number — orange
            return Text(" " + trimmed)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.orange) +
            Text(trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
        }

        return Text(" " + value)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
    }
    
    // MARK: - Helpers
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


    private var sanitizedRawLogText: String {
        let source = log.rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "" }

        let sanitizedScalars = source.unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 0: return "\\0"
            case 9, 10, 13: return String(scalar)
            case 32...126, 160...0x10FFFF: return String(scalar)
            default: return "\\u{" + String(scalar.value, radix: 16).uppercased() + "}"
            }
        }

        return sanitizedScalars.joined()
    }

    // MARK: - Microstackshot Parser

    struct MicrostackFrame {
        let samples: Int
        let library: String
        let offset: String
        let address: String
        let depth: Int    // indentation level
    }

    struct MicrostackResult {
        let frames: [MicrostackFrame]
        let event: String?
        let cpuInfo: String?
        let maxSamples: Int
    }

    private func extractMicrostackshot(from content: String) -> MicrostackResult {
        let lines = content.components(separatedBy: "\n")
        var frames: [MicrostackFrame] = []
        var event: String?
        var cpuInfo: String?
        var inHeaviestStack = false

        // Microstackshot pattern: leading spaces + number + "???" + (library + offset) + [address]
        let framePattern = #"^\s*(\d+)\s+\?\?\?\s+\((.+?)\s*\+\s*(\d+)\)\s*\[(0x[0-9a-fA-F]+)\]"#
        let frameRegex = try? NSRegularExpression(pattern: framePattern)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract event type
            if trimmed.hasPrefix("Event:") {
                event = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }

            // Extract CPU info
            if trimmed.hasPrefix("CPU:") {
                cpuInfo = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }

            // Enter heaviest stack section
            if trimmed.hasPrefix("Heaviest stack for the target process:") {
                inHeaviestStack = true
                continue
            }

            // Exit: empty line after collecting frames, or new section
            if inHeaviestStack && !frames.isEmpty && trimmed.isEmpty {
                break
            }
            if inHeaviestStack && trimmed.hasPrefix("Powerstats for:") {
                break
            }

            // Parse frame
            if inHeaviestStack, let regex = frameRegex {
                let nsRange = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: nsRange), match.numberOfRanges >= 5 {
                    let samplesStr = (Range(match.range(at: 1), in: line).map { String(line[$0]) }) ?? "0"
                    let library = (Range(match.range(at: 2), in: line).map { String(line[$0]) }) ?? "???"
                    let offset = (Range(match.range(at: 3), in: line).map { String(line[$0]) }) ?? "0"
                    let address = (Range(match.range(at: 4), in: line).map { String(line[$0]) }) ?? ""

                    // Calculate depth from leading spaces
                    let leadingSpaces = line.prefix(while: { $0 == " " }).count
                    let depth = leadingSpaces / 2

                    frames.append(MicrostackFrame(
                        samples: Int(samplesStr) ?? 0,
                        library: library,
                        offset: offset,
                        address: address,
                        depth: depth
                    ))
                }
            }
        }

        let maxSamples = frames.map { $0.samples }.max() ?? 1
        return MicrostackResult(frames: frames, event: event, cpuInfo: cpuInfo, maxSamples: maxSamples)
    }
    
    private func extractStackTrace(from content: String) -> [String] {
        var frames: [String] = []
        var inCrashThread = false
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Enter crash thread section
            if trimmed.contains("Thread") && trimmed.contains("Crashed") {
                inCrashThread = true
                continue
            }
            // Exit when hitting next thread header
            if inCrashThread && trimmed.hasPrefix("Thread ") && !trimmed.contains("Crashed") {
                inCrashThread = false
            }
            // Exit at Binary Images section
            if trimmed.hasPrefix("Binary Images:") {
                break
            }
            
            // Only collect frames from the crashed thread
            guard inCrashThread else { continue }
            
            if trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                frames.append(trimmed)
            }
        }
        
        // Fallback: if no crashed thread found, collect all stack frames
        // But skip if this is a Microstackshot format (handled by extractMicrostackshot)
        if frames.isEmpty && !content.contains("Heaviest stack for the target process:") && !content.contains("Data Source:      Microstackshots") {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                    frames.append(trimmed)
                }
            }
        }
        
        return frames
    }

    /// Extract stack frames from IPS JSON `threads[].frames[]` format.
    private func extractIPSStackTrace(from content: String) -> [String] {
        // Find the body JSON (second JSON block in IPS)
        guard let bodyDict = extractIPSBody(from: content) else { return [] }

        guard let threads = bodyDict["threads"] as? [[String: Any]] else { return [] }

        // Find the triggered (faulting) thread
        let faultingThread: [String: Any]?
        if let ft = bodyDict["faultingThread"] as? Int, ft < threads.count {
            faultingThread = threads[ft]
        } else {
            faultingThread = threads.first(where: { $0["triggered"] as? Bool == true }) ?? threads.first
        }

        guard let thread = faultingThread,
              let jsonFrames = thread["frames"] as? [[String: Any]] else { return [] }

        let usedImages = bodyDict["usedImages"] as? [[String: Any]] ?? []

        var result: [String] = []
        for (idx, frame) in jsonFrames.enumerated() {
            let imageIndex = frame["imageIndex"] as? Int ?? -1
            let imageOffset = frame["imageOffset"] as? Int ?? 0
            let symbol = frame["symbol"] as? String ?? ""
            let symbolLocation = frame["symbolLocation"] as? Int ?? 0

            // Resolve image name
            var imageName = "???"
            if imageIndex >= 0 && imageIndex < usedImages.count {
                let img = usedImages[imageIndex]
                imageName = (img["name"] as? String) ?? (img["path"] as? String) ?? "image[\(imageIndex)]"
                if imageName.isEmpty {
                    let path = (img["path"] as? String) ?? ""
                    imageName = path.isEmpty ? "image[\(imageIndex)]" : (path as NSString).lastPathComponent
                }
            }

            let symbolStr = symbol.isEmpty ? "0x\(String(imageOffset, radix: 16))" : "\(symbol) + \(symbolLocation)"
            result.append("\(idx)   \(imageName)   \(symbolStr)")
        }

        return result
    }

    /// Extract termination reason from IPS JSON body.
    private func extractTerminationReason(from content: String) -> String? {
        guard let body = extractIPSBody(from: content) else { return nil }

        if let termination = body["termination"] as? [String: Any] {
            let namespace = termination["namespace"] as? String ?? ""
            let code = termination["code"] as? Int ?? 0
            let indicator = termination["indicator"] as? String ?? ""
            let flags = termination["flags"] as? Int ?? 0

            var parts: [String] = []
            if !namespace.isEmpty { parts.append(namespace) }
            if !indicator.isEmpty { parts.append(indicator) }
            parts.append("code=\(code), flags=\(flags)")

            return parts.joined(separator: " — ")
        }

        // Fallback: check exception block
        if let exception = body["exception"] as? [String: Any] {
            let type = exception["type"] as? String ?? ""
            let signal = exception["signal"] as? String ?? ""
            if !type.isEmpty || !signal.isEmpty {
                return [type, signal].filter { !$0.isEmpty }.joined(separator: " / ")
            }
        }

        return nil
    }

    /// Parse the IPS body (second JSON object in an IPS file).
    private func extractIPSBody(from content: String) -> [String: Any]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }

        // Skip first JSON block (header)
        guard let firstClose = findFirstJSONClose(in: trimmed) else { return nil }
        let bodyStart = trimmed.index(after: firstClose)
        guard bodyStart < trimmed.endIndex else { return nil }

        let bodyStr = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = bodyStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    // MARK: - Jetsam Info Extraction

    struct JetsamInfo {
        let largestProcess: String?
        let pageSize: String?
        let freePages: String?
        let reason: String?
        let killedCount: Int?
    }

    /// Lightweight Jetsam info extraction — scans header only, avoids parsing huge body JSON.
    private func extractJetsamInfo(from content: String) -> JetsamInfo? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }

        // Parse only the header (first JSON block) — it's small and safe
        guard let firstClose = findFirstJSONClose(in: trimmed) else { return nil }
        let headerStr = String(trimmed[trimmed.startIndex...firstClose])
        guard let data = headerStr.data(using: .utf8),
              let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let largestProcess = header["largestProcess"] as? String

        // Scan first 5000 chars of body for key fields (avoid full parse)
        let bodyStart = trimmed.index(after: firstClose)
        guard bodyStart < trimmed.endIndex else { return nil }
        let bodyPreview = String(trimmed[bodyStart...].prefix(5000))

        var pageSize: String?
        var freePages: String?
        var reason: String?

        // Extract pageSize
        if let range = bodyPreview.range(of: #""pageSize"\s*:\s*(\d+)"#, options: .regularExpression) {
            let match = String(bodyPreview[range])
            let num = match.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            if let bytes = Int(num) {
                pageSize = "\(bytes / 1024) KB (\(bytes) bytes)"
            }
        }

        // Extract uncompressed/free pages
        if let range = bodyPreview.range(of: #""pagesFreed"\s*:\s*(\d+)"#, options: .regularExpression) {
            let match = String(bodyPreview[range])
            freePages = match.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
        }

        // Extract reason
        if let range = bodyPreview.range(of: #""reason"\s*:\s*"([^"]+)""#, options: .regularExpression) {
            let match = String(bodyPreview[range])
            if let quoteStart = match.lastIndex(of: "\""), let quoteEnd = match.dropLast().lastIndex(of: "\"") {
                // Just get what we can
            }
            reason = match.components(separatedBy: "\"").dropFirst(3).first
        }

        // Count killed processes (rough estimate from "rpages" occurrences)
        let killedCount = bodyPreview.components(separatedBy: "\"rpages\"").count - 1

        guard largestProcess != nil || pageSize != nil || reason != nil || killedCount > 0 else { return nil }

        return JetsamInfo(
            largestProcess: largestProcess,
            pageSize: pageSize,
            freePages: freePages,
            reason: reason,
            killedCount: killedCount > 0 ? killedCount : nil
        )
    }
}

// MARK: - Supporting Views

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundColor(.gray)
                .padding(.bottom, 2)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct DetailRow: View {
    let key: String
    let value: String
    var valueColor: Color = .white
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(valueColor)
                .multilineTextAlignment(.leading)
            Spacer()
        }
    }
}

struct SeverityBadge: View {
    let log: CrashLog

    private var severityText: String {
        switch log.severityGroup {
        case .noise:
            return "LOW"
        case .system:
            return log.category == .resource ? "RESOURCE" : "SYSTEM"
        case .relevant:
            switch log.crashType.severity {
            case 3: return "CRITICAL"
            case 2: return "HIGH"
            default: return "MEDIUM"
            }
        }
    }

    private var color: Color {
        switch log.severityGroup {
        case .noise:
            return .gray
        case .system:
            return .orange
        case .relevant:
            switch log.crashType.severity {
            case 3: return .red
            case 2: return .orange
            default: return .yellow
            }
        }
    }

    var body: some View {
        Text(severityText)
            .font(.system(size: 9, weight: .black))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
            )
    }
}

struct StackFrameRow: View {
    let index: Int
    let frame: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 24, alignment: .trailing)
            
            Text(frame)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(index < 3 ? .cyan : .green.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

struct MicrostackFrameRow: View {
    let frame: CrashDetailView.MicrostackFrame
    let maxSamples: Int

    private var heatColor: Color {
        let ratio = maxSamples > 0 ? Double(frame.samples) / Double(maxSamples) : 0
        if ratio > 0.8 { return .red }
        if ratio > 0.5 { return .orange }
        if ratio > 0.2 { return .yellow }
        return .green.opacity(0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                // Sample count with heat color
                Text("\(frame.samples)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(heatColor)
                    .frame(width: 24, alignment: .trailing)

                // Heat bar
                GeometryReader { geo in
                    let ratio = maxSamples > 0 ? CGFloat(frame.samples) / CGFloat(maxSamples) : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor.opacity(0.6))
                        .frame(width: max(2, geo.size.width * ratio), height: 10)
                }
                .frame(width: 40, height: 10)

                // Library + offset
                VStack(alignment: .leading, spacing: 0) {
                    Text(frame.library)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Text("+ \(frame.offset)  \(frame.address)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.leading, CGFloat(min(frame.depth, 10)) * 4)
        .padding(.vertical, 1)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
