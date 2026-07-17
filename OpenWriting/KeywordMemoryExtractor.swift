import Foundation

enum KeywordMemoryExtractor {
    static func extract(from text: String, volumeNumber: Int, chapterNumber: Int) -> [MemoryItem] {
        let source = Source(
            volumeNumber: max(volumeNumber, 1),
            chapterNumber: max(chapterNumber, 1)
        )
        let characters = characterItems(from: text, source: source)
        let characterNames = Set(characters.map(\.subject))

        return characters
            + relationshipItems(from: text, characterNames: characterNames, source: source)
            + locationItems(from: text, source: source)
            + foreshadowItems(from: text, source: source)
            + timelineItems(from: text, source: source)
            + storyFactItems(from: text, source: source)
    }

    private struct Source {
        let volumeNumber: Int
        let chapterNumber: Int
    }

    private static let nonNameWords: Set<String> = [
        "什么", "怎么", "那个", "这个", "他们", "我们", "你们", "自己",
        "别人", "大家", "哪个", "哪些", "任何", "某个", "某些", "每个",
        "谁", "哪", "哪位", "哪边", "哪儿", "哪里",
        "知道", "没有", "觉得", "需要", "希望", "认为", "相信", "明白",
        "看见", "听到", "感到", "想起", "发现", "决定", "开始", "结束",
        "离开", "回来", "过来", "出去", "起来", "下来", "上去", "出来",
        "告诉", "说道", "回答", "笑道", "说话", "问道", "叹道", "怒道",
        "冷声道", "轻声道", "淡淡道", "大声道", "低声道", "急道", "惊道",
        "道", "说", "答", "叫", "喊", "笑", "哭", "叹", "问", "怒",
        "想", "看", "听", "走", "来", "去", "到", "回", "出", "入",
        "站", "坐", "躺", "拿", "放", "拉", "推", "打", "挡",
        "已经", "不是", "可能", "可以", "应该", "还是", "就是", "只是",
        "不过", "因为", "所以", "但是", "如果", "虽然", "或者", "然后",
        "忽然", "突然", "居然", "竟然", "果然", "依然", "仍然", "当然",
        "自然", "显然", "似乎", "仿佛", "好像", "大概", "也许", "或许",
        "几乎", "简直", "根本", "实在", "确实", "真正", "完全", "非常",
        "特别", "尤其", "甚至", "至少", "至多", "反正", "总之", "否则",
        "于是", "接着", "随后", "随即", "马上", "立刻", "立即", "赶紧",
        "连忙", "急忙", "渐渐", "慢慢", "悄悄", "偷偷", "默默",
        "现在", "刚才", "此时", "这时", "那时", "这里", "那里", "到处",
        "时候", "一下", "一点", "一些", "许多", "很多", "所有", "全部",
        "方才", "之前", "之后", "以后", "以前", "将来", "未来",
        "昨天", "今天", "明天", "前天", "后天",
        "一个", "两个", "几个", "那些", "这些", "各种", "各位",
        "本人", "自身", "对方", "彼此", "互相", "一起", "一同", "单独",
        "的话", "罢了", "而已", "算了", "好吧", "对了", "行了", "够了"
    ]

