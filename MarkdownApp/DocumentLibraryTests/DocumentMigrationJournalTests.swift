import Foundation

@main
enum DocumentMigrationJournalTests {
    static func main() throws {
        try testJournalRoundTripAndMonotonicCheckpoints()
        try testRecoveryBackupPreservesMarkdownHierarchy()
        try testRecoveryBackupDetectsCorruption()
        print("DocumentMigrationJournalTests: PASS")
    }

    private static func testJournalRoundTripAndMonotonicCheckpoints() throws {
        try withTemporaryDirectory { base in
            let workspace = DocumentMigrationWorkspace(rootURL: base.appendingPathComponent("Application Support/Migration"))
            let store = DocumentMigrationJournalStore(journalURL: workspace.journalURL)
            let id = UUID()
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            var journal = DocumentMigrationJournal(
                id: id,
                direction: .enableICloud,
                sourceRootURL: base.appendingPathComponent("Local"),
                destinationRootURL: base.appendingPathComponent("Cloud"),
                recoveryBackupURL: workspace.recoveryBackupURL(for: id),
                now: now
            )
            try store.save(journal)
            let initiallyLoaded = try store.load()
            expect(initiallyLoaded == journal, "journal must round-trip atomically")

            try journal.advance(to: .recoveryBackupCreated, now: now.addingTimeInterval(1))
            journal.completedRelativePaths = ["Nested/One.md"]
            try store.save(journal)
            let advanced = try store.load()
            expect(advanced?.checkpoint == .recoveryBackupCreated, "advanced checkpoint must persist")
            do {
                try journal.advance(to: .prepared)
                throw TestError("journal accepted a checkpoint regression")
            } catch DocumentMigrationJournalError.checkpointRegression {
                // Expected.
            }
            try store.clear()
            let cleared = try store.load()
            expect(cleared == nil, "cleared journal must be absent")
        }
    }

    private static func testRecoveryBackupPreservesMarkdownHierarchy() throws {
        try withTemporaryDirectory { base in
            let source = base.appendingPathComponent("Documents", isDirectory: true)
            let inbox = source.appendingPathComponent("Inbox", isDirectory: true)
            let nested = source.appendingPathComponent("Nested", isDirectory: true)
            let empty = source.appendingPathComponent("Empty", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            try Data("root".utf8).write(to: source.appendingPathComponent("Root.md"))
            try Data("nested".utf8).write(to: nested.appendingPathComponent("Note.md"))
            try Data("ignored".utf8).write(to: source.appendingPathComponent("Image.png"))
            try Data("staged".utf8).write(to: inbox.appendingPathComponent("Staged.md"))

            let workspace = DocumentMigrationWorkspace(rootURL: base.appendingPathComponent("Application Support/Migration"))
            let id = UUID()
            let backupURL = workspace.recoveryBackupURL(for: id)
            let service = DocumentRecoveryBackupService()
            let manifest = try service.createBackup(
                migrationID: id,
                sourceRootURL: source,
                backupURL: backupURL,
                excluding: inbox,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
            expect(!backupURL.path.hasPrefix(source.path + "/"), "recovery backup must stay outside visible local Documents")
            expect(Set(manifest.directories) == ["Nested", "Empty"], "empty folders and nested hierarchy must be retained")
            expect(manifest.entries.map(\.relativePath) == ["Nested/Note.md", "Root.md"], "only Markdown documents outside Inbox belong in recovery")
            try service.verifyBackup(at: backupURL)
            let backupValues = try backupURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
            expect(backupValues.isExcludedFromBackup == true, "redundant migration recovery payload must be excluded from device backup")

            try Data("changed later".utf8).write(to: source.appendingPathComponent("Root.md"), options: .atomic)
            let backupRoot = backupURL
                .appendingPathComponent(DocumentRecoveryBackupService.payloadDirectoryName)
                .appendingPathComponent("Root.md")
            let backupText = try String(contentsOf: backupRoot, encoding: .utf8)
            expect(backupText == "root", "backup must remain an independent byte copy")
        }
    }

    private static func testRecoveryBackupDetectsCorruption() throws {
        try withTemporaryDirectory { base in
            let source = base.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("safe".utf8).write(to: source.appendingPathComponent("Safe.md"))
            let backup = base.appendingPathComponent("Application Support/Recovery", isDirectory: true)
            let service = DocumentRecoveryBackupService()
            _ = try service.createBackup(
                migrationID: UUID(),
                sourceRootURL: source,
                backupURL: backup,
                excluding: nil
            )
            let payload = backup
                .appendingPathComponent(DocumentRecoveryBackupService.payloadDirectoryName)
                .appendingPathComponent("Safe.md")
            try Data("corrupt".utf8).write(to: payload, options: .atomic)
            do {
                try service.verifyBackup(at: backup)
                throw TestError("corrupted recovery backup passed verification")
            } catch DocumentRecoveryBackupError.manifestMismatch(let path) {
                expect(path == "Safe.md", "verification failure must identify the damaged relative path")
            }
        }
    }

    private static func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentMigrationJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base)
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    private struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
