import SwiftUI

struct CrashDiffView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var leftLog: CrashLog?
    @State private var rightLog: CrashLog?
    @State private var showLeftPicker = false
    @State private var showRightPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                // Pickers
                HStack(spacing: 12) {
                    pickerButton(label: "diff.left".localized, log: leftLog, action: { showLeftPicker = true }, color: .cyan)
                    pickerButton(label: "diff.right".localized, log: rightLog, action: { showRightPicker = true }, color: .orange)
                }

                if let left = leftLog, let right = rightLog {
                    diffContent(left: left, right: right)
                } else {
                    hintCard
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("diff.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showLeftPicker) {
            CrashPickerSheet(selected: $leftLog, exclude: rightLog, crashes: crashMonitor.crashLogs)
        }
        .sheet(isPresented: $showRightPicker) {
            CrashPickerSheet(selected: $rightLog, exclude: leftLog, crashes: crashMonitor.crashLogs)
        }
    }

    // MARK: - Components

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.left.and.right")
                .font(.title2)
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("diff.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("diff.headerDesc".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1)))
    }

    private func pickerButton(label: String, log: CrashLog?, action: @escaping () -> Void, color: Color) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(color)
                if let log {
                    Text(log.processName)
                        .font(.caption.monospaced())
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("diff.selectCrash".localized)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.3), lineWidth: 1)))
        }
    }

    private var hintCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.5))
            Text("diff.selectTwo".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Diff Content

    private func diffContent(left: CrashLog, right: CrashLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            diffSection(title: "detail.processInfo".localized) {
                diffRow(key: "detail.process".localized, left: left.processName, right: right.processName)
                diffRow(key: "detail.bundleID".localized, left: left.bundleID, right: right.bundleID)
                diffRow(key: "iOS", left: left.osVersion, right: right.osVersion)
                diffRow(key: "detail.device".localized, left: left.deviceModel, right: right.deviceModel)
            }

            diffSection(title: "detail.crashInfo".localized) {
                diffRow(key: "detail.type".localized, left: left.crashType.rawValue, right: right.crashType.rawValue)
                diffRow(key: "detail.signal".localized, left: left.signal, right: right.signal)
                diffRow(key: "detail.exception".localized, left: left.exception, right: right.exception)
                diffRow(key: "diff.category".localized, left: left.category.displayName, right: right.category.displayName)
                diffRow(key: "diff.severity".localized, left: left.severityGroup.displayName, right: right.severityGroup.displayName)
                diffRow(key: "diff.jbRelated".localized, left: left.isJailbreakRelevant ? "diff.yes".localized : "diff.no".localized, right: right.isJailbreakRelevant ? "diff.yes".localized : "diff.no".localized)
            }

            diffSection(title: "diff.timestamps".localized) {
                diffRow(key: "detail.time".localized, left: left.timestamp.formatted(date: .abbreviated, time: .standard), right: right.timestamp.formatted(date: .abbreviated, time: .standard))
                let interval = abs(left.timestamp.timeIntervalSince(right.timestamp))
                let intervalStr = formatInterval(interval)
                HStack {
                    Text("diff.timeDelta".localized)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text(intervalStr)
                        .font(.caption.monospaced().bold())
                        .foregroundColor(.purple)
                    Spacer()
                }
            }

            // Stack trace diff
            stackTraceDiff(left: left, right: right)
        }
    }

    private func diffSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .textCase(.uppercase)
                .foregroundColor(.gray)
            content()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func diffRow(key: String, left: String, right: String) -> some View {
        let same = left.lowercased() == right.lowercased()
        let leftDisplay = left.isEmpty ? "—" : left
        let rightDisplay = right.isEmpty ? "—" : right

        return VStack(spacing: 4) {
            HStack {
                Text(key)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 70, alignment: .leading)
                Spacer()
                if same {
                    Image(systemName: "equal")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Text(leftDisplay)
                    .font(.caption2.monospaced())
                    .foregroundColor(same ? .white : .cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                Divider().frame(height: 16).background(Color.white.opacity(0.1))
                Text(rightDisplay)
                    .font(.caption2.monospaced())
                    .foregroundColor(same ? .white : .orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
    }

    private func stackTraceDiff(left: CrashLog, right: CrashLog) -> some View {
        let leftFrames = extractFrames(from: left.rawContent)
        let rightFrames = extractFrames(from: right.rawContent)
        let maxCount = max(leftFrames.count, rightFrames.count)

        return VStack(alignment: .leading, spacing: 8) {
            Text("diff.stackComparison".localized)
                .font(.caption.bold())
                .textCase(.uppercase)
                .foregroundColor(.gray)

            if maxCount == 0 {
                Text("diff.noStackTraces".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                HStack {
                    Text("diff.leftFrames".localized(leftFrames.count))
                        .font(.caption2)
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("diff.rightFrames".localized(rightFrames.count))
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                ForEach(0..<min(maxCount, 20), id: \.self) { idx in
                    let leftFrame = idx < leftFrames.count ? leftFrames[idx] : "—"
                    let rightFrame = idx < rightFrames.count ? rightFrames[idx] : "—"
                    let same = extractLibName(leftFrame) == extractLibName(rightFrame)

                    HStack(alignment: .top, spacing: 4) {
                        Text("#\(idx)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(leftFrame)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(same ? .white.opacity(0.6) : .cyan)
                                .lineLimit(1)
                            Text(rightFrame)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(same ? .white.opacity(0.6) : .orange)
                                .lineLimit(1)
                        }

                        Spacer()

                        if !same {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 2)
                    .background(same ? Color.clear : Color.red.opacity(0.05))
                }

                if maxCount > 20 {
                    Text("… \(maxCount - 20) more frames")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Helpers

    private func extractFrames(from content: String) -> [String] {
        var frames: [String] = []
        var inCrashedThread = false
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("Thread") && t.contains("Crashed") { inCrashedThread = true; continue }
            if inCrashedThread && t.hasPrefix("Thread ") && !t.contains("Crashed") { break }
            if t.hasPrefix("Binary Images:") { break }
            if inCrashedThread && t.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                frames.append(t)
            }
        }
        if frames.isEmpty {
            for line in content.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.range(of: #"^\d+\s+"#, options: .regularExpression) != nil {
                    frames.append(t)
                }
            }
        }
        return frames
    }

    private func extractLibName(_ frame: String) -> String {
        let parts = frame.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.count >= 2 ? parts[1] : frame
    }

    private func formatInterval(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h \(Int((seconds / 60).truncatingRemainder(dividingBy: 60)))m" }
        return "\(Int(seconds / 86400))d"
    }
}

// MARK: - Crash Picker Sheet

struct CrashPickerSheet: View {
    @Binding var selected: CrashLog?
    let exclude: CrashLog?
    let crashes: [CrashLog]
    @Environment(\.dismiss) var dismiss
    @State private var search = ""

    private var filtered: [CrashLog] {
        let base = crashes.filter { $0.id != exclude?.id }
        if search.isEmpty { return base }
        return base.filter {
            $0.processName.localizedCaseInsensitiveContains(search) ||
            $0.crashType.rawValue.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationView {
            List(filtered) { crash in
                Button(action: {
                    selected = crash
                    dismiss()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: crash.crashType.icon)
                            .foregroundColor(.cyan)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(crash.processName)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("\(crash.crashType.rawValue) · \(crash.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if crash.id == selected?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.cyan)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "crashlist.search".localized)
            .navigationTitle("diff.selectCrash".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.cancel".localized) { dismiss() }
                }
            }
        }
    }
}
