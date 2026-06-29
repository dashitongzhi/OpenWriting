import Foundation
import OSLog

nonisolated enum AppLogger {
    static let ai = Logger(subsystem: "com.openwriting.app", category: "ai")
    static let sync = Logger(subsystem: "com.openwriting.app", category: "sync")
    static let persistence = Logger(subsystem: "com.openwriting.app", category: "persistence")
    static let export = Logger(subsystem: "com.openwriting.app", category: "export")
    static let quality = Logger(subsystem: "com.openwriting.app", category: "quality")
}
