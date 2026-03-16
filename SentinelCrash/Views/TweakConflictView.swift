import SwiftUI

struct TweakConflictView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var analysisResult: TweakConflictDetector.AnalysisResult?
    @State private var isAnalyzing = false
    @State private var selectedConflict: TweakConflictReport?

    private let detector = TweakConflictDetector()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if isAnalyzing {
                    ProgressView("tweak.analyzing".localized)
                        .tint(.cyan)
                        .padding(40)
                } else if let result = analysisResult {
                    summaryCard(result)
                    if result.conflicts.isEmpty {
                        noConflictsCard
                    } else {
                        conflictList(result.conflicts)
                    }
                } else {
                    startCard
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("conflict.title".localized)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Header
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("conflict.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("conflict.headerDesc".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Start Card
    private var startCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.cyan.opacity(0.6))
            Text("conflict.runAnalysisDesc".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            runButton
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var runButton: some View {
        Button(action: runAnalysis) {
            Label("conflict.runAnalysis".localized, systemImage: "play.fill")
                .font(.subheadline.bold())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.cyan)
                .cornerRadius(10)
        }
    }

    // MARK: - Summary
    private func summaryCard(_ result: TweakConflictDetector.AnalysisResult) -> some View {
        VStack(spacing: 12) {
            HStack {
                summaryPill(title: "tweak.packages".localized, value: "\(result.packages.count)", color: .cyan)
                summaryPill(title: "tweak.conflicts".localized, value: "\(result.conflicts.count)", color: result.conflicts.isEmpty ? .green : .red)
                summaryPill(title: "tweak.analyzed".localized, value: "\(result.totalCrashesAnalyzed)", color: .orange)
            }
            runButton
        }
    }

    private func summaryPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundColor(color)
            Text(title).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    // MARK: - No Conflicts
    private var noConflictsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("conflict.noConflicts".localized)
                .font(.headline)
                .foregroundColor(.white)
            Text("conflict.noConflictsDesc".localized)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Conflict List
    private func conflictList(_ conflicts: [TweakConflictReport]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("conflict.rankedByDanger".localized, systemImage: "flame.fill")
                .font(.headline)
                .foregroundColor(.orange)

            ForEach(Array(conflicts.enumerated()), id: \.offset) { idx, conflict in
                conflictRow(rank: idx + 1, conflict: conflict)
            }
        }
    }

    private func conflictRow(rank: Int, conflict: TweakConflictReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("#\(rank)")
                    .font(.caption.bold().monospaced())
                    .foregroundColor(.gray)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.tweakName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(conflict.packageID)
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }

                Spacer()

                dangerBadge(score: conflict.dangerScore)
            }

            HStack(spacing: 16) {
                Label("\(conflict.crashCount) crashes", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Label("\(conflict.affectedProcesses.count) processes", systemImage: "app.badge")
                    .font(.caption2)
                    .foregroundColor(.cyan)
                Label("\(conflict.dylibsLoaded.count) dylibs", systemImage: "link")
                    .font(.caption2)
                    .foregroundColor(.purple)
            }

            // Danger bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(dangerGradient(score: conflict.dangerScore))
                        .frame(width: geo.size.width * conflict.dangerScore)
                }
            }
            .frame(height: 6)

            if !conflict.affectedProcesses.isEmpty {
                Text("tweak.affected".localized(conflict.affectedProcesses.prefix(5).joined(separator: ", ")))
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 14).stroke(dangerBorderColor(score: conflict.dangerScore).opacity(0.3), lineWidth: 1)))
    }

    private func dangerBadge(score: Double) -> some View {
        let label: String
        let color: Color
        if score >= 0.7 { label = "DANGER"; color = .red }
        else if score >= 0.4 { label = "WARN"; color = .orange }
        else { label = "LOW"; color = .yellow }

        return Text(label)
            .font(.system(size: 9, weight: .black))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)).overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5)))
    }

    private func dangerGradient(score: Double) -> LinearGradient {
        let color: Color = score >= 0.7 ? .red : score >= 0.4 ? .orange : .yellow
        return LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
    }

    private func dangerBorderColor(score: Double) -> Color {
        score >= 0.7 ? .red : score >= 0.4 ? .orange : .yellow
    }

    // MARK: - Actions
    private func runAnalysis() {
        isAnalyzing = true
        let crashes = crashMonitor.indexedCrashLogs
        DispatchQueue.global(qos: .userInitiated).async {
            let result = detector.analyze(crashes: crashes)
            DispatchQueue.main.async {
                self.analysisResult = result
                self.isAnalyzing = false
            }
        }
    }
}
