import CoreFoundation
import Foundation

enum TextFileDecoding {
    enum Error: LocalizedError {
        case unreadableContent

        var errorDescription: String? {
            switch self {
            case .unreadableContent:
                return "暂不支持这个文本文件的编码格式，请先转换成 UTF-8、UTF-16 或 GB18030 后再导入。"
            }
        }
    }

    nonisolated static func loadText(from url: URL, usingSecurityScopedAccess: Bool = false) throws -> String {
        let accessed = usingSecurityScopedAccess ? url.startAccessingSecurityScopedResource() : false
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        return try decodeText(from: data)
    }

    nonisolated static func decodeText(from data: Data) throws -> String {
        if let string = decodeUsingByteOrderMark(from: data) {
            return string
        }

        for encoding in candidateEncodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }

        throw Error.unreadableContent
    }

    private nonisolated static func decodeUsingByteOrderMark(from data: Data) -> String? {
        let bomEncodings: [(prefix: [UInt8], encoding: String.Encoding)] = [
            ([0xEF, 0xBB, 0xBF], .utf8),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian)
        ]

        for candidate in bomEncodings where data.starts(with: candidate.prefix) {
            return String(data: data, encoding: candidate.encoding)
        }

        return nil
    }

    private nonisolated static var candidateEncodings: [String.Encoding] {
        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .utf32LittleEndian,
            .utf32BigEndian,
            .gb18030,
            .gbk,
            .big5
        ]

        var seenRawValues = Set<UInt>()
        return encodings.filter { seenRawValues.insert($0.rawValue).inserted }
    }
}

private extension String.Encoding {
    nonisolated static var gb18030: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        )
    }

    nonisolated static var gbk: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue))
        )
    }

    nonisolated static var big5: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        )
    }
}
