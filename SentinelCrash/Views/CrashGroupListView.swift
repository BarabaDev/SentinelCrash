import SwiftUI

struct CrashGroupListView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var groups: [CrashGroup] = []
    @State private var expandedGroupID: String?

    private let grouper = CrashGrouper()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard

                if groups.isEmpty {
                    emptyCard
                } else {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("groups.title".localized)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { regroup() }
        .onChange(of: crashMonitor.crashLogs.count) { _ in regroup() }
    }

    private var groupSummaryText: String {
        "\(groups.count) " + "groups.groupsFrom".localized + " \(crashMonitor.crashLogs.count) " + "groups.crashes".localized
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("groups.header".localized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(groupSummaryText)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "rectangle.stack.fill")
                .font(.title2)
                .foregroundColor(.purple)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1)))
    }

    private var emptyCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.5))
            Text("groups.noGroups".localized)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private func groupCard(_ group: CrashGroup) -> some View {
        let isExpanded = expandedGroupID == group.id
        let color = typeColor(group.crashType)

        return VStack(alignment: .leading, spacing: 0) {
            groupCardHeader(group: group, isExpanded: isExpanded, color: color)

            if isExpanded {
                Divider().background(Color.white.opacity(0.1))
                groupCardBody(group: group)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
        )
    }

    private func groupCardHeader(group: CrashGroup, isExpanded: Bool, color: Color) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedGroupID = isExpanded ? nil : group.id
            }
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: group.crashType.icon)
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(group.processName)
                            .font(.subheadline.bold().monospaced())
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("×\(group.count)")
                            .font(.title3.bold())
                            .foregroundColor(color)
                    }

                    HStack(spacing: 8) {
                        Text(group.crashType.rawValue)
                            .font(.caption2.monospaced())
                            .foregroundColor(color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(color.opacity(0.12)))

                        trendBadge(group.trend)

                        Spacer()
                    }

                    Text("\(group.firstSeen.formatted(date: .abbreviated, time: .omitted)) — \(group.lastSeen.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
        }
    }

    private func groupCardBody(group: CrashGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("groups.exception".localized + " \(group.primaryException)")
                .font(.caption.monospaced())
                .foregroundColor(.orange)
                .lineLimit(2)
                .padding(.bottom, 4)

            ForEach(Array(group.crashes.prefix(10))) { crash in
                NavigationLink(destination: CrashDetailView(log: crash)) {
                    groupCrashRow(crash: crash)
                }
            }

            if group.count > 10 {
                Text("+ \(group.count - 10) more")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
        }
        .padding()
    }

    private func groupCrashRow(crash: CrashLog) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(crash.isRead ? Color.gray.opacity(0.3) : Color.cyan)
                .frame(width: 6, height: 6)
            Text(crash.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospaced())
                .foregroundColor(.white)
            Spacer()
            Text(crash.signal.isEmpty ? String(crash.exception.prefix(20)) : crash.signal)
                .font(.caption2.monospaced())
                .foregroundColor(.gray)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.vertical, 4)
    }

    private func trendBadge(_ trend: CrashGroup.GroupTrend) -> some View {
        let color: Color = trend == .increasing ? .red : trend == .decreasing ? .green : .gray
        return HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.system(size: 8))
            Text(trend.displayName)
                .font(.system(size: 9))
        }
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
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

    private func regroup() {
        groups = grouper.group(crashes: crashMonitor.crashLogs)
    }
}
