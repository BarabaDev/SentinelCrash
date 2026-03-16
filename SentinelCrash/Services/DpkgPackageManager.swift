import Foundation

// MARK: - DpkgPackageManager
final class DpkgPackageManager: Sendable {

    private let statusPaths: [String] = [
        "/var/jb/var/lib/dpkg/status",
        "/var/lib/dpkg/status",
        // Sileo / alternative dpkg locations
        "/var/jb/Library/dpkg/status",
    ]

    private let dylibSearchPaths: [String] = [
        "/var/jb/Library/MobileSubstrate/DynamicLibraries",
        "/var/jb/usr/lib",
    ]

    // MARK: - Public

    /// Read and parse all installed packages from dpkg status file.
    func loadInstalledPackages() -> [DpkgPackage] {
        for path in statusPaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return parseStatusFile(content)
            }
        }
        return []
    }

    /// Build a mapping from dylib filename to package identifier.
    func buildDylibToPackageMap(packages: [DpkgPackage]) -> [String: DpkgPackage] {
        var map: [String: DpkgPackage] = [:]
        for pkg in packages {
            for dylib in pkg.providedDylibs {
                let filename = (dylib as NSString).lastPathComponent
                map[filename.lowercased()] = pkg
            }
        }

        // Also scan DynamicLibraries directories for .plist -> .dylib mapping
        let fm = FileManager.default
        for searchPath in dylibSearchPaths {
            guard let files = try? fm.contentsOfDirectory(atPath: searchPath) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let plistPath = "\(searchPath)/\(file)"
                let dylibName = file.replacingOccurrences(of: ".plist", with: ".dylib")
                guard fm.fileExists(atPath: "\(searchPath)/\(dylibName)") else { continue }

                if let data = fm.contents(atPath: plistPath),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let filter = plist["Filter"] as? [String: Any] {
                    // Try to find matching package by dylib name
                    let key = dylibName.lowercased()
                    if map[key] == nil {
                        // Create a synthetic entry from the plist
                        let bundleFilter = (filter["Bundles"] as? [String])?.joined(separator: ", ") ?? ""
                        let pkg = DpkgPackage(
                            identifier: "unknown.dylib.\(dylibName)",
                            name: dylibName.replacingOccurrences(of: ".dylib", with: ""),
                            version: "?",
                            author: "",
                            description: "Loaded dylib: \(dylibName). Filters: \(bundleFilter)",
                            section: "Tweaks",
                            installedSize: 0,
                            status: .installed,
                            installedDate: fileModificationDate(plistPath),
                            depends: [],
                            providedDylibs: [dylibName]
                        )
                        map[key] = pkg
                    }
                }
            }
        }

        return map
    }

    /// Try to determine install date of a package from filesystem metadata.
    func estimateInstallDate(for packageID: String) -> Date? {
        let possiblePaths = [
            "/var/jb/var/lib/dpkg/info/\(packageID).list",
            "/var/jb/var/lib/dpkg/info/\(packageID).md5sums",
            "/var/lib/dpkg/info/\(packageID).list",
            // Sileo / alternative dpkg info locations
            "/var/jb/Library/dpkg/info/\(packageID).list",
            "/var/jb/Library/dpkg/info/\(packageID).md5sums",
        ]
        for path in possiblePaths {
            if let date = fileModificationDate(path) {
                return date
            }
        }
        return nil
    }

    /// Get dpkg info list file contents for a package (installed file listing).
    func installedFiles(for packageID: String) -> [String] {
        let paths = [
            "/var/jb/var/lib/dpkg/info/\(packageID).list",
            "/var/lib/dpkg/info/\(packageID).list",
            // Sileo / alternative dpkg info locations
            "/var/jb/Library/dpkg/info/\(packageID).list",
        ]
        for path in paths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    // MARK: - Parsing

    private func parseStatusFile(_ content: String) -> [DpkgPackage] {
        let blocks = content.components(separatedBy: "\n\n")
        var packages: [DpkgPackage] = []

        for block in blocks {
            guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let pkg = parseBlock(block) {
                packages.append(pkg)
            }
        }

        return packages
    }

    private func parseBlock(_ block: String) -> DpkgPackage? {
        var fields: [String: String] = [:]
        var currentKey = ""
        var currentValue = ""

        for line in block.components(separatedBy: "\n") {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // Continuation of previous field
                currentValue += "\n" + line.trimmingCharacters(in: .whitespaces)
            } else if let colonIndex = line.firstIndex(of: ":") {
                // Save previous field
                if !currentKey.isEmpty {
                    fields[currentKey.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
                }
                currentKey = String(line[..<colonIndex])
                currentValue = String(line[line.index(after: colonIndex)...])
            }
        }
        // Save last field
        if !currentKey.isEmpty {
            fields[currentKey.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
        }

        guard let identifier = fields["package"], !identifier.isEmpty else { return nil }

        let statusRaw = fields["status"] ?? ""
        let status = DpkgPackage.PackageStatus(raw: statusRaw)
        guard status == .installed || status == .halfInstalled else { return nil }

        let installedSizeStr = fields["installed-size"] ?? "0"
        let installedSize = Int64(installedSizeStr) ?? 0

        let depends = (fields["depends"] ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { dep -> String in
                // Strip version constraints: "package (>= 1.0)" -> "package"
                if let parenIdx = dep.firstIndex(of: "(") {
                    return String(dep[..<parenIdx]).trimmingCharacters(in: .whitespaces)
                }
                return dep
            }
            .filter { !$0.isEmpty }

        // Determine provided dylibs from installed files
        let dylibFiles = installedFiles(for: identifier).filter {
            $0.hasSuffix(".dylib") || $0.hasSuffix(".framework")
        }

        let installDate = estimateInstallDate(for: identifier)

        return DpkgPackage(
            identifier: identifier,
            name: fields["name"] ?? identifier,
            version: fields["version"] ?? "?",
            author: fields["author"] ?? fields["maintainer"] ?? "",
            description: fields["description"] ?? "",
            section: fields["section"] ?? "",
            installedSize: installedSize,
            status: status,
            installedDate: installDate,
            depends: depends,
            providedDylibs: dylibFiles
        )
    }

    private func fileModificationDate(_ path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
