import Foundation

enum ReferenceDocumentImporting {
    static func documents(
        from urls: [URL],
        usingSecurityScopedAccess: Bool = true
    ) throws -> [ReferenceDocument] {
        try urls.map { try document(from: $0, usingSecurityScopedAccess: usingSecurityScopedAccess) }
    }

    static func document(
        from url: URL,
        usingSecurityScopedAccess: Bool = true
    ) throws -> ReferenceDocument {
        let content = try text(from: url, usingSecurityScopedAccess: usingSecurityScopedAccess)
        return ReferenceDocument(
            title: url.deletingPathExtension().lastPathComponent,
            content: content,
            importedAt: TimestampLabel.now()
        )
    }

    static func text(
        from url: URL,
        usingSecurityScopedAccess: Bool = true
    ) throws -> String {
        try TextFileDecoding.loadText(from: url, usingSecurityScopedAccess: usingSecurityScopedAccess)
    }
}
