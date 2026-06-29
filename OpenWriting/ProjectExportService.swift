import Foundation
import OSLog

struct ProjectExportSummary {
    let directoryURL: URL
    let fileCount: Int
}

struct ProjectExportValidationReport {
    let directoryURL: URL
    let project: NovelProject
    let manifestFileCount: Int
    let missingFiles: [String]
    let invalidFiles: [String]

    var isValid: Bool {
        missingFiles.isEmpty && invalidFiles.isEmpty
    }
}

enum ProjectExportError: LocalizedError {
    case missingManifest(URL)
    case unreadableProjectJSON(URL)
    case invalidManifest(URL)
    case invalidExport(URL, missingFiles: [String], invalidFiles: [String])

    var errorDescription: String? {
        switch self {
        case let .missingManifest(url):
            return "没有找到导出清单：\(url.path)"
        case let .unreadableProjectJSON(url):
            return "无法读取项目备份文件：\(url.path)"
        case let .invalidManifest(url):
            return "导出清单不可解析：\(url.path)"
        case let .invalidExport(_, missingFiles, invalidFiles):
            let missing = missingFiles.isEmpty ? "" : "缺少文件：\(missingFiles.prefix(3).joined(separator: "、"))。"
            let invalid = invalidFiles.isEmpty ? "" : "文件格式异常：\(invalidFiles.prefix(3).joined(separator: "、"))。"
            return "导出备份不完整。\(missing)\(invalid)"
        }
    }
}

enum ProjectExportService {
    private struct Manifest: Codable {
        var title: String
        var exportedAt: String
        var chapterCount: Int
        var savedWordCount: Int
        var currentDraftWordCount: Int
        var manuscriptWordCount: Int
        var files: [String]
    }

