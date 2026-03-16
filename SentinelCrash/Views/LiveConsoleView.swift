import SwiftUI
import Combine

struct LiveConsoleView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var consoleLines: [ConsoleLine] = []
    @State private var isLive = true
    @State private var autoScroll = true
    @State private var showOnlyNew = false
    @State private var previousCrashCount = 0
    @State private var timer: Timer?
    @State private var scrollProxy: ScrollViewProxy?

    private let maxLines = 200

    struct ConsoleLine: Identifiable {
        let id = UUID()
        let timestamp: Date
        let text: String
        let kind: LineKind
        let crashLog: CrashLog?

        enum LineKind {
            case info, crash, warning, system
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            controlsBar

            // Console output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(consoleLines) { line in
                            consoleLineView(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .background(Color(white: 0.05))
                .onChange(of: consoleLines.count) { _ in
                    if autoScroll, let last = consoleLines.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear { scrollProxy = proxy }
            }

            // Status bar
            statusBar
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("console.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startConsole() }
        .onDisappear { stopConsole() }
    }

    // MARK: - Controls Bar
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button(action: { isLive.toggle(); isLive ? startConsole() : stopConsole() }) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isLive ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isLive ? "dashboard.live".localized : "console.paused".localized)
                        .font(.caption.bold().monospaced())
                        .foregroundColor(isLive ? .red : .gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(isLive ? Color.red.opacity(0.15) : Color.white.opacity(0.08)))
            }

            Toggle("console.autoScroll".localized, isOn: $autoScroll)
                .font(.caption2)
                .tint(.cyan)
                .fixedSize()

            Spacer()

            Button(action: clearConsole) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Text("\(consoleLines.count)/\(maxLines)")
                .font(.caption2.monospaced())
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Console Line View
    private func consoleLineView(_ line: ConsoleLine) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(line.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray.opacity(0.6))
                .frame(width: 62, alignment: .leading)

            Text(linePrefix(line.kind))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(lineColor(line.kind))
                .frame(width: 38, alignment: .leading)

            if let crash = line.crashLog {
                NavigationLink(destination: CrashDetailView(log: crash)) {
                    Text(line.text)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(lineColor(line.kind))
                        .lineLimit(3)
                }
            } else {
                Text(line.text)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(lineColor(line.kind))
                    .lineLimit(3)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func linePrefix(_ kind: ConsoleLine.LineKind) -> String {
        switch kind {
        case .info: return "[INFO]"
        case .crash: return "[CRASH]"
        case .warning: return "[WARN]"
        case .system: return "[SYS]"
        }
    }

    private func lineColor(_ kind: ConsoleLine.LineKind) -> Color {
        switch kind {
        case .info: return .green.opacity(0.8)
        case .crash: return .red
        case .warning: return .orange
        case .system: return .cyan
        }
    }

    // MARK: - Status Bar
    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: crashMonitor.isMonitoring ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .font(.caption2)
                .foregroundColor(crashMonitor.isMonitoring ? .green : .red)

            Text(crashMonitor.isMonitoring ? "console.monitorActive".localized : "console.paused".localized)
                .font(.caption2)
                .foregroundColor(.gray)

            Spacer()

            if crashMonitor.isScanning {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5)
                    Text("console.scanInProgress".localized)
                        .font(.caption2)
                        .foregroundColor(.cyan)
                }
            }

            Text("console.indexed".localized + " \(crashMonitor.indexedCrashCount)")
                .font(.caption2.monospaced())
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
    }

    // MARK: - Console Logic

    private func startConsole() {
        isLive = true
        previousCrashCount = crashMonitor.crashLogs.count

        appendLine("console.started".localized, kind: .system)
        let monitorMsg = "console.monitoring".localized + " \(crashMonitor.existingMonitoredPaths.count) " + "console.activePaths".localized
        appendLine(monitorMsg, kind: .info)

        if let jb = crashMonitor.jailbreakEnvironment {
            appendLine("JB: \(jb.jailbreakName) — rootless: \(jb.isRootless)", kind: .info)
        }

        let indexMsg = "console.indexed".localized + " \(crashMonitor.indexedCrashCount) | " + "dashboard.visibleShort".localized + ": \(crashMonitor.crashLogs.count)"
        appendLine(indexMsg, kind: .info)
        appendLine("console.waiting".localized, kind: .system)

        // Poll for new crashes
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak crashMonitor] _ in
            Task { @MainActor in
                guard let monitor = crashMonitor else { return }
                let currentCount = monitor.crashLogs.count
                if currentCount > previousCrashCount {
                    let newLogs = Array(monitor.crashLogs.prefix(currentCount - previousCrashCount))
                    for log in newLogs {
                        appendLine("\(log.processName) — \(log.crashType.rawValue) — \(log.signal.isEmpty ? log.exception : log.signal)", kind: .crash, crashLog: log)

                        if log.isJailbreakRelevant {
                            appendLine("  ⚠ Jailbreak-relevant crash detected!", kind: .warning)
                        }
                        if log.crashType.severity >= 3 {
                            appendLine("  ⚠ CRITICAL severity: \(log.crashType.rawValue)", kind: .warning)
                        }
                    }
                    previousCrashCount = currentCount
                }

                if monitor.isScanning {
                    appendLine("Scan in progress…", kind: .system)
                }
            }
        }
    }

    private func stopConsole() {
        isLive = false
        timer?.invalidate()
        timer = nil
        appendLine("console.paused".localized, kind: .system)
    }

    private func clearConsole() {
        consoleLines.removeAll()
        appendLine("console.cleared".localized, kind: .system)
    }

    private func appendLine(_ text: String, kind: ConsoleLine.LineKind, crashLog: CrashLog? = nil) {
        let line = ConsoleLine(timestamp: Date(), text: text, kind: kind, crashLog: crashLog)
        consoleLines.append(line)
        if consoleLines.count > maxLines {
            consoleLines.removeFirst(consoleLines.count - maxLines)
        }
    }
}
