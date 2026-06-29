import Foundation

enum UserFacingError {
    static func aiMessage(for error: Error, fallbackAction: String = "请稍后重试。") -> String {
        if let aiError = error as? AIWritingError {
            switch aiError {
            case .invalidResponse:
                return "模型返回内容格式异常，当前正文没有被改动。\(fallbackAction)"
            case let .serverError(message):
                return "模型服务调用失败，当前正文没有被改动。\(shortDetail(message))"
            case .rateLimited:
                return "模型请求过于频繁，当前正文没有被改动。请稍后再试，或降低连续生成频率。"
            case let .transientServerError(statusCode, _):
                return "模型服务暂时不可用（HTTP \(statusCode)），当前正文没有被改动。请稍后重试。"
            case .emptyResult:
                return "模型没有返回可用正文，当前正文没有被改动。请调整提示或稍后重试。"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络连接异常，当前正文没有被改动。请检查网络或模型服务地址后重试。"
        }

        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return fallbackAction }
        return "\(fallbackAction)（\(shortDetail(detail))）"
    }

    static func syncMessage(for error: Error) -> String {
        "iCloud 同步暂时没有完成，本机项目内容仍会保留。\(shortDetail(error.localizedDescription))"
    }

    static func exportMessage(for error: Error) -> String {
        "导出没有完成，项目内容没有被改动。\(shortDetail(error.localizedDescription))"
    }

    static func persistenceMessage(for error: Error) -> String {
        "本机保存遇到问题，请先不要关闭应用，并尝试导出备份。\(shortDetail(error.localizedDescription))"
    }

    private static func shortDetail(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        return "\(trimmed.prefix(120))..."
    }
}