    static func exportProject(_ project: NovelProject, to directoryURL: URL) throws -> ProjectExportSummary {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let chaptersDirectory = directoryURL.appendingPathComponent("chapters", isDirectory: true)
        try fileManager.createDirectory(at: chaptersDirectory, withIntermediateDirectories: true)

        let chapters = orderedChapters(for: project)
        var files: [String] = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let projectData = try encoder.encode(project)
        let projectURL = directoryURL.appendingPathComponent("project.json", isDirectory: false)
        try projectData.write(to: projectURL, options: .atomic)
        files.append("project.json")

        for (index, chapter) in chapters.enumerated() {
            let fileName = chapterFileName(for: chapter, index: index)
            let chapterMarkdown = markdown(for: chapter)
            try chapterMarkdown.write(
                to: chaptersDirectory.appendingPathComponent(fileName, isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
            files.append("chapters/\(fileName)")
        }

        let fullMarkdown = fullBookMarkdown(for: project, chapters: chapters)
        try fullMarkdown.write(
            to: directoryURL.appendingPathComponent("full-book.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        files.append("full-book.md")

        let docxData = try DOCXExporter.data(for: project, chapters: chapters)
        try docxData.write(to: directoryURL.appendingPathComponent("full-book.docx", isDirectory: false), options: .atomic)
        files.append("full-book.docx")

        let epubData = try EPUBExporter.data(for: project, chapters: chapters)
        try epubData.write(to: directoryURL.appendingPathComponent("full-book.epub", isDirectory: false), options: .atomic)
        files.append("full-book.epub")

        if !project.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let currentDraft = "# \(project.currentChapterSummary)\n\n\(project.draftText)\n"
            try currentDraft.write(
                to: directoryURL.appendingPathComponent("current-draft.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
            files.append("current-draft.md")
        }

        let manifest = Manifest(
            title: project.title,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            chapterCount: project.savedChapterCount,
            savedWordCount: project.savedChapterWordCount,
            currentDraftWordCount: project.draftWordCount,
            manuscriptWordCount: project.manuscriptWordCount,
            files: files
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: directoryURL.appendingPathComponent("manifest.json", isDirectory: false), options: .atomic)

        return ProjectExportSummary(directoryURL: directoryURL, fileCount: files.count + 1)
    }

    static func validateExport(at directoryURL: URL) throws -> ProjectExportValidationReport {
        let fileManager = FileManager.default
        let manifestURL = directoryURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ProjectExportError.missingManifest(manifestURL)
        }

        let decoder = JSONDecoder()
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            AppLogger.export.error("Export manifest could not be read: \(manifestURL.path, privacy: .public)")
            throw ProjectExportError.invalidManifest(manifestURL)
        }

        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData) else {
            AppLogger.export.error("Export manifest could not be decoded: \(manifestURL.path, privacy: .public)")
            throw ProjectExportError.invalidManifest(manifestURL)
        }

        let projectURL = directoryURL.appendingPathComponent("project.json", isDirectory: false)
        guard let projectData = try? Data(contentsOf: projectURL) else {
            AppLogger.export.error("Export project JSON could not be read: \(projectURL.path, privacy: .public)")
            throw ProjectExportError.unreadableProjectJSON(projectURL)
        }

        guard let project = try? decoder.decode(NovelProject.self, from: projectData) else {
            AppLogger.export.error("Export project JSON could not be decoded: \(projectURL.path, privacy: .public)")
            throw ProjectExportError.unreadableProjectJSON(projectURL)
        }

        let listedFiles = Set(manifest.files + ["manifest.json"])
        let missingFiles = listedFiles
            .filter { relativePath in
                !fileManager.fileExists(atPath: directoryURL.appendingPathComponent(relativePath).path)
            }
            .sorted()

        let invalidFiles = listedFiles
            .filter { relativePath in
                let url = directoryURL.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: url.path) else { return false }
                return !isValidExportFile(relativePath: relativePath, url: url)
            }
            .sorted()

        let report = ProjectExportValidationReport(
            directoryURL: directoryURL,
            project: project,
            manifestFileCount: listedFiles.count,
            missingFiles: missingFiles,
            invalidFiles: invalidFiles
        )

        guard report.isValid else {
            throw ProjectExportError.invalidExport(
                directoryURL,
                missingFiles: missingFiles,
                invalidFiles: invalidFiles
            )
        }

        return report
    }

    static func importProject(from directoryURL: URL) throws -> NovelProject {
        try validateExport(at: directoryURL).project
    }

    private static func orderedChapters(for project: NovelProject) -> [ChapterDraft] {
        project.chapterDrafts.sorted {
            if $0.volumeNumber != $1.volumeNumber {
                return $0.volumeNumber < $1.volumeNumber
            }
            if $0.chapterNumber != $1.chapterNumber {
                return $0.chapterNumber < $1.chapterNumber
            }
            if $0.savedAtDate != $1.savedAtDate {
                return $0.savedAtDate < $1.savedAtDate
            }
            return $0.id < $1.id
        }
    }

    private static func chapterFileName(for chapter: ChapterDraft, index: Int) -> String {
        let title = sanitizedFileComponent(chapter.chapterTitle)
        return String(
            format: "%04d-v%04d-ch%04d-%@.md",
            index + 1,
            chapter.volumeNumber,
            chapter.chapterNumber,
            title.isEmpty ? "chapter" : title
        )
    }

    private static func markdown(for chapter: ChapterDraft) -> String {
        "# \(chapter.chapterSummary)\n\n\(chapter.content.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }

    private static func fullBookMarkdown(for project: NovelProject, chapters: [ChapterDraft]) -> String {
        let body = chapters.map { chapter in
            markdown(for: chapter)
        }.joined(separator: "\n\n")
        return "# \(project.title)\n\n\(project.summary)\n\n\(body)"
    }

    private static func sanitizedFileComponent(_ value: String) -> String {
        value
            .map { character in
                if character.isLetter || character.isNumber {
                    return String(character)
                }
                if character == "-" || character == "_" {
                    return String(character)
                }
                return "-"
            }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_ "))
    }

    private static func isValidExportFile(relativePath: String, url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "json":
            guard let data = try? Data(contentsOf: url) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil
        case "md":
            return (try? String(contentsOf: url, encoding: .utf8)) != nil
        case "docx", "epub":
            return hasZipHeader(url)
        default:
            return true
        }
    }

    private static func hasZipHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let signature = handle.readData(ofLength: 4)
        return signature == Data([0x50, 0x4b, 0x03, 0x04])
            || signature == Data([0x50, 0x4b, 0x05, 0x06])
            || signature == Data([0x50, 0x4b, 0x07, 0x08])
    }
}

