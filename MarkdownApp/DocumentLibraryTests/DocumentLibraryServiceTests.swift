import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum DocumentLibraryServiceTests {
    static func main() async throws {
        try testPreferenceDefaultsAndPersistence()
        try await testExplicitRootInboxAndSerializedOperations()
        try await testMutationFreeze()
        try await testControllerRevisionAndIdentity()
        try await testLocalCreateRenameContinueAndReopen()
        print("DocumentLibraryServiceTests: PASS")
    }

    private static func testPreferenceDefaultsAndPersistence() throws {
        let suite = "DocumentLibraryServiceTests-\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite), "missing isolated defaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DocumentStoragePreferenceStore(defaults: defaults)
        expect(preferences.loadMode() == .local, "storage mode must default to local")
        preferences.saveMode(.iCloud)
        expect(preferences.loadMode() == .iCloud, "committed mode must persist")
    }

    private static func testExplicitRootInboxAndSerializedOperations() async throws {
        try await withTemporaryLibrary { service, root, inbox, fileManager in
            try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
            let staged = inbox.appendingPathComponent("Staged.md")
            try Data("staged".utf8).write(to: staged)

            let created = try await withThrowingTaskGroup(of: URL.self) { group in
                for _ in 0..<8 {
                    group.addTask { try await service.createMarkdown(named: "Note", in: root) }
                }
                var urls: [URL] = []
                for try await url in group { urls.append(url) }
                return urls
            }
            expect(Set(created).count == 8, "actor serialization must preserve all name collisions")
            let visible = try await service.contents(of: root)
            expect(visible.count == 8, "all serialized creations must be visible")
            let inboxIsInside = await service.isInsideLibrary(staged)
            expect(!inboxIsInside, "local Inbox must not become part of an active library")

            try await service.purgeInbox()
            expect(!fileManager.fileExists(atPath: staged.path), "purge must always target the explicit local Inbox")

            let empty = created[0]
            let emptyText = try await service.readText(at: empty)
            expect(emptyText.isEmpty, "a readable empty document is valid content")
            try await service.writeText("body", to: empty)
            let savedText = try await service.readText(at: empty)
            expect(savedText == "body", "atomic write must round-trip")
        }
    }

    private static func testMutationFreeze() async throws {
        try await withTemporaryLibrary { service, root, _, _ in
            await service.setMutationsFrozen(true)
            do {
                _ = try await service.createMarkdown(named: "Blocked", in: root)
                throw TestError("frozen service accepted a mutation")
            } catch DocumentLibraryError.mutationsFrozen {
                // Expected.
            }
            await service.setMutationsFrozen(false)
            _ = try await service.createMarkdown(named: "Allowed", in: root)
        }
    }

    @MainActor
    private static func testControllerRevisionAndIdentity() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("DocumentLibraryControllerTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Documents", isDirectory: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let suite = "DocumentLibraryControllerTests-\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite), "missing isolated defaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = DocumentLibraryController(
            localRootURL: root,
            localInboxURL: inbox,
            preferenceStore: DocumentStoragePreferenceStore(defaults: defaults),
            fileManager: fileManager
        )

        let initialRevision = controller.revision
        let created = try await controller.createMarkdown(named: "Controller", in: root)
        expect(controller.revision == initialRevision + 1, "successful mutations must publish one revision")

        let createdNode = DocumentNode(url: created, kind: .markdown, modifiedAt: .distantPast)
        let noOpRevision = controller.revision
        let unchanged = try await controller.rename(createdNode, to: "Controller")
        expect(unchanged.standardizedFileURL.path == created.standardizedFileURL.path,
               "same-name controller rename should keep the source URL")
        expect(controller.revision == noOpRevision, "same-name rename must not publish a false revision")

        let renamed = try await controller.rename(createdNode, to: "Renamed")
        expect(renamed.lastPathComponent == "Renamed.md", "controller rename should preserve the extension")
        expect(controller.revision == noOpRevision + 1, "a real rename must publish exactly one revision")

        let cloudRoot = base.appendingPathComponent("Cloud", isDirectory: true)
        controller.commit(mode: .iCloud, rootURL: cloudRoot, state: .cloudReady)
        expect(controller.storageMode == .iCloud, "commit must publish the new mode")
        expect(controller.identity == DocumentLibraryIdentity(mode: .iCloud, rootURL: cloudRoot), "identity must change with root and mode")
        expect(DocumentStoragePreferenceStore(defaults: defaults).loadMode() == .iCloud, "commit must persist only the committed mode")
    }

    @MainActor
    private static func testLocalCreateRenameContinueAndReopen() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("DocumentLibraryRoundTripTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Documents", isDirectory: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        let suite = "DocumentLibraryRoundTripTests-\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite), "missing round-trip defaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DocumentStoragePreferenceStore(defaults: defaults)
        let controller = DocumentLibraryController(
            localRootURL: root,
            localInboxURL: inbox,
            preferenceStore: preferences,
            fileManager: fileManager
        )

        let created = try await controller.createMarkdown(named: "", in: root)
        try await controller.writeText("# Notes", to: created)
        let createdNode = DocumentNode(url: created, kind: .markdown, modifiedAt: .distantPast)
        let renamed = try await controller.rename(createdNode, to: "Notes")
        try await controller.writeText("# Notes\n\nContinued", to: renamed)

        let reopenedController = DocumentLibraryController(
            localRootURL: root,
            localInboxURL: inbox,
            preferenceStore: preferences,
            fileManager: fileManager
        )
        let reopenedText = try await reopenedController.readText(at: renamed)
        let reopenedItems = try await reopenedController.contents(of: root)
        expect(reopenedText == "# Notes\n\nContinued", "reopening must read continued edits from the renamed URL")
        expect(reopenedItems.contains { $0.url.standardizedFileURL.path == renamed.standardizedFileURL.path },
               "the reopened library must list the renamed document")
        expect(!fileManager.fileExists(atPath: created.path), "rename must not leave an orphaned fallback file")
    }

    private static func withTemporaryLibrary(
        _ body: (DocumentLibraryService, URL, URL, FileManager) async throws -> Void
    ) async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("DocumentLibraryServiceTests-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Active", isDirectory: true)
        let inbox = base.appendingPathComponent("LocalDocuments/Inbox", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        let store = FileStore(
            fileManager: fileManager,
            rootURL: root,
            localInboxURL: inbox,
            accessCoordinator: DirectFileAccessCoordinator()
        )
        try await body(DocumentLibraryService(store: store), root, inbox, fileManager)
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError(message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    private struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
