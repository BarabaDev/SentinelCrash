import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var scope: CrashVisibilityScope = .relevant

    private var sourceLogs: [CrashLog] {
        crashMonitor.logs(for: scope)
    }

    private var last7DaysData: [(String, Int)] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<7).reversed().map { dayOffset -> (String, Int) in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) else {
                return ("?", 0)
            }
            let dayStart = calendar.startOfDay(for: date)
            let count = sourceLogs.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }.count
            let label = dayOffset == 0 ? "analytics.today".localized : calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return (label, count)
        }
    }

    private var topProcesses: [(String, Int)] {
        let grouped = Dictionary(grouping: sourceLogs, by: { $0.processName })
        return grouped.map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }.prefix(10).map { $0 }
    }

    private var crashTypeCounts: [(CrashType, Int)] {
        Dictionary(grouping: sourceLogs, by: { $0.crashType }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("analytics.scope".localized, selection: $scope) {
                        ForEach([CrashVisibilityScope.visible, .relevant, .system, .noise]) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    summaryCard
                    chartCard
                    topProcessesCard
                    typeDistributionCard
                    hourlyHeatmapCard
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("analytics.title".localized)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("analytics.scope".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(scope.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Spacer()
            Text("\(sourceLogs.count) logs")
                .font(.subheadline.bold())
                .foregroundColor(.cyan)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("analytics.last7Days".localized, systemImage: "chart.bar.fill").font(.headline).foregroundColor(.cyan)
            let maxVal = max(last7DaysData.map { $0.1 }.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7DaysData, id: \.0) { label, count in
                    VStack(spacing: 4) {
                        if count > 0 { Text("\(count)").font(.system(size: 9, weight: .bold)).foregroundColor(.white) }
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barGradient(count: count, max: maxVal))
                                    .frame(height: max(4, geo.size.height * CGFloat(count) / CGFloat(maxVal)))
                            }
                        }
                        Text(label).font(.system(size: 9)).foregroundColor(.gray).frame(width: 32)
                    }
                }
            }
            .frame(height: 120)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.2), lineWidth: 1)))
    }

    private func barGradient(count: Int, max: Int) -> LinearGradient {
        let intensity = max > 0 ? Double(count) / Double(max) : 0
        let startColor: Color = intensity > 0.7 ? .red : intensity > 0.4 ? .orange : .cyan
        return LinearGradient(colors: [startColor, startColor.opacity(0.5)], startPoint: .top, endPoint: .bottom)
    }

    private var topProcessesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("analytics.topOffenders".localized, systemImage: "app.badge.fill").font(.headline).foregroundColor(.red)
            if topProcesses.isEmpty {
                Text("analytics.noCrashData".localized).foregroundColor(.gray).font(.caption)
            } else {
                let maxCount = topProcesses.first?.1 ?? 1
                ForEach(Array(topProcesses.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: 10) {
                        Text("#\(idx + 1)").font(.caption.monospaced()).foregroundColor(.gray).frame(width: 24)
                        Text(item.0).font(.caption.monospaced()).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                                RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.7)).frame(width: geo.size.width * CGFloat(item.1) / CGFloat(maxCount))
                            }
                        }.frame(width: 60, height: 8)
                        Text("\(item.1)").font(.caption.bold()).foregroundColor(.red).frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    private var typeDistributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("analytics.crashDistribution".localized, systemImage: "chart.pie.fill").font(.headline).foregroundColor(.purple)
            if crashTypeCounts.isEmpty {
                Text("analytics.noCrashData".localized).foregroundColor(.gray).font(.caption)
            } else {
                ForEach(crashTypeCounts, id: \.0) { type, count in
                    HStack {
                        Text(type.rawValue).foregroundColor(.white).font(.caption.monospaced())
                        Spacer()
                        Text("\(count)").foregroundColor(typeColor(type)).font(.caption.bold())
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1)))
    }

    private var hourlyHeatmapCard: some View {
        let grouped = Dictionary(grouping: sourceLogs, by: { Calendar.current.component(.hour, from: $0.timestamp) })
        return VStack(alignment: .leading, spacing: 12) {
            Label("analytics.hourlyActivity".localized, systemImage: "clock.fill").font(.headline).foregroundColor(.orange)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = grouped[hour]?.count ?? 0
                    VStack(spacing: 4) {
                        Text("\(hour)").font(.system(size: 9)).foregroundColor(.gray)
                        RoundedRectangle(cornerRadius: 6).fill(count == 0 ? Color.white.opacity(0.05) : Color.orange.opacity(min(0.2 + Double(count) * 0.15, 1))).frame(height: 24)
                        Text("\(count)").font(.system(size: 8)).foregroundColor(.white.opacity(count == 0 ? 0.3 : 0.9))
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
    }

    private func typeColor(_ type: CrashType) -> Color {
        switch type.color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "cyan": return .cyan
        default: return .gray
        }
    }
}
