import Foundation

enum TimestampLabel {
    static func now() -> String {
        PersistedTimestampCodec.displayLabel(for: Date(), style: .compact)
    }

    static func project() -> String {
        PersistedTimestampCodec.displayLabel(for: Date(), style: .project)
    }
}
