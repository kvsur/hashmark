import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum DocumentEnableMigrationTests {
    static func main() async throws {
        try await testEnableCommitsOnlyAfterVerifiedMerge()
        try await testPreCommitFailureKeepsLocalModeAndRetriesIdempotently()
        try await testDisableBuildsLocalCopyAndRetainsCloud()
        try await testPostCommitFailureRecoversOnLaunch()
        print("DocumentEnableMigrationTests: PASS")
    }

    @MainActor
    private static func testPostCommitFailureRecoversOnLaunch() async throws {
        let faults = FailOnceMigrationFaults(.crashAfterModeCommit)
        try await withFixture(faults: faults) { fixture in
            let local = fixture.localRoot.appendingPathComponent("Committed.md")
            try write("committed-bytes", to: local)
            let first = fixture.makeController()
            do {
                try await first.enableICloud()
                throw TestError("injected post-commit crash did not fail")
            } catch let fault as InjectedMigrationFault {
                expect(fault.point == .crashAfterModeCommit, "post-commit failure identity must survive")
            }
            expect(first.storageMode == .iCloud, "post-commit failure must retain the newly committed cloud mode")
            expect(FileManager.default.fileExists(atPath: local.path), "post-commit failure may leave cleanup debt without losing source")

            let relaunched = fixture.makeController()
            await relaunched.start()
            expect(relaunched.storageMode == .iCloud, "launch recovery must honor committed cloud mode")
            expect(!FileManager.default.fileExists(atPath: local.path), "launch recovery must finish idempotent local cleanup")
            let journal = try await fixture.migrationService.loadJournal()
            expect(journal?.checkpoint == .cleanupCompleted, "launch recovery must persist terminal cleanup")
            let cloudText = try read(fixture.cloudDocuments.appendingPathComponent("Committed.md"))
            expect(cloudText == "committed-bytes", "post-commit recovery must retain verified cloud bytes")
        }
    }

    @MainActor
    private static func testDisableBuildsLocalCopyAndRetainsCloud() async throws {
        try await withFixture { fixture in
            try write("cloud-only", to: fixture.cloudDocuments.appendingPathComponent("Cloud.md"))
            try write("cloud-version", to: fixture.cloudDocuments.appendingPathComponent("Shared.md"))
            try write("local-version", to: fixture.localRoot.appendingPathComponent("Shared.md"))
            try write("staged", to: fixture.inbox.appendingPathComponent("Staged.md"))
            fixture.preferences.saveMode(.iCloud)
            let controller = fixture.makeController()
            await controller.start()

            try await controller.disableICloud()
            expect(controller.storageMode == .local, "verified disable must commit local mode")
            expect(controller.state == .localReady, "disable must finish local-ready")
            let localCloudText = try read(fixture.localRoot.appendingPathComponent("Cloud.md"))
            expect(localCloudText == "cloud-only", "cloud-only document must receive a local copy")
            let originalLocalText = try read(fixture.localRoot.appendingPathComponent("Shared.md"))
            expect(originalLocalText == "local-version", "disable must not overwrite an existing local file")
            let localItems = try FileManager.default.contentsOfDirectory(at: fixture.localRoot, includingPropertiesForKeys: nil)
            var cloudConflictFound = false
            for url in localItems where url.lastPathComponent.contains("Shared (Conflict") {
                if try read(url) == "cloud-version" { cloudConflictFound = true }
            }
            expect(cloudConflictFound, "divergent cloud bytes must survive as a local conflict copy")
            let retainedCloud = try read(fixture.cloudDocuments.appendingPathComponent("Cloud.md"))
            expect(retainedCloud == "cloud-only", "turning sync off must never delete the cloud library")
            expect(FileManager.default.fileExists(atPath: fixture.inbox.appendingPathComponent("Staged.md").path), "local Inbox must remain staging-only and intact")
            let journal = try await fixture.migrationService.loadJournal()
            expect(journal?.direction == .disableICloud && journal?.checkpoint == .cleanupCompleted, "disable must persist a terminal non-destructive journal")

            try await controller.enableICloud()
            expect(controller.storageMode == .iCloud, "re-enable must safely merge the retained local and cloud libraries")
            let cloudTexts = try allMarkdownTexts(in: fixture.cloudDocuments)
            expect(cloudTexts.contains("cloud-version") && cloudTexts.contains("local-version"), "re-enable must preserve every divergent byte sequence")
        }
    }

    @MainActor
    private static func testEnableCommitsOnlyAfterVerifiedMerge() async throws {
        try await withFixture { fixture in
            try write("local-root", to: fixture.localRoot.appendingPathComponent("Root.md"))
            try write("local-note", to: fixture.localRoot.appendingPathComponent("Nested/Note.md"))
            try write("cloud-note", to: fixture.cloudDocuments.appendingPathComponent("Nested/Note.md"))
            try write("staged", to: fixture.inbox.appendingPathComponent("Staged.md"))

            let controller = fixture.makeController()
            try await controller.enableICloud()

            expect(controller.storageMode == .iCloud, "verified enable must commit cloud mode")
            expect(controller.state == .cloudReady, "successful cleanup must finish cloud-ready")
            let originalCloudText = try read(fixture.cloudDocuments.appendingPathComponent("Nested/Note.md"))
            expect(originalCloudText == "cloud-note", "enable must not overwrite existing cloud bytes")
            let nestedItems = try FileManager.default.contentsOfDirectory(at: fixture.cloudDocuments.appendingPathComponent("Nested"), includingPropertiesForKeys: nil)
            var preservedLocal: URL?
            for url in nestedItems where url.lastPathComponent.contains("Conflict") {
                if try read(url) == "local-note" { preservedLocal = url; break }
            }
            expect(preservedLocal != nil, "divergent local bytes must become a cloud conflict copy")
            expect(!FileManager.default.fileExists(atPath: fixture.localRoot.appendingPathComponent("Root.md").path), "local Markdown originals may clean only after commit")
            expect(FileManager.default.fileExists(atPath: fixture.inbox.appendingPathComponent("Staged.md").path), "Inbox must survive migration cleanup")

            let journal = try await fixture.migrationService.loadJournal()
            expect(journal?.checkpoint == .cleanupCompleted, "successful enable must persist its terminal checkpoint")
            expect(FileManager.default.fileExists(atPath: journal?.recoveryBackupPath ?? ""), "recovery backup must remain after mode commit")
        }
    }

    @MainActor
    private static func testPreCommitFailureKeepsLocalModeAndRetriesIdempotently() async throws {
        let faults = FailOnceMigrationFaults(.crashBeforeModeCommit)
        try await withFixture(faults: faults) { fixture in
            let local = fixture.localRoot.appendingPathComponent("Retry.md")
            try write("retry-bytes", to: local)
            let controller = fixture.makeController()
            do {
                try await controller.enableICloud()
                throw TestError("injected pre-commit crash did not fail")
            } catch let fault as InjectedMigrationFault {
                expect(fault.point == .crashBeforeModeCommit, "failure must retain its checkpoint identity")
            }
            expect(controller.storageMode == .local, "pre-commit failure must retain local mode")
            expect(FileManager.default.fileExists(atPath: local.path), "pre-commit failure must retain local source bytes")

            try await controller.enableICloud()
            expect(controller.storageMode == .iCloud, "retry must complete the pending verified migration")
            let cloudItems = try FileManager.default.contentsOfDirectory(at: fixture.cloudDocuments, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "md" && $0.lastPathComponent.contains("Retry") }
            expect(cloudItems.count == 1, "retry must not duplicate an already merged identical document")
            let retriedText = try read(cloudItems[0])
            expect(retriedText == "retry-bytes", "retry must preserve source bytes")
        }
    }

    @MainActor
    private static func withFixture(
        faults: any DocumentMigrationFaultChecking = NoDocumentMigrationFaults(),
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentEnableMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let local = base.appendingPathComponent("Local/Documents", isDirectory: true)
        let inbox = local.appendingPathComponent("Inbox", isDirectory: true)
        let cloudContainer = base.appendingPathComponent("CloudContainer", isDirectory: true)
        let cloudDocuments = cloudContainer.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cloudDocuments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let suite = "DocumentEnableMigrationTests-\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite), "missing defaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        let migration = DocumentLibraryMigrationService(
            workspace: DocumentMigrationWorkspace(rootURL: base.appendingPathComponent("Application Support/Migration")),
            coordinator: DirectFileAccessCoordinator(),
            deviceName: "Test iPhone",
            faults: faults
        )
        let fixture = Fixture(
            localRoot: local,
            inbox: inbox,
            cloudDocuments: cloudDocuments,
            preferences: DocumentStoragePreferenceStore(defaults: defaults),
            cloudService: ICloudContainerService(runtime: FakeMigrationCloudRuntime(containerURL: cloudContainer)),
            migrationService: migration
        )
        try await body(fixture)
    }

    @MainActor
    private struct Fixture {
        let localRoot: URL
        let inbox: URL
        let cloudDocuments: URL
        let preferences: DocumentStoragePreferenceStore
        let cloudService: ICloudContainerService
        let migrationService: DocumentLibraryMigrationService

        func makeController() -> DocumentLibraryController {
            DocumentLibraryController(
                localRootURL: localRoot,
                localInboxURL: inbox,
                preferenceStore: preferences,
                cloudContainerService: cloudService,
                migrationService: migrationService
            )
        }
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
    private static func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private static func allMarkdownTexts(in root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension.lowercased() == "md" else { return nil }
            return try read(url)
        }
    }
    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError(message) }
        return value
    }
    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !value() { fatalError(message) }
    }
    private struct TestError: Error { let message: String; init(_ message: String) { self.message = message } }
}

private struct InjectedMigrationFault: Error { let point: DocumentMigrationFaultPoint }

private final class FailOnceMigrationFaults: DocumentMigrationFaultChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var armed: DocumentMigrationFaultPoint?
    init(_ point: DocumentMigrationFaultPoint) { armed = point }
    func checkpoint(_ point: DocumentMigrationFaultPoint) throws {
        lock.lock()
        defer { lock.unlock() }
        if armed == point { armed = nil; throw InjectedMigrationFault(point: point) }
    }
}

private final class FakeMigrationCloudRuntime: ICloudContainerRuntime, @unchecked Sendable {
    let container: URL
    init(containerURL: URL) { container = containerURL }
    func containerURL(for identifier: String) -> URL? { container }
    func identityFingerprint() -> String? { "test-account" }
    func createDirectory(at url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    func itemStatus(at url: URL) throws -> ICloudItemStatus {
        ICloudItemStatus(isUbiquitous: false, isDownloaded: true, isDownloading: false, downloadErrorDescription: nil)
    }
    func startDownloading(at url: URL) throws {}
}
