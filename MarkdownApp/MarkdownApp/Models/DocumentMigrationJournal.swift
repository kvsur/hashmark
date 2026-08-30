import Foundation

nonisolated enum DocumentMigrationCheckpoint: String, Codable, CaseIterable, Sendable {
    case prepared
    case recoveryBackupCreated
    case mergeCompleted
    case verificationCompleted
    case modeCommitted
    case cleanupCompleted
}

nonisolated struct DocumentMigrationJournal: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let direction: DocumentMigrationDirection
    let sourceRootPath: String
    let destinationRootPath: String
    let recoveryBackupPath: String
    let startedAt: Date
    var updatedAt: Date
    var checkpoint: DocumentMigrationCheckpoint
    var completedRelativePaths: [String]
    var cleanupDebtRelativePaths: [String]

    init(
        id: UUID = UUID(),
        direction: DocumentMigrationDirection,
        sourceRootURL: URL,
        destinationRootURL: URL,
        recoveryBackupURL: URL,
        now: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.direction = direction
        sourceRootPath = sourceRootURL.standardizedFileURL.path
        destinationRootPath = destinationRootURL.standardizedFileURL.path
        recoveryBackupPath = recoveryBackupURL.standardizedFileURL.path
        startedAt = now
        updatedAt = now
        checkpoint = .prepared
        completedRelativePaths = []
        cleanupDebtRelativePaths = []
    }

    mutating func advance(to checkpoint: DocumentMigrationCheckpoint, now: Date = Date()) throws {
        guard let currentIndex = Self.checkpointIndex(self.checkpoint),
              let nextIndex = Self.checkpointIndex(checkpoint),
              nextIndex >= currentIndex else {
            throw DocumentMigrationJournalError.checkpointRegression(from: self.checkpoint, to: checkpoint)
        }
        self.checkpoint = checkpoint
        updatedAt = now
    }

    private static func checkpointIndex(_ checkpoint: DocumentMigrationCheckpoint) -> Int? {
        DocumentMigrationCheckpoint.allCases.firstIndex(of: checkpoint)
    }
}

nonisolated enum DocumentMigrationJournalError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case checkpointRegression(from: DocumentMigrationCheckpoint, to: DocumentMigrationCheckpoint)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "The document migration journal version \(version) is unsupported."
        case .checkpointRegression(let current, let requested):
            return "The migration checkpoint cannot move backward from \(current.rawValue) to \(requested.rawValue)."
        }
    }
}

nonisolated struct DocumentMigrationJournalStore: @unchecked Sendable {
    let journalURL: URL

    private let fileManager: FileManager

    init(journalURL: URL, fileManager: FileManager = .default) {
        self.journalURL = journalURL
        self.fileManager = fileManager
    }

    func load() throws -> DocumentMigrationJournal? {
        guard fileManager.fileExists(atPath: journalURL.path) else { return nil }
        let journal = try JSONDecoder.migration.decode(
            DocumentMigrationJournal.self,
            from: Data(contentsOf: journalURL)
        )
        guard journal.schemaVersion == DocumentMigrationJournal.currentSchemaVersion else {
            throw DocumentMigrationJournalError.unsupportedSchemaVersion(journal.schemaVersion)
        }
        return journal
    }

    func save(_ journal: DocumentMigrationJournal) throws {
        guard journal.schemaVersion == DocumentMigrationJournal.currentSchemaVersion else {
            throw DocumentMigrationJournalError.unsupportedSchemaVersion(journal.schemaVersion)
        }
        try fileManager.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.migration.encode(journal)
        try data.write(to: journalURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        try fileManager.removeItem(at: journalURL)
    }
}

nonisolated struct DocumentMigrationWorkspace: Sendable {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    init(fileManager: FileManager = .default) throws {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        rootURL = applicationSupport
            .appendingPathComponent("Hashmark", isDirectory: true)
            .appendingPathComponent("DocumentMigration", isDirectory: true)
    }

    var journalURL: URL { rootURL.appendingPathComponent("journal.json") }

    func historyJournalURL(for migrationID: UUID) -> URL {
        rootURL
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("\(migrationID.uuidString).json")
    }

    func recoveryBackupURL(for migrationID: UUID) -> URL {
        rootURL
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent(migrationID.uuidString, isDirectory: true)
    }
}

private extension JSONEncoder {
    nonisolated static var migration: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var migration: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
