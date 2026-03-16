import SwiftUI

struct ExportView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var selectedFormat: ExportFormat = .json
    @State private var exportScope: ExportScope = .visible
    @State private var exportContent: String = ""
    @State private var showShareSheet = false
    @State private var showCopied = false
    @State private var exportFileURL: URL?

    private let exporter = CrashExporter()

    enum ExportScope: String, CaseIterable, Identifiable {
        case visible = "Visible"
        case relevant = "Relevant"
        case all = "All"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .visible: return "export.visibleLogs".localized
            case .relevant: return "export.relevantOnly".localized
            case .all: return "export.allIndexed".localized
            }
        }
    }

    private var logsToExport: [CrashLog] {
        switch exportScope {
        case .visible: return crashMonitor.crashLogs
        case .relevant: return crashMonitor.relevantCrashLogs
        case .all: return crashMonitor.indexedCrashLogs
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                configCard
                previewCard
                actionsCard
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("export.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            } else {
                ShareSheet(items: [exportContent])
            }
        }
        .alert("detail.copied".localized, isPresented: $showCopied) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            Text("export.copied".localized)
        }
    }

    // MARK: - Header
    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("export.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("export.headerDesc".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Config
    private var configCard: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("export.format".localized.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                Picker("export.format".localized, selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("export.scope".localized.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                Picker("export.scope".localized, selection: $exportScope) {
                    ForEach(ExportScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("export.logsToExport".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(logsToExport.count)")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Preview
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("export.preview".localized.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                Spacer()
                Button("export.generate".localized) { generateExport() }
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
            }

            if exportContent.isEmpty {
                Text("export.tapGenerate".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(exportContent.prefix(3000) + (exportContent.count > 3000 ? "\n\n[...truncated preview...]" : ""))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 250)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Actions
    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button(action: {
                generateExport()
                let filename = "SentinelCrash_export_\(dateString()).\(selectedFormat.fileExtension)"
                exportFileURL = exporter.exportToFile(content: exportContent, filename: filename)
                showShareSheet = true
            }) {
                Label("export.share".localized, systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .cornerRadius(10)
            }

            Button(action: {
                generateExport()
                UIPasteboard.general.string = exportContent
                showCopied = true
            }) {
                Label("export.copy".localized, systemImage: "doc.on.doc")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Helpers
    private func generateExport() {
        let logs = logsToExport
        exportContent = exporter.exportBatch(crashes: logs, format: selectedFormat)
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