    private static func characterItems(from text: String, source: Source) -> [MemoryItem] {
        var frequency: [String: Int] = [:]
        let nsText = text as NSString

        if let regex = try? NSRegularExpression(
            pattern: "[\u{201C}\u{0022}]([^\u{201C}\u{201D}\u{0022}\n]{1,20})[\u{201D}\u{0022}]"
        ) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let contextStart = max(0, match.range.location - 10)
                let contextLength = min(match.range.location - contextStart, 20)
                let context = nsText.substring(with: NSRange(location: contextStart, length: contextLength))
                for name in names(from: context) {
                    frequency[name, default: 0] += 1
                }
            }
        }

        for pattern in ["道：", "笑道", "怒道", "冷声道", "道，", "说道："] {
            var searchStart = text.startIndex
            while let range = text.range(of: pattern, range: searchStart..<text.endIndex) {
                let availableDistance = text.distance(from: text.startIndex, to: range.lowerBound)
                let contextStart = text.index(
                    range.lowerBound,
                    offsetBy: -min(10, availableDistance),
                    limitedBy: text.startIndex
                ) ?? text.startIndex
                for name in names(from: String(text[contextStart..<range.lowerBound])) {
                    frequency[name, default: 0] += 2
                }
                searchStart = range.upperBound
            }
        }

        return frequency
            .filter { $0.value >= 2 }
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(10)
            .map { name, _ in
                MemoryItem(
                    category: .characterState,
                    subject: name,
                    field: "出场",
                    value: "在第\(source.volumeNumber)卷第\(source.chapterNumber)章中出场并有对白或行动",
                    sourceVolumeNumber: source.volumeNumber,
                    sourceChapter: source.chapterNumber
                )
            }
    }

    private static func relationshipItems(
        from text: String,
        characterNames: Set<String>,
        source: Source
    ) -> [MemoryItem] {
        var pairs: [String: Int] = [:]
        let paragraphs = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for paragraph in paragraphs {
            let present = characterNames.filter(paragraph.contains).sorted()
            guard present.count >= 2 else { continue }
            for firstIndex in present.indices {
                for secondIndex in present.index(after: firstIndex)..<present.endIndex {
                    pairs["\(present[firstIndex])↔\(present[secondIndex])", default: 0] += 1
                }
            }
        }

        return pairs
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(8)
            .map { pair, count in
                MemoryItem(
                    category: .relationship,
                    subject: pair,
                    field: count >= 3 ? "密切互动" : "互动",
                    value: "第\(source.volumeNumber)卷第\(source.chapterNumber)章中共同出现\(count)次",
                    sourceVolumeNumber: source.volumeNumber,
                    sourceChapter: source.chapterNumber
                )
            }
    }

    private static func locationItems(from text: String, source: Source) -> [MemoryItem] {
        let patterns = [
            "在(.{2,8}?)[，。,.]", "来到(.{2,8}?)[，。,.]",
            "到达(.{2,8}?)[，。,.]", "离开(.{2,8}?)[，。,.]",
            "进入(.{2,8}?)[，。,.]", "走出(.{2,8}?)[，。,.]"
        ]
        let rejectedLocations: Set<String> = [
            "这里", "那里", "此时", "这时", "什么", "自己", "对方", "面前",
            "身后", "旁边", "外面", "里面", "上面", "下面", "前面", "后面",
            "之间", "其中", "之后", "之前", "以后", "以前"
        ]
        let nsText = text as NSString
        var frequency: [String: Int] = [:]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
                guard match.numberOfRanges >= 2 else { continue }
                let location = nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if (2...8).contains(location.count), !rejectedLocations.contains(location) {
                    frequency[location, default: 0] += 1
                }
            }
        }

        return frequency
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(6)
            .map { location, _ in
                MemoryItem(
                    category: .worldRule,
                    subject: location,
                    field: "地点",
                    value: "在第\(source.volumeNumber)卷第\(source.chapterNumber)章中出现",
                    sourceVolumeNumber: source.volumeNumber,
                    sourceChapter: source.chapterNumber
                )
            }
    }

    private static func foreshadowItems(from text: String, source: Source) -> [MemoryItem] {
        let patterns = [
            ("暗示线索", ["暗示", "似乎", "仿佛", "好像"]),
            ("悬疑伏笔", ["疑团", "谜团", "悬念", "蹊跷", "奇怪"]),
            ("未解之谜", ["不知", "不解", "未明", "不明", "无法解释"]),
            ("隐藏信息", ["秘密", "隐瞒", "隐藏", "藏着", "背后的真相"]),
            ("预兆", ["预感", "预兆", "不祥", "隐隐"])
        ]
        var items: [MemoryItem] = []

        for (field, markers) in patterns {
            for marker in markers {
                var searchStart = text.startIndex
                while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
                    let leadingDistance = text.distance(from: text.startIndex, to: range.lowerBound)
                    let trailingDistance = text.distance(from: range.upperBound, to: text.endIndex)
                    let contextStart = text.index(
                        range.lowerBound,
                        offsetBy: -min(8, leadingDistance),
                        limitedBy: text.startIndex
                    ) ?? text.startIndex
                    let contextEnd = text.index(
                        range.upperBound,
                        offsetBy: min(20, trailingDistance),
                        limitedBy: text.endIndex
                    ) ?? text.endIndex
                    let context = String(text[contextStart..<contextEnd])
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if context.count >= 4 {
                        items.append(MemoryItem(
                            category: .openLoop,
                            subject: String(context.prefix(30)),
                            field: field,
                            value: context,
                            status: .tentative,
                            sourceVolumeNumber: source.volumeNumber,
                            sourceChapter: source.chapterNumber
                        ))
                    }
                    searchStart = range.upperBound
                }
            }
        }

        return Array(items.prefix(8))
    }

    private static func timelineItems(from text: String, source: Source) -> [MemoryItem] {
        let markers = [
            "黎明", "清晨", "早上", "上午", "中午", "下午", "傍晚", "黄昏",
            "晚上", "深夜", "午夜", "凌晨", "日出", "日落", "天亮", "天黑",
            "三天后", "第二天", "次日", "当日", "当晚", "一周后", "一个月后",
            "一年后", "数日后", "数月后", "数年后", "半月后", "两周后", "多年后",
            "片刻后", "半晌", "一炷香", "一盏茶", "过了许久", "过了很久",
            "不知过了多久", "日复一日", "年复一年", "转眼间", "不知不觉",
            "那一年", "这一年", "那日", "这日", "翌日"
        ]

        return markers
            .filter(text.contains)
            .prefix(6)
            .map { marker in
                MemoryItem(
                    category: .timeline,
                    subject: marker,
                    field: "时间标记",
                    value: "第\(source.volumeNumber)卷第\(source.chapterNumber)章提及「\(marker)」",
                    sourceVolumeNumber: source.volumeNumber,
                    sourceChapter: source.chapterNumber
                )
            }
    }

    private static func storyFactItems(from text: String, source: Source) -> [MemoryItem] {
        let patterns = [
            ("关键转折", ["决定", "选择", "放弃", "离开", "归来", "背叛"]),
            ("能力揭示", ["觉醒", "突破", "领悟", "解锁", "获得"]),
            ("重要信息", ["真相", "发现", "揭露", "得知", "原来"])
        ]
        var items: [MemoryItem] = []

        for (field, markers) in patterns {
            for marker in markers {
                let count = text.components(separatedBy: marker).count - 1
                if count >= 2 {
                    items.append(MemoryItem(
                        category: .storyFact,
                        subject: marker,
                        field: field,
                        value: "第\(source.volumeNumber)卷第\(source.chapterNumber)章中出现\(count)次",
                        sourceVolumeNumber: source.volumeNumber,
                        sourceChapter: source.chapterNumber
                    ))
                }
            }
        }

        return Array(items.prefix(8))
    }

    private static func names(from context: String) -> [String] {
        let separators = CharacterSet(charactersIn: "，。、；：！？… \t\n\"'")
        return context
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                guard (2...6).contains(token.count), !nonNameWords.contains(token) else { return false }
                let isCapitalized = token.unicodeScalars.first
                    .map(CharacterSet.uppercaseLetters.contains) ?? false
                let allChinese = token.unicodeScalars.allSatisfy {
                    (0x4E00...0x9FFF).contains($0.value)
                }
                return isCapitalized || (allChinese && token.count <= 4)
            }
    }
}
