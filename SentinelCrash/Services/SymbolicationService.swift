import Foundation

/// Resolves memory addresses to function names and library offsets from crash logs.
final class SymbolicationService {

    struct SymbolicatedFrame {
        let index: Int
        let library: String
        let address: String
        let symbol: String
        let isResolved: Bool
        let sourceInfo: String
    }

    struct SymbolicationResult {
        let frames: [SymbolicatedFrame]
        let resolvedCount: Int
        let totalCount: Int
        var resolvedPercentage: Double {
            totalCount > 0 ? Double(resolvedCount) / Double(totalCount) * 100.0 : 0.0
        }
    }

    struct BinaryImage {
        let baseAddress: UInt64
        let endAddress: UInt64
        let name: String
        let uuid: String
        let path: String
    }

    func symbolicate(rawContent: String) -> SymbolicationResult {
        let binaryImages = parseBinaryImages(from: rawContent)
        let rawFrames = extractFrames(from: rawContent)
        var results: [SymbolicatedFrame] = []
        var resolved = 0

        for (idx, frame) in rawFrames.enumerated() {
            let sym = resolveFrame(frame, index: idx, binaryImages: binaryImages)
            results.append(sym)
            if sym.isResolved { resolved += 1 }
        }

        return SymbolicationResult(frames: results, resolvedCount: resolved, totalCount: results.count)
    }

    func parseBinaryImages(from content: String) -> [BinaryImage] {
        var images: [BinaryImage] = []
        let lines = content.components(separatedBy: "\n")
        var inBinaryImages = false

        let pattern = #"(0x[0-9a-fA-F]+)\s*-\s*(0x[0-9a-fA-F]+)\s+(\S+)\s+<([^>]+)>\s+(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            if line.contains("Binary Images:") { inBinaryImages = true; continue }
            if !inBinaryImages { continue }

            let nsRange = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: nsRange), match.numberOfRanges >= 6 {
                let baseStr = Range(match.range(at: 1), in: line).map { String(line[$0]) } ?? ""
                let endStr = Range(match.range(at: 2), in: line).map { String(line[$0]) } ?? ""
                let name = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""
                let uuid = Range(match.range(at: 4), in: line).map { String(line[$0]) } ?? ""
                let path = Range(match.range(at: 5), in: line).map { String(line[$0]) } ?? ""

                let base = UInt64(baseStr.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
                let end = UInt64(endStr.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0
                images.append(BinaryImage(baseAddress: base, endAddress: end, name: name, uuid: uuid, path: path.trimmingCharacters(in: .whitespaces)))
            }
        }
        return images
    }

    private struct RawFrame {
        let library: String
        let address: String
        let symbolOrOffset: String
    }

    private func extractFrames(from content: String) -> [RawFrame] {
        var frames: [RawFrame] = []
        let lines = content.components(separatedBy: "\n")
        var inCrashedThread = false

        let pattern = #"^\s*\d+\s+(\S+)\s+(0x[0-9a-fA-F]+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Thread") && trimmed.contains("Crashed") {
                inCrashedThread = true; continue
            }
            if inCrashedThread && trimmed.hasPrefix("Thread ") && !trimmed.contains("Crashed") { break }
            if trimmed.hasPrefix("Binary Images:") { break }

            if inCrashedThread {
                let nsRange = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: nsRange), match.numberOfRanges >= 4 {
                    let lib = Range(match.range(at: 1), in: line).map { String(line[$0]) } ?? ""
                    let addr = Range(match.range(at: 2), in: line).map { String(line[$0]) } ?? ""
                    let rest = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""
                    frames.append(RawFrame(library: lib, address: addr, symbolOrOffset: rest))
                }
            }
        }
        return frames
    }

    private func resolveFrame(_ frame: RawFrame, index: Int, binaryImages: [BinaryImage]) -> SymbolicatedFrame {
        let sym = frame.symbolOrOffset.trimmingCharacters(in: .whitespaces)
        let hasSymbol = !sym.isEmpty && !sym.hasPrefix("0x") && sym != "???"

        if hasSymbol {
            return SymbolicatedFrame(index: index, library: frame.library, address: frame.address, symbol: sym, isResolved: true, sourceInfo: "")
        }

        if let addr = UInt64(frame.address.replacingOccurrences(of: "0x", with: ""), radix: 16) {
            for image in binaryImages where addr >= image.baseAddress && addr <= image.endAddress {
                let offset = addr - image.baseAddress
                return SymbolicatedFrame(index: index, library: image.name, address: frame.address, symbol: "\(image.name) + 0x\(String(offset, radix: 16))", isResolved: false, sourceInfo: "UUID: \(image.uuid)")
            }
        }

        return SymbolicatedFrame(index: index, library: frame.library, address: frame.address, symbol: sym.isEmpty ? frame.address : sym, isResolved: false, sourceInfo: "")
    }
}
