import Foundation

// MARK: - CrashGrouper
final class CrashGrouper {

    /// Group crashes by process name + crash type + primary exception signature.
    func group(crashes: [CrashLog]) -> [CrashGroup] {
        let grouped = Dictionary(grouping: crashes) { crash -> String in
            groupKey(for: crash)
        }

        return grouped.compactMap { key, logs -> CrashGroup? in
            guard let first = logs.first else { return nil }
            let sorted = logs.sorted { $0.timestamp > $1.timestamp }
            return CrashGroup(
                id: key,
                processName: first.processName,
                crashType: first.crashType,
                primaryException: normalizeException(first.exception),
                crashes: sorted,
                firstSeen: sorted.last?.timestamp ?? Date(),
                lastSeen: sorted.first?.timestamp ?? Date()
            )
        }
        .sorted { $0.count > $1.count }
    }

    /// Group key: processName + crashType + normalized exception prefix.
    private func groupKey(for crash: CrashLog) -> String {
        let process = crash.processName.lowercased()
        let type = crash.crashType.rawValue
        let exception = normalizeException(crash.exception)
        return "\(process)|\(type)|\(exception)"
    }

    /// Normalize exception string for grouping (strip addresses, keep type).
    private func normalizeException(_ exception: String) -> String {
        let trimmed = exception.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "unknown" }

        // Remove hex addresses: 0x00000001234abcd -> <addr>
        var normalized = trimmed
        if let regex = try? NSRegularExpression(pattern: #"0x[0-9a-fA-F]{6,}"#) {
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized),
                withTemplate: "<addr>"
            )
        }

        // Remove PIDs: [1234] -> [pid]
        if let regex = try? NSRegularExpression(pattern: #"\[\d+\]"#) {
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized),
                withTemplate: "[pid]"
            )
        }

        // Truncate to first meaningful portion
        if normalized.count > 80 {
            normalized = String(normalized.prefix(80))
        }

        return normalized
    }
}
