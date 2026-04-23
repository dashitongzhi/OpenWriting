import Foundation

struct LiteraryQuote: Identifiable, Hashable {
    let author: String
    let country: String
    let text: String
    let source: String

    var id: String {
        "\(author)|\(text)"
    }
}

enum LiteraryQuoteLibrary {
    static var totalCount: Int {
        all.count
    }

    static func quote(for item: SidebarItem, seed: Int) -> LiteraryQuote? {
        guard !all.isEmpty else { return nil }
        let index = stableHash("\(item.rawValue)|\(seed)") % all.count
        return all[index]
    }

    private static let all: [LiteraryQuote] = loadQuotes()

    private nonisolated static func loadQuotes() -> [LiteraryQuote] {
        guard let url = quotesResourceURL(),
              let content = try? TextFileDecoding.loadText(from: url) else {
            return []
        }

        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap(parseLine)
    }

    private nonisolated static func quotesResourceURL() -> URL? {
        let legacyBundleName = ("Open" + "Reading") + "_" + ("Open" + "Reading") + ".bundle"
        let resourcePaths = [
            "LiteraryQuotes.zh-Hans.tsv",
            "Resources/LiteraryQuotes.zh-Hans.tsv",
            "OpenWriting_OpenWriting.bundle/LiteraryQuotes.zh-Hans.tsv",
            "\(legacyBundleName)/LiteraryQuotes.zh-Hans.tsv"
        ]

        let candidates = resourcePaths.flatMap { resourcePath in
            [
                Bundle.main.resourceURL?.appendingPathComponent(resourcePath),
                Bundle.main.bundleURL.appendingPathComponent(resourcePath),
                Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(resourcePath)
            ]
        }

        return candidates.first(where: {
            guard let url = $0 else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }) ?? nil
    }

    private nonisolated static func parseLine(_ line: Substring) -> LiteraryQuote? {
        let columns = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard columns.count == 4 else { return nil }

        let author = simplifiedChinese(String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines))
        let country = simplifiedChinese(String(columns[1]).trimmingCharacters(in: .whitespacesAndNewlines))
        let text = simplifiedChinese(String(columns[2]).trimmingCharacters(in: .whitespacesAndNewlines))
        let source = sanitizeSource(simplifiedChinese(String(columns[3])))

        guard !author.isEmpty, !text.isEmpty else { return nil }

        return LiteraryQuote(
            author: author,
            country: country,
            text: text,
            source: source
        )
    }

    private nonisolated static func sanitizeSource(_ source: String) -> String {
        var sanitized = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = sanitized.range(of: "衍生") {
            sanitized.removeSubrange(range.lowerBound..<sanitized.endIndex)
        }

        if sanitized == "原文" || !containsChineseCharacters(sanitized) {
            sanitized = ""
        }

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func simplifiedChinese(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return String(mutable)
    }

    private nonisolated static func containsChineseCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private nonisolated static func stableHash(_ text: String) -> Int {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037

        for scalar in text.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= prime
        }

        return Int(hash & 0x7fff_ffff_ffff_ffff)
    }
}
