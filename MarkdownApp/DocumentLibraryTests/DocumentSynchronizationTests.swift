import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum DocumentSynchronizationTests {
    static func main() async throws {
        try testOpenDocumentPresenterIdentityAndOrdering()
        try await testDirtyRemoteAndDeletedDraftPreservation()
        try await testVersionConflictMaterializationAndDeduplication()
        try await testFailedMaterializationNeverResolvesVersions()
        try await testOfflineCloudFeatureParityAndAccountFreeze()
        print("DocumentSynchronizationTests: PASS")
    }

    private static func testOpenDocumentPresenterIdentityAndOrdering() throws {
        let original = URL(fileURLWithPath: "/Cloud/Original.md")
        let moved = URL(fileURLWithPath: "/Cloud/Nested/Moved.md")
        let recorder = OpenEventRecorder()
        let presenter = OpenDocumentPresenter(url: original) { recorder.append($0) }

        presenter.presentedItemDidChange()
        presenter.presentedItemDidMove(to: moved)
        presenter.presentedItemDidChange()
        var deletionAcknowledged = false
        presenter.accommodatePresentedItemDeletion { error in
            expect(error == nil, "a presented deletion must be acknowledged without inventing an error")
            deletionAcknowledged = true
        }

        expect(deletionAcknowledged, "the presenter must always invoke the deletion completion handler")
        expect(presenter.presentedItemURL == moved, "a remote move must update the presenter's identity")
        expect(recorder.events == [
            .changed(original),
            .moved(from: original, to: moved),
            .changed(moved),
            .deleted(moved)
        ], "open-document events must retain serial move-aware URL identity")
    }

    private static func testDirtyRemoteAndDeletedDraftPreservation() async throws {
        try await withTemporaryDirectory("DocumentSyncPreservation") { root in
            let nested = root.appendingPathComponent("Nested", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let document = nested.appendingPathComponent("Note.md")
            try Data("remote bytes".utf8).write(to: document)
            let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
            let resolver = DocumentConflictResolver(
                coordinator: DirectFileAccessCoordinator(),
                versionAccess: FakeVersionAccess([]),
                deviceName: "Test iPhone",
                timestamp: { fixedDate }
            )

            let preserved = try await resolver.preserveRemoteText(
                "remote bytes",
                activeDraftText: "local draft",
                beside: document
            )
            let preservedURL = try unwrap(preserved, "distinct remote content was not materialized")
            let preservedText = try String(contentsOf: preservedURL, encoding: .utf8)
            let mainText = try String(contentsOf: document, encoding: .utf8)
            expect(preservedText == "remote bytes",
                   "the remote sibling must retain exact remote bytes")
            expect(mainText == "remote bytes",
                   "preserving remote content must not mutate the main file")

            let duplicate = try await resolver.preserveRemoteText(
                "same",
                activeDraftText: "same",
                beside: document
            )
            expect(duplicate == nil, "identical remote and draft bytes must not create noise")

            let occupiedRootName = root.appendingPathComponent("Note.md")
            try Data("existing root".utf8).write(to: occupiedRootName)
            let recovered = try await resolver.recoverDraft(
                "unsaved draft",
                formerlyAt: document,
                in: root
            )
            expect(recovered.deletingLastPathComponent() == root,
                   "a deleted dirty draft must recover at the active library root")
            expect(recovered != occupiedRootName, "recovery must never overwrite an existing root document")
            let recoveredText = try String(contentsOf: recovered, encoding: .utf8)
            let occupiedText = try String(contentsOf: occupiedRootName, encoding: .utf8)
            expect(recoveredText == "unsaved draft",
                   "recovery must retain exact in-memory draft bytes")
            expect(occupiedText == "existing root",
                   "recovery must preserve pre-existing root content")
        }
    }

    private static func testVersionConflictMaterializationAndDeduplication() async throws {
        try await withTemporaryDirectory("DocumentVersionResolution") { root in
            let document = root.appendingPathComponent("Shared.md")
            try Data("winner".utf8).write(to: document)
            let versions = FakeVersionAccess([
                DocumentVersionSnapshot(identifier: "winner-copy", data: Data("winner".utf8), modifiedAt: Date(timeIntervalSince1970: 1)),
                DocumentVersionSnapshot(identifier: "remote-a", data: Data("remote A".utf8), modifiedAt: Date(timeIntervalSince1970: 2)),
                DocumentVersionSnapshot(identifier: "remote-a-copy", data: Data("remote A".utf8), modifiedAt: Date(timeIntervalSince1970: 3)),
                DocumentVersionSnapshot(identifier: "remote-b", data: Data("remote B".utf8), modifiedAt: Date(timeIntervalSince1970: 4))
            ])
            let resolver = DocumentConflictResolver(
                coordinator: DirectFileAccessCoordinator(),
                versionAccess: versions,
                deviceName: "Test iPhone",
                timestamp: { Date(timeIntervalSince1970: 1_700_000_000) }
            )

            let report = try await resolver.resolveVersions(at: document)
            expect(report.materializedURLs.count == 2,
                   "every distinct non-winning byte sequence must become exactly one sibling")
            let materializedTexts = try Set(report.materializedURLs.map { try String(contentsOf: $0, encoding: .utf8) })
            expect(materializedTexts == Set(["remote A", "remote B"]),
                   "materialized siblings must retain all distinct losing bytes")
            expect(Set(report.deduplicatedVersionIdentifiers) == Set(["winner-copy", "remote-a-copy"]),
                   "winner-identical and duplicate conflict versions must be deduplicated")
            expect(versions.finishedIdentifiers == Set(["winner-copy", "remote-a", "remote-a-copy", "remote-b"]),
                   "versions may resolve only after every distinct byte sequence is verified")
            let winnerText = try String(contentsOf: document, encoding: .utf8)
            expect(winnerText == "winner",
                   "automatic resolution must leave the nominated current version untouched")
        }
    }

    private static func testFailedMaterializationNeverResolvesVersions() async throws {
        try await withTemporaryDirectory("DocumentVersionFailure") { root in
            let document = root.appendingPathComponent("Shared.md")
            try Data("winner".utf8).write(to: document)
            let versions = FakeVersionAccess([
                DocumentVersionSnapshot(identifier: "sole-loser", data: Data("must survive".utf8), modifiedAt: nil)
            ])
            let resolver = DocumentConflictResolver(
                coordinator: FailingConflictWriteCoordinator(),
                versionAccess: versions,
                deviceName: "Test iPhone"
            )
            do {
                _ = try await resolver.resolveVersions(at: document)
                throw TestError("an injected conflict-copy failure unexpectedly succeeded")
            } catch is InjectedWriteFailure {
                // Expected.
            }
            expect(versions.finishedIdentifiers.isEmpty,
                   "a version must remain unresolved when its sole bytes were not materialized")
            let winnerText = try String(contentsOf: document, encoding: .utf8)
            expect(winnerText == "winner",
                   "a failed conflict copy must not alter the current file")
        }
    }

    @MainActor
    private static func testOfflineCloudFeatureParityAndAccountFreeze() async throws {
        try await withTemporaryDirectory("DocumentOfflineCloud") { base in
            let localRoot = base.appendingPathComponent("Local/Documents", isDirectory: true)
            let inbox = localRoot.appendingPathComponent("Inbox", isDirectory: true)
            let cloudContainer = base.appendingPathComponent("Cloud", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cloudContainer, withIntermediateDirectories: true)
            let suite = "DocumentOfflineCloud-\(UUID().uuidString)"
            let defaults = try unwrap(
                UserDefaults(suiteName: suite),
                "missing isolated defaults"
            )
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = DocumentStoragePreferenceStore(defaults: defaults)
            preferences.saveMode(.iCloud)
            let runtime = OfflineICloudRuntime(containerURL: cloudContainer, identity: "account-a")
            let controller = DocumentLibraryController(
                localRootURL: localRoot,
                localInboxURL: inbox,
                preferenceStore: preferences,
                cloudContainerService: ICloudContainerService(runtime: runtime),
                conflictResolver: DocumentConflictResolver(
                    coordinator: DirectFileAccessCoordinator(),
                    versionAccess: FakeVersionAccess([]),
                    deviceName: "Offline iPhone"
                )
            )
            await controller.start()
            expect(controller.storageMode == .iCloud && controller.state == .cloudReady,
                   "downloaded iCloud content must remain usable with no network")

            let root = controller.activeRootURL
            let folder = try await controller.createFolder(named: "Offline", in: root)
            let original = try await controller.createMarkdown(named: "Draft", in: folder)
            try await controller.writeText("offline edit", to: original)
            let offlineText = try await controller.readText(at: original)
            expect(offlineText == "offline edit",
                   "offline edits must round-trip through the cloud store")
            let renamed = try await controller.rename(node(original), to: "Renamed")
            let moved = try await controller.move(node(renamed), to: root)

            let external = base.appendingPathComponent("Imported.md")
            try Data("imported offline".utf8).write(to: external)
            let imported = try await controller.importFile(from: external, to: root)
            let tree = try await controller.tree()
            let visibleFiles = fileURLs(in: tree)
            let movedReferenceURL = try unwrap(
                visibleFiles.first { $0.lastPathComponent == moved.lastPathComponent },
                "moved offline document was absent from the live tree"
            )
            let importedReferenceURL = try unwrap(
                visibleFiles.first { $0.lastPathComponent == imported.lastPathComponent },
                "imported offline document was absent from the live tree"
            )
            let referenceTexts = [
                movedReferenceURL: try await controller.readText(at: movedReferenceURL),
                importedReferenceURL: try await controller.readText(at: importedReferenceURL)
            ]
            let references = DocumentReferenceResolver.attachments(
                in: tree,
                selectedURLs: [movedReferenceURL, importedReferenceURL],
                readText: { referenceTexts[$0] ?? "" }
            )
            expect(references.count == 2, "offline cloud documents must remain usable as AI references")
            expect(runtime.downloadRequests.isEmpty,
                   "already-downloaded offline operations must not attempt a network download")

            try await controller.delete(node(imported))
            expect(!FileManager.default.fileExists(atPath: imported.path),
                   "offline deletes must apply locally and queue normal iCloud propagation")

            runtime.identity = "account-b"
            NotificationCenter.default.post(name: NSNotification.Name.NSUbiquityIdentityDidChange, object: nil)
            for _ in 0..<20 {
                if case .cloudUnavailable = controller.state { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard case .cloudUnavailable = controller.state else {
                throw TestError("account change did not publish cloud-unavailable state")
            }
            expect(controller.storageMode == .iCloud && preferences.loadMode() == .iCloud,
                   "account loss must never fork into local mode")
            do {
                _ = try await controller.createMarkdown(named: "Blocked", in: root)
                throw TestError("account-change mutation freeze was bypassed")
            } catch DocumentLibraryError.mutationsFrozen {
                // Expected.
            }

            await controller.retryICloudAccess()
            expect(controller.storageMode == .iCloud && controller.state == .cloudReady,
                   "retry must re-resolve the current account without changing committed mode")
            _ = try await controller.createMarkdown(named: "After Retry", in: root)
        }
    }

    private static func node(_ url: URL) -> DocumentNode {
        DocumentNode(url: url, kind: .markdown, modifiedAt: .distantPast)
    }

    private static func fileURLs(in nodes: [DocumentTreeNode]) -> [URL] {
        nodes.flatMap { node in
            if let children = node.children { return fileURLs(in: children) }
            return [node.node.url]
        }
    }

    private static func withTemporaryDirectory(
        _ prefix: String,
        _ body: (URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError(message) }
        return value
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() { fatalError(message) }
    }

    private struct TestError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}

private final class OpenEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OpenDocumentEvent] = []
    var events: [OpenDocumentEvent] { locked { stored } }
    func append(_ event: OpenDocumentEvent) { locked { stored.append(event) } }
    @discardableResult private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

private final class FakeVersionAccess: DocumentVersionAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [DocumentVersionSnapshot]
    private var storedFinishedIdentifiers = Set<String>()
    init(_ snapshots: [DocumentVersionSnapshot]) { self.snapshots = snapshots }
    var finishedIdentifiers: Set<String> { locked { storedFinishedIdentifiers } }
    func unresolvedVersions(at url: URL) throws -> [DocumentVersionSnapshot] { locked { snapshots } }
    func finishResolution(at url: URL, identifiers: Set<String>) throws {
        locked {
            storedFinishedIdentifiers.formUnion(identifiers)
            snapshots.removeAll { identifiers.contains($0.identifier) }
        }
    }
    @discardableResult private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}

private struct InjectedWriteFailure: Error {}

private final class FailingConflictWriteCoordinator: FileAccessCoordinating, @unchecked Sendable {
    func read<T>(at url: URL, accessor: (URL) throws -> T) throws -> T { try accessor(url) }
    func write<T>(at url: URL, options: NSFileCoordinator.WritingOptions, accessor: (URL) throws -> T) throws -> T {
        throw InjectedWriteFailure()
    }
    func readWrite<T>(reading sourceURL: URL, writing destinationURL: URL, accessor: (URL, URL) throws -> T) throws -> T {
        throw InjectedWriteFailure()
    }
    func move<T>(from sourceURL: URL, to destinationURL: URL, accessor: (URL, URL) throws -> T) throws -> T {
        throw InjectedWriteFailure()
    }
}

private final class OfflineICloudRuntime: ICloudContainerRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private let containerURLValue: URL
    private var identityValue: String
    private var storedDownloadRequests: [URL] = []

    init(containerURL: URL, identity: String) {
        containerURLValue = containerURL
        identityValue = identity
    }

    var identity: String {
        get { locked { identityValue } }
        set { locked { identityValue = newValue } }
    }
    var downloadRequests: [URL] { locked { storedDownloadRequests } }
    func containerURL(for identifier: String) -> URL? { containerURLValue }
    func identityFingerprint() -> String? { identity }
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func itemStatus(at url: URL) throws -> ICloudItemStatus {
        ICloudItemStatus(isUbiquitous: true, isDownloaded: true, isDownloading: false, downloadErrorDescription: nil)
    }
    func startDownloading(at url: URL) throws { locked { storedDownloadRequests.append(url) } }
    @discardableResult private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }
}
