import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var events: [TimelineEvent] = []
    @State private var isLoading = false
    @State private var daysToShow = 14
    @State private var showTweakEvents = true

    private let dpkgManager = DpkgPackageManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                controlsCard
                if isLoading {
                    ProgressView("timeline.building".localized).tint(.cyan).padding(30)
                } else if events.isEmpty {
                    emptyCard
                } else {
                    timelineContent
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("timeline.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { buildTimeline() }
    }

    // MARK: - Header
    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("timeline.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("timeline.headerDesc".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
    }

    private var controlsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("timeline.timeRange".localized)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text("settings.days".localized(daysToShow))
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }
            Slider(value: Binding(
                get: { Double(daysToShow) },
                set: { daysToShow = Int($0); buildTimeline() }
            ), in: 3...90, step: 1)
            .tint(.orange)

            Toggle("timeline.showTweakEvents".localized, isOn: Binding(
                get: { showTweakEvents },
                set: { showTweakEvents = $0; buildTimeline() }
            ))
            .font(.caption)
            .tint(.cyan)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.5))
            Text("timeline.noEvents".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    // MARK: - Timeline Content
    private var timelineContent: some View {
        let grouped = groupByDay(events)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { idx, dayGroup in
                VStack(alignment: .leading, spacing: 0) {
                    // Day header
                    HStack(spacing: 8) {
                        Text(dayGroup.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.bold())
                            .foregroundColor(.white)

                        let crashCount = dayGroup.events.filter { if case .crash = $0.kind { return true }; return false }.count
                        if crashCount > 0 {
                            Text("\(crashCount) crash\(crashCount == 1 ? "" : "es")")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red.opacity(0.15)))
                        }

                        Spacer()

                        let tweakCount = dayGroup.events.filter { if case .tweakInstall = $0.kind { return true }; if case .tweakUpdate = $0.kind { return true }; return false }.count
                        if tweakCount > 0 {
                            Text("\(tweakCount) tweak\(tweakCount == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }
                    }
                    .padding(.vertical, 8)

                    // Events for this day
                    ForEach(dayGroup.events) { event in
                        eventRow(event, isLast: event.id == dayGroup.events.last?.id && idx == grouped.count - 1)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private func eventRow(_ event: TimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline line and dot
            VStack(spacing: 0) {
                Circle()
                    .fill(eventColor(event))
                    .frame(width: 10, height: 10)
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .frame(minHeight: 30)
                }
            }

            // Event content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: eventIcon(event))
                        .font(.caption2)
                        .foregroundColor(eventColor(event))
                    Text(event.title)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospaced())
                        .foregroundColor(.gray)
                }
                Text(event.subtitle)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            .padding(.bottom, 8)
        }
    }

    private func eventColor(_ event: TimelineEvent) -> Color {
        switch event.kind {
        case .crash: return .red
        case .tweakInstall: return .green
        case .tweakUpdate: return .cyan
        case .tweakRemove: return .orange
        }
    }

    private func eventIcon(_ event: TimelineEvent) -> String {
        switch event.kind {
        case .crash: return "exclamationmark.triangle.fill"
        case .tweakInstall: return "plus.circle.fill"
        case .tweakUpdate: return "arrow.up.circle.fill"
        case .tweakRemove: return "minus.circle.fill"
        }
    }

    // MARK: - Build Timeline

    private func buildTimeline() {
        isLoading = true
        let crashes = crashMonitor.indexedCrashLogs
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysToShow, to: Date()) ?? Date.distantPast
        let showTweaks = showTweakEvents

        DispatchQueue.global(qos: .userInitiated).async {
            var allEvents: [TimelineEvent] = []

            // Crash events
            let recentCrashes = crashes.filter { $0.timestamp >= cutoff }
            for crash in recentCrashes {
                allEvents.append(TimelineEvent(
                    date: crash.timestamp,
                    kind: .crash(crash),
                    title: "\(crash.processName) — \(crash.crashType.rawValue)",
                    subtitle: crash.exception.isEmpty ? crash.signal : crash.exception,
                    color: "red"
                ))
            }

            // Tweak events
            if showTweaks {
                let packages = self.dpkgManager.loadInstalledPackages()
                for pkg in packages {
                    guard let installDate = pkg.installedDate, installDate >= cutoff else { continue }
                    guard pkg.isTweak || pkg.section.lowercased().contains("tweak") || !pkg.providedDylibs.isEmpty else { continue }

                    allEvents.append(TimelineEvent(
                        date: installDate,
                        kind: .tweakInstall(pkg),
                        title: "Installed: \(pkg.name)",
                        subtitle: "\(pkg.identifier) v\(pkg.version)",
                        color: "green"
                    ))
                }
            }

            allEvents.sort { $0.date > $1.date }

            DispatchQueue.main.async {
                self.events = allEvents
                self.isLoading = false
            }
        }
    }

    // MARK: - Grouping

    private struct DayGroup {
        let date: Date
        let events: [TimelineEvent]
    }

    private func groupByDay(_ events: [TimelineEvent]) -> [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.date)
        }
        return grouped.map { DayGroup(date: $0.key, events: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}
