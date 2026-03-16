import SwiftUI

// MARK: - Jailbreak Info View
struct JailbreakInfoView: View {
    @EnvironmentObject var crashMonitor: CrashMonitorService
    @State private var diagResult = ""
    @State private var isDiagnosing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let env = crashMonitor.jailbreakEnvironment {
                        jailbreakDetectedCard(env)
                        fileSystemCard
                        installedToolsCard(env)
                    } else {
                        noJailbreakCard
                    }
                    diagnosticsCard
                    monitoredPathsCard
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("jbinfo.title".localized)
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func jailbreakDetectedCard(_ env: JailbreakEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.open.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                Text(env.jailbreakName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Spacer()
                StatusPill(text: "jbinfo.detected".localized, color: .green)
            }

            Divider().background(Color.white.opacity(0.1))

            VStack(spacing: 10) {
                InfoRow(icon: "folder.fill", label: "jb.root".localized, value: env.jbRoot, color: .yellow)
                InfoRow(icon: "cpu", label: "jb.mode".localized, value: "Rootless (/var/jb)", color: .cyan)
                InfoRow(icon: "checkmark.seal.fill", label: "jb.bootstrap".localized, value: env.procursusStrapped ? "Procursus ✓" : "common.unknown".localized, color: .orange)
                InfoRow(icon: "shippingbox.fill", label: "jbinfo.bootstrapPath".localized, value: env.bootstrapPath, color: .purple)
                InfoRow(icon: "iphone", label: "jbinfo.deviceiOS".localized, value: env.deviceIOSVersion, color: .white)
                InfoRow(icon: "arrow.left.and.right", label: "jbinfo.supportediOS".localized, value: env.supportedIOSMax == "?" ? "\(env.supportedIOSMin)+" : "iOS \(env.supportedIOSMin) – \(env.supportedIOSMax)", color: .cyan)
            }

            // iOS compatibility badge
            if env.isIOSInRange {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("jb.inRange".localized(env.deviceIOSVersion, env.jailbreakName))
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("jb.outOfRange".localized(env.deviceIOSVersion, env.jailbreakName, env.supportedIOSMin, env.supportedIOSMax))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.green.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.3), lineWidth: 1))
        )
    }

    private var fileSystemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("jbinfo.keyPaths".localized, systemImage: "folder.badge.gearshape")
                .font(.headline)
                .foregroundColor(.yellow)

            let paths: [(String, String)] = [
                // JB Core
                ("JB Root", "/var/jb"),
                ("Bootstrap", "/var/jb/usr"),
                ("Procursus", "/var/jb/.procursus_strapped"),
                ("Dopamine", "/var/jb/.installed_dopamine"),
                ("NathanLR", "/var/jb/.installed_nathanlr"),
                ("palera1n", "/var/jb/.installed_palera1n"),
                // Verified crash log paths
                ("jbinfo.crashLogs".localized, "/var/mobile/Library/Logs/CrashReporter"),
                ("jbinfo.panics".localized, "/var/mobile/Library/Logs/CrashReporter/Panics"),
                ("jbinfo.diagnosticReports".localized, "/var/db/diagnostics"),
                ("DiagnosticPipeline", "/var/mobile/Library/Logs/DiagnosticPipeline"),
                ("AppleSupport", "/private/var/logs/AppleSupport"),
                ("Root Logs", "/private/var/root/Library/Logs"),
                // JB paths
                ("JB Logs", "/var/jb/var/log"),
                ("JB Libexec", "/var/jb/usr/libexec"),
                ("JB Lib", "/var/jb/usr/lib"),
                ("JB Config", "/var/jb/etc"),
                ("JB Preferences", "/var/jb/var/mobile/Library/Preferences"),
                // Tools
                ("Tweaks", "/var/jb/Library/MobileSubstrate/DynamicLibraries"),
                ("ElleKit", "/var/jb/usr/lib/ellekit.dylib"),
                ("dpkg status", "/var/jb/var/lib/dpkg/status"),
                ("dpkg (Sileo)", "/var/jb/Library/dpkg/status"),
            ]

            ForEach(paths, id: \.0) { label, path in
                HStack(alignment: .top) {
                    let exists = FileManager.default.fileExists(atPath: path)
                    Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(exists ? .green : .red)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(exists ? .yellow : .red.opacity(0.7))
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
        )
    }

    private func installedToolsCard(_ env: JailbreakEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("jbinfo.installedTools".localized, systemImage: "wrench.and.screwdriver.fill")
                .font(.headline)
                .foregroundColor(.purple)

            if env.installedJBTools.isEmpty {
                Text("jb.noTools".localized)
                    .foregroundColor(.gray)
                    .font(.caption)
            } else {
                FlowLayout(env.installedJBTools)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.2), lineWidth: 1))
        )
    }

    private var noJailbreakCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.7))
            Text("dashboard.noJB".localized)
                .font(.title2.bold())
                .foregroundColor(.white)
            Text("jb.noJBDesc".localized)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .font(.caption)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.3), lineWidth: 1))
        )
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("jbinfo.systemDiag".localized, systemImage: "stethoscope")
                .font(.headline)
                .foregroundColor(.cyan)

            if isDiagnosing {
                ProgressView("jb.running".localized)
                    .tint(.cyan)
            } else if !diagResult.isEmpty {
                Text(diagResult)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.green)
            }

            Button(action: runDiagnostics) {
                Label("jbinfo.runDiag".localized, systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
        )
    }

    private var monitoredPathsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("settings.monitoredPaths".localized, systemImage: "eye.fill")
                .font(.headline)
                .foregroundColor(.orange)

            ForEach(crashMonitor.monitoredPaths, id: \.self) { path in
                let exists = FileManager.default.fileExists(atPath: path)
                HStack {
                    Image(systemName: exists ? "eye.fill" : "eye.slash")
                        .foregroundColor(exists ? .green : .gray.opacity(0.4))
                        .font(.caption)
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(exists ? .white : .gray.opacity(0.5))
                    Spacer()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        )
    }

    private func runDiagnostics() {
        isDiagnosing = true
        diagResult = ""

        let activePathCount = crashMonitor.existingMonitoredPaths.count
        let totalPathCount = crashMonitor.monitoredPaths.count
        let visibleCount = crashMonitor.crashLogs.count
        let indexedCount = crashMonitor.indexedCrashCount
        let hiddenCount = crashMonitor.hiddenCrashCount
        let jbEnv = crashMonitor.jailbreakEnvironment

        DispatchQueue.global().async {
            let fm = FileManager.default
            var result = "=== SentinelCrash v1.1.0 Diagnostics ===\n"

            // iOS & JB info
            if let env = jbEnv {
                result += "\nJailbreak: \(env.jailbreakName)\n"
                result += "Device iOS: \(env.deviceIOSVersion)\n"
                let rangeStr = env.supportedIOSMax == "?" ? "\(env.supportedIOSMin)+" : "\(env.supportedIOSMin) – \(env.supportedIOSMax)"
                result += "Supported iOS: \(rangeStr)\n"
                result += "In range: \(env.isIOSInRange ? "✓ Yes" : "⚠ No")\n"
                result += "Mode: \("Rootless")\n"
            }

            result += "\n--- File System Checks ---\n"

            let checks: [(String, String)] = [
                // JB Core
                ("/var/jb exists", "/var/jb"),
                ("Procursus strapped", "/var/jb/.procursus_strapped"),
                ("Dopamine installed", "/var/jb/.installed_dopamine"),
                ("NathanLR installed", "/var/jb/.installed_nathanlr"),
                ("palera1n installed", "/var/jb/.installed_palera1n"),
                // Verified log paths
                ("CrashReporter dir", "/var/mobile/Library/Logs/CrashReporter"),
                ("Panics dir", "/var/mobile/Library/Logs/CrashReporter/Panics"),
                ("Diagnostics DB", "/var/db/diagnostics"),
                ("DiagnosticPipeline", "/var/mobile/Library/Logs/DiagnosticPipeline"),
                ("AppleSupport logs", "/private/var/logs/AppleSupport"),
                ("Root logs", "/private/var/root/Library/Logs"),
                // JB log paths
                ("JB var/log", "/var/jb/var/log"),
                ("JB libexec", "/var/jb/usr/libexec"),
                ("JB lib", "/var/jb/usr/lib"),
                ("JB etc", "/var/jb/etc"),
                ("JB Preferences", "/var/jb/var/mobile/Library/Preferences"),
                // Fallback paths
                ("Stacks dir", "/var/mobile/Library/Logs/CrashReporter/Stacks"),
                ("DiagnosticReports", "/var/mobile/Library/Logs/DiagnosticReports"),
                ("Remapped crash dir", "/var/jb/var/mobile/Library/Logs/CrashReporter"),
                // Tools
                ("dpkg status", "/var/jb/var/lib/dpkg/status"),
                ("dpkg status (Sileo)", "/var/jb/Library/dpkg/status"),
                ("dpkg available", "/var/jb/usr/bin/dpkg"),
                ("apt available", "/var/jb/usr/bin/apt"),
                ("Sileo installed", "/var/jb/Applications/Sileo.app"),
                ("Zebra installed", "/var/jb/Applications/Zebra.app"),
                ("ElleKit present", "/var/jb/usr/lib/ellekit.dylib"),
                ("Substitute present", "/var/jb/usr/lib/libsubstitute.dylib"),
                ("bash available", "/var/jb/usr/bin/bash"),
                ("ssh available", "/var/jb/usr/bin/ssh"),
            ]

            for (label, path) in checks {
                let exists = fm.fileExists(atPath: path)
                result += "\(exists ? "✓" : "✗") \(label)\n"
            }

            result += "\n--- Statistics ---\n"
            result += "Active monitor paths: \(activePathCount)/\(totalPathCount)\n"
            result += "Visible crashes: \(visibleCount)\n"
            result += "Indexed crashes: \(indexedCount)\n"
            result += "Hidden/filtered logs: \(hiddenCount)\n"
            result += "\n=== Complete ==="

            DispatchQueue.main.async {
                self.diagResult = result
                self.isDiagnosing = false
            }
        }
    }
}

// MARK: - Shared Helper Views
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .black))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
            )
    }
}

struct FlowLayout: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.purple.opacity(0.15)))
            }
        }
    }
}