private enum DOCXExporter {
    static func data(for project: NovelProject, chapters: [ChapterDraft]) throws -> Data {
        let paragraphs = [
            paragraph(project.title, style: "Title"),
            paragraph(project.summary, style: nil)
        ] + chapters.flatMap { chapter in
            [paragraph(chapter.chapterSummary, style: "Heading1")] + chapter.content
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { paragraph($0, style: nil) }
        }

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        \(paragraphs.joined(separator: "\n"))
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        </w:body>
        </w:document>
        """

        var archive = ZipArchiveBuilder()
        archive.add("[Content_Types].xml", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """)
        archive.add("_rels/.rels", text: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """)
        archive.add("word/document.xml", text: document)
        return try archive.data()
    }

    private static func paragraph(_ text: String, style: String?) -> String {
        let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        return "<w:p>\(styleXML)<w:r><w:t>\(xmlEscaped(text))</w:t></w:r></w:p>"
    }
}

private enum EPUBExporter {
    static func data(for project: NovelProject, chapters: [ChapterDraft]) throws -> Data {
        var archive = ZipArchiveBuilder()
        archive.addStored("mimetype", text: "application/epub+zip")
        archive.add("META-INF/container.xml", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """)

        var chapterItems: [(id: String, fileName: String, title: String)] = []
        for (index, chapter) in chapters.enumerated() {
            let fileName = String(format: "chapter-%04d.xhtml", index + 1)
            archive.add("OEBPS/\(fileName)", text: xhtml(for: chapter, project: project))
            chapterItems.append((id: "chapter\(index + 1)", fileName: fileName, title: chapter.chapterSummary))
        }

        let manifestItems = chapterItems
            .map { "<item id=\"\($0.id)\" href=\"\($0.fileName)\" media-type=\"application/xhtml+xml\"/>" }
            .joined(separator: "\n")
        let spineItems = chapterItems
            .map { "<itemref idref=\"\($0.id)\"/>" }
            .joined(separator: "\n")
        let navPoints = chapterItems.enumerated().map { index, item in
            """
            <navPoint id="navPoint-\(index + 1)" playOrder="\(index + 1)">
            <navLabel><text>\(xmlEscaped(item.title))</text></navLabel>
            <content src="\(item.fileName)"/>
            </navPoint>
            """
        }.joined(separator: "\n")

        archive.add("OEBPS/content.opf", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(xmlEscaped(project.title))</dc:title>
        <dc:language>zh-CN</dc:language>
        <dc:identifier id="bookid">urn:uuid:\(project.id)</dc:identifier>
        </metadata>
        <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        \(manifestItems)
        </manifest>
        <spine toc="ncx">
        \(spineItems)
        </spine>
        </package>
        """)

        archive.add("OEBPS/toc.ncx", text: """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
        <head><meta name="dtb:uid" content="urn:uuid:\(project.id)"/></head>
        <docTitle><text>\(xmlEscaped(project.title))</text></docTitle>
        <navMap>
        \(navPoints)
        </navMap>
        </ncx>
        """)

        return try archive.data()
    }

    private static func xhtml(for chapter: ChapterDraft, project: NovelProject) -> String {
        let paragraphs = chapter.content
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\(xmlEscaped($0))</p>" }
            .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">
        <head><title>\(xmlEscaped(chapter.chapterSummary))</title></head>
        <body>
        <h1>\(xmlEscaped(chapter.chapterSummary))</h1>
        \(paragraphs)
        </body>
        </html>
        """
    }
}

private struct ZipArchiveBuilder {
    private enum CompressionMethod: UInt16 {
        case stored = 0
    }

    private struct Entry {
        var path: String
        var data: Data
        var compressionMethod: CompressionMethod
    }

    private var entries: [Entry] = []

    mutating func add(_ path: String, text: String) {
        addStored(path, text: text)
    }

    mutating func addStored(_ path: String, text: String) {
        entries.append(Entry(path: path, data: Data(text.utf8), compressionMethod: .stored))
    }

    func data() throws -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let offset = UInt32(output.count)
            let nameData = Data(entry.path.utf8)
            let checksum = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)

            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(entry.compressionMethod.rawValue)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(checksum)
            output.appendUInt32(size)
            output.appendUInt32(size)
            output.appendUInt16(UInt16(nameData.count))
            output.appendUInt16(0)
            output.append(nameData)
            output.append(entry.data)

            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(entry.compressionMethod.rawValue)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(checksum)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt32(size)
            centralDirectory.appendUInt16(UInt16(nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(offset)
            centralDirectory.append(nameData)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralDirectoryOffset)
        output.appendUInt16(0)
        return output
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            var value = (crc ^ UInt32(byte)) & 0xff
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xedb88320 ^ (value >> 1)) : (value >> 1)
            }
            crc = (crc >> 8) ^ value
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<UInt32>.size))
    }
}

private func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
