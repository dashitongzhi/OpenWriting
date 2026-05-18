import XCTest
@testable import OpenWriting

final class SearchTests: XCTestCase {

    // MARK: - Search Token Extraction

    func testSearchTokenExtraction() {
        let query = "主角 受伤 城市"
        let tokens = Self.searchTokens(from: query)

        XCTAssertTrue(tokens.contains("主角"))
        XCTAssertTrue(tokens.contains("受伤"))
        XCTAssertTrue(tokens.contains("城市"))
    }

    func testSearchTokenMinLength() {
        let query = "主 A" // "A" is too short
        let tokens = Self.searchTokens(from: query)

        XCTAssertFalse(tokens.contains("A"))
        XCTAssertTrue(tokens.contains("主"))
    }

    func testSearchTokenDeduplication() {
        let query = "主角 主角 受伤 受伤"
        let tokens = Self.searchTokens(from: query)

        XCTAssertEqual(tokens.filter { $0 == "主角" }.count, 1)
        XCTAssertEqual(tokens.filter { $0 == "受伤" }.count, 1)
    }

    func testSearchTokenMaxCount() {
        let query = "词1 词2 词3 词4 词5 词6 词7 词8 词9 词10 词11 词12 词13 词14"
        let tokens = Self.searchTokens(from: query)

        XCTAssertLessThanOrEqual(tokens.count, 12)
    }

    func testSearchTokenPunctuationSplit() {
        let query = "主角，受伤！城市。"
        let tokens = Self.searchTokens(from: query)

        XCTAssertTrue(tokens.contains("主角"))
        XCTAssertTrue(tokens.contains("受伤"))
        XCTAssertTrue(tokens.contains("城市"))
    }

    // MARK: - Search Score Tests

    func testSearchScoreBasic() {
        let text = "这是一个关于主角的故事，主角很强。"
        let tokens = ["主角"]

        let score = Self.searchScore(in: text, tokens: tokens)

        // "主角" appears twice in text, each occurrence = length("主角") = 2
        XCTAssertEqual(score, 4)
    }

    func testSearchScoreMultipleTokens() {
        let text = "主角在城市中行走，主角很强。"
        let tokens = ["主角", "城市"]

        let score = Self.searchScore(in: text, tokens: tokens)

        // "主角" x2 = 4, "城市" x1 = 2
        XCTAssertEqual(score, 6)
    }

    func testSearchScoreNoMatch() {
        let text = "这是一个关于猫的故事。"
        let tokens = ["狗"]

        let score = Self.searchScore(in: text, tokens: tokens)

        XCTAssertEqual(score, 0)
    }

    func testSearchScoreCaseInsensitive() {
        let text = "主角 Hero 主角"
        let tokens = ["主角"]

        let score = Self.searchScore(in: text, tokens: tokens)

        // "主角" appears twice = 2*2 = 4
        XCTAssertEqual(score, 4)
    }

    func testSearchScoreEmptyText() {
        let text = ""
        let tokens = ["主角"]

        let score = Self.searchScore(in: text, tokens: tokens)

        XCTAssertEqual(score, 0)
    }

    func testSearchScoreEmptyTokens() {
        let text = "这是一个测试"
        let tokens: [String] = []

        let score = Self.searchScore(in: text, tokens: tokens)

        XCTAssertEqual(score, 0)
    }

    // MARK: - Search Excerpt Tests

    func testSearchExcerptBasic() {
        let text = "这是一个很长的文本，包含关键词在中间位置。"
        let tokens = ["关键词"]
        let excerpt = Self.searchExcerpt(from: text, tokens: tokens, limit: 30)

        XCTAssertTrue(excerpt.contains("关键词"))
    }

    func testSearchExcerptAtStart() {
        let text = "关键词在开头。这是一个测试。"
        let tokens = ["关键词"]
        let excerpt = Self.searchExcerpt(from: text, tokens: tokens, limit: 30)

        XCTAssertTrue(excerpt.hasPrefix("关键词"))
    }

    func testSearchExcerptAtEnd() {
        let text = "这是一个测试。关键词在结尾"
        let tokens = ["关键词"]
        let excerpt = Self.searchExcerpt(from: text, tokens: tokens, limit: 30)

        XCTAssertTrue(excerpt.hasSuffix("关键词在结尾"))
    }

    func testSearchExcerptShortText() {
        let text = "短文本"
        let tokens = ["短"]
        let excerpt = Self.searchExcerpt(from: text, tokens: tokens, limit: 50)

        XCTAssertEqual(excerpt, "短文本")
    }

    func testSearchExcerptNoMatch() {
        let text = "这是一个没有匹配项的文本。"
        let tokens = ["关键词"]
        let excerpt = Self.searchExcerpt(from: text, tokens: tokens, limit: 30)

        XCTAssertFalse(excerpt.isEmpty)
    }

    // MARK: - Helper Methods (mimicking AppState)

    private static func searchTokens(from query: String) -> [String] {
        let separators = CharacterSet.whitespacesNewlines
            .union(CharacterSet(charactersIn: "，。、！？：；""''（）【】《》…——"))
            .union(CharacterSet(charactersIn: ".,!?;:\"'()[]{}<>-_=+*&^%$#@~`\\|/"))
        return query.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
    }

    private static func searchScore(in text: String, tokens: [String]) -> Int {
        guard !text.isEmpty, !tokens.isEmpty else { return 0 }
        let lowercasedText = text.lowercased()
        return tokens.reduce(0) { score, token in
            let lowercasedToken = token.lowercased()
            var tokenScore = 0
            var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
            while let range = lowercasedText.range(of: lowercasedToken, options: [], range: searchRange) {
                tokenScore += max(1, lowercasedToken.count)
                searchRange = range.upperBound..<lowercasedText.endIndex
            }
            return score + tokenScore
        }
    }

    private static func searchExcerpt(from text: String, tokens: [String], limit: Int = 180) -> String {
        guard !text.isEmpty else { return "" }

        if text.count <= limit {
            return text
        }

        // Find earliest occurrence
        var earliestOffset: Int?
        var earliestIndex: String.Index?

        for token in tokens {
            if let range = text.lowercased().range(of: token.lowercased()) {
                let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                if earliestOffset == nil || offset < earliestOffset! {
                    earliestOffset = offset
                    earliestIndex = range.lowerBound
                }
            }
        }

        guard let matchIndex = earliestIndex else {
            return String(text.prefix(limit))
        }

        let matchOffset = text.distance(from: text.startIndex, to: matchIndex)
        let startOffset = max(0, matchOffset - limit / 3)
        let startIndex = text.index(text.startIndex, offsetBy: startOffset)

        var excerpt = String(text[startIndex..<text.endIndex])
        if startOffset > 0 {
            excerpt = "..." + excerpt
        }
        if excerpt.count > limit {
            excerpt = String(excerpt.prefix(limit)) + "..."
        }

        return excerpt
    }
}