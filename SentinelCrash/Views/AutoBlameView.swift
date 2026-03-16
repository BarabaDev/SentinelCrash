import SwiftUI

struct AutoBlameView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var results: [TweakBlameResult] = []
    @State private var isAnalyzing = false
    @State private var selectedCrash: CrashLog?
    @State private var showCrashPicker = false
    @State private var analysisMode: AnalysisMode = .all

    private let blameEngine = AutoBlameEngine()

    enum AnalysisMode: String, CaseIterable, Identifiable {
        case all = "All"
        case single = "Single"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .all: return "blame.allCrashes".localized
            case .single: return "blame.singleCrash".localized
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                modeCard
                if isAnalyzing {
                    ProgressView("blame.analyzing".localized).tint(.cyan).padding(30)
                } else if results.isEmpty && !isAnalyzing {
                    startCard
                } else {
                    resultsSection
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("blame.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCrashPicker) {
            CrashPickerSheet(selected: $selectedCrash, exclude: nil, crashes: crashMonitor.crashLogs)
        }
        .onChange(of: selectedCrash) { _ in
            if analysisMode == .single, selectedCrash != nil { runAnalysis() }
        }
    }

    // MARK: - Components

    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "person.fill.questionmark")
                    .font(.title3)
                    .foregroundColor(.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("blame.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("blame.headerDesc".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    private var modeCard: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $analysisMode) {
                ForEach(AnalysisMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if analysisMode == .single {
                Button(action: { showCrashPicker = true }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        if let crash = selectedCrash {
                            Text("\(crash.processName) — \(crash.crashType.rawValue)")
                                .lineLimit(1)
                        } else {
                            Text("blame.selectCrash".localized)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.2), lineWidth: 1)))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var startCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36))
                .foregroundColor(.cyan.opacity(0.5))
            Text(analysisMode == .single ? "Select a crash above, then run analysis" : "blame.analyzeAll".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Button(action: runAnalysis) {
                Label("blame.run".localized, systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan)
                    .cornerRadius(10)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("blame.results".localized, systemImage: "person.fill.checkmark")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
                Button(action: runAnalysis) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
            }

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("blame.noSuspects".localized)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("blame.noSuspectsDesc".localized)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(results) { result in
                    blameCard(result)
                }
            }
        }
    }

    private func blameCard(_ result: TweakBlameResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: result.confidence.icon)
                    .foregroundColor(confidenceColor(result.confidence))
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.tweakName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(result.packageID)
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }
                Spacer()
                confidenceBadge(result.confidence)
            }

            // Score bar
            HStack(spacing: 8) {
                Text("blame.score".localized)
                    .font(.caption2)
                    .foregroundColor(.gray)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(confidenceGradient(result.confidence))
                            .frame(width: geo.size.width * result.score)
                    }
                }
                .frame(height: 6)
                Text(String(format: "%.0f%%", result.score * 100))
                    .font(.caption2.bold().monospaced())
                    .foregroundColor(confidenceColor(result.confidence))
                    .frame(width: 32)
            }

            Text(result.reason)
                .font(.caption)
                .foregroundColor(.orange.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            if !result.dylibPaths.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text(result.dylibPaths.joined(separator: ", "))
                        .font(.caption2.monospaced())
                        .foregroundColor(.purple.opacity(0.7))
                        .lineLimit(2)
                }
            }

            HStack {
                Text("blame.involvedIn".localized(result.involvedCrashes.count))
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 14).stroke(confidenceColor(result.confidence).opacity(0.2), lineWidth: 1)))
    }

    private func confidenceBadge(_ confidence: TweakBlameResult.BlameConfidence) -> some View {
        let color = confidenceColor(confidence)
        return Text(confidence.displayName.uppercased())
            .font(.system(size: 9, weight: .black))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)).overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5)))
    }

    private func confidenceColor(_ c: TweakBlameResult.BlameConfidence) -> Color {
        switch c {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }

    private func confidenceGradient(_ c: TweakBlameResult.BlameConfidence) -> LinearGradient {
        let color = confidenceColor(c)
        return LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Actions

    private func runAnalysis() {
        isAnalyzing = true
        let allCrashes = crashMonitor.indexedCrashLogs
        let target = analysisMode == .single ? selectedCrash : nil

        DispatchQueue.global(qos: .userInitiated).async {
            var blameResults: [TweakBlameResult] = []

            if let target {
                blameResults = blameEngine.blame(crash: target, allCrashes: allCrashes)
            } else {
                // Aggregate blame across recent crashes
                var seen = Set<String>()
                let recentCrashes = Array(allCrashes.prefix(50))
                for crash in recentCrashes {
                    let crashBlames = blameEngine.blame(crash: crash, allCrashes: allCrashes)
                    for blame in crashBlames where !seen.contains(blame.packageID) {
                        seen.insert(blame.packageID)
                        blameResults.append(blame)
                    }
                }
                blameResults.sort { $0.score > $1.score }
            }

            DispatchQueue.main.async {
                self.results = blameResults
                self.isAnalyzing = false
            }
        }
    }
}
