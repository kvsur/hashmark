import Foundation

nonisolated enum DocumentStorageMode: String, Codable, CaseIterable, Sendable {
    case local
    case iCloud
}

nonisolated enum DocumentMigrationDirection: String, Codable, Sendable {
    case enableICloud
    case disableICloud
}

nonisolated enum DocumentLibraryState: Equatable, Sendable {
    case localReady
    case checkingCloud
    case cloudReady
    case syncing
    case migrating(direction: DocumentMigrationDirection, progress: Double)
    case cloudUnavailable(reason: String)
    case failed(message: String)
}

nonisolated struct DocumentLibraryIdentity: Hashable, Sendable {
    let mode: DocumentStorageMode
    let rootPath: String

    init(mode: DocumentStorageMode, rootURL: URL) {
        self.mode = mode
        rootPath = rootURL.standardizedFileURL.path
    }
}
