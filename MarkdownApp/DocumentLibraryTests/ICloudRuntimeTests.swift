import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum ICloudRuntimeTests {
    static func main() async throws {
        try await testContainerResolutionAndIdentity()
        try await testUnavailableContainer()
        try await testDownloadReadinessAndFailure()
        try testPresenterEvents()
        try testEveryCloudOperationUsesCoordination()
        print("ICloudRuntimeTests: PASS")
    }

    private static func testContainerResolutionAndIdentity() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ICloudRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let runtime = FakeICloudRuntime(containerURL: base, identity: "account-a")
        let service = ICloudContainerService(runtime: runtime)
        let resolution = try await service.resolve()
        expect(resolution.documentsURL == base.appendingPathComponent("Documents", isDirectory: true), "resolution must use the public Documents directory")
        expect(runtime.createdDirectories == [resolution.documentsURL], "resolution must prepare Documents")
        try await service.verifyIdentity()
        runtime.identity = "account-b"
        do {
            try await service.verifyIdentity()
            throw TestError("identity change was accepted")
        } catch ICloudContainerError.identityChanged {
            // Expected.
        }
    }

    private static func testUnavailableContainer() async throws {
        let runtime = FakeICloudRuntime(containerURL: nil, identity: nil)
        let service = ICloudContainerService(runtime: runtime)
        do {
            _ = try await service.resolve()
            throw TestError("unavailable container resolved")
        } catch ICloudContainerError.unavailable {
            // Expected.
        }
    }

    private static func testDownloadReadinessAndFailure() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ICloudDownloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let runtime = FakeICloudRuntime(containerURL: base, identity: "account")
        let service = ICloudContainerService(runtime: runtime)
        _ = try await service.resolve()
        let document = base.appendingPathComponent("Documents/Cloud.md")
        runtime.status = ICloudItemStatus(
            isUbiquitous: true,
            isDownloaded: false,
            isDownloading: false,
            downloadErrorDescription: nil
        )
        try await service.ensureDownloaded(at: document, timeout: 1)
        expect(runtime.downloadRequests == [document], "cloud-only reads must request a download")

        runtime.status = ICloudItemStatus(
            isUbiquitous: true,
            isDownloaded: false,
            isDownloading: false,
            downloadErrorDescription: "quota"
        )
        do {
            try await service.ensureDownloaded(at: document, timeout: 1)
            throw TestError("download error was treated as empty content")
        } catch ICloudContainerError.downloadFailed(let message) {
            expect(message == "quota", "typed download failure must preserve its reason")
        }
    }

    private static func testPresenterEvents() throws {
        let root = URL(fileURLWithPath: "/tmp/iCloud-presenter", isDirectory: true)
        let first = root.appendingPathComponent("First.md")
        let second = root.appendingPathComponent("Second.md")
        let recorder = EventRecorder()
        let presenter = ICloudLibraryPresenter(rootURL: root) { event in
            recorder.append(event)
        }
        presenter.presentedSubitemDidAppear(at: first)
        presenter.presentedSubitemDidChange(at: first)
        presenter.presentedSubitem(at: first, didMoveTo: second)
        var deletionCompleted = false
        presenter.accommodatePresentedSubitemDeletion(at: second) { error in
            expect(error == nil, "presenter deletion acknowledgement must not invent an error")
            deletionCompleted = true
        }
        presenter.presentedItemDidChange()
        expect(deletionCompleted, "presenter must acknowledge deletion")
        expect(recorder.events == [
            .itemAppeared(first),
            .itemChanged(first),
            .itemMoved(from: first, to: second),
            .itemDeleted(second),
            .rootChanged(root)
        ], "presenter must retain external event identity and order")
    }

    private static func testEveryCloudOperationUsesCoordination() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CloudCoordinationTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let coordinator = RecordingCoordinator()
        let store = FileStore(
            fileManager: fileManager,
            rootURL: root,
            localInboxURL: root.deletingLastPathComponent().appendingPathComponent("Inbox"),
            accessCoordinator: coordinator
        )
        let created = try store.createMarkdown(named: "Note", in: root)
        try store.writeText("body", to: created)
        _ = try store.readText(at: created)
        _ = try store.contents(of: root)
        let node = DocumentNode(url: created, kind: .markdown, modifiedAt: .now)
        let renamed = try store.rename(node, to: "Renamed")
        let external = root.deletingLastPathComponent().appendingPathComponent("External-\(UUID().uuidString).md")
        try Data("external".utf8).write(to: external)
        defer { try? fileManager.removeItem(at: external) }
        _ = try store.importFile(from: external, to: root)
        try store.delete(DocumentNode(url: renamed, kind: .markdown, modifiedAt: .now))
        expect(coordinator.readCount >= 2, "scans and reads must coordinate")
        expect(coordinator.writeCount >= 3, "creates, writes, and deletes must coordinate")
        expect(coordinator.readWriteCount == 1, "imports must coordinate source and destination together")
        expect(coordinator.moveCount == 1, "renames and moves must coordinate both URLs")
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

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [ICloudLibraryEvent] = []
    var events: [ICloudLibraryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }
    func append(_ event: ICloudLibraryEvent) {
        lock.lock()
        storedEvents.append(event)
        lock.unlock()
    }
}

private final class FakeICloudRuntime: ICloudContainerRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var storedContainerURL: URL?
    private var storedIdentity: String?
    private var storedStatus = ICloudItemStatus(
        isUbiquitous: false,
        isDownloaded: true,
        isDownloading: false,
        downloadErrorDescription: nil
    )
    private var storedCreatedDirectories: [URL] = []
    private var storedDownloadRequests: [URL] = []

    init(containerURL: URL?, identity: String?) {
        storedContainerURL = containerURL
        storedIdentity = identity
    }

    var identity: String? {
        get { locked { storedIdentity } }
        set { locked { storedIdentity = newValue } }
    }
    var status: ICloudItemStatus {
        get { locked { storedStatus } }
        set { locked { storedStatus = newValue } }
    }
    var createdDirectories: [URL] { locked { storedCreatedDirectories } }
    var downloadRequests: [URL] { locked { storedDownloadRequests } }

    func containerURL(for identifier: String) -> URL? { locked { storedContainerURL } }
    func identityFingerprint() -> String? { locked { storedIdentity } }
    func createDirectory(at url: URL) throws { locked { storedCreatedDirectories.append(url) } }
    func itemStatus(at url: URL) throws -> ICloudItemStatus { locked { storedStatus } }
    func startDownloading(at url: URL) throws {
        locked {
            storedDownloadRequests.append(url)
            storedStatus = ICloudItemStatus(
                isUbiquitous: true,
                isDownloaded: true,
                isDownloading: false,
                downloadErrorDescription: nil
            )
        }
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class RecordingCoordinator: FileAccessCoordinating, @unchecked Sendable {
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var readWriteCount = 0
    private(set) var moveCount = 0

    func read<T>(at url: URL, accessor: (URL) throws -> T) throws -> T {
        readCount += 1
        return try accessor(url)
    }

    func write<T>(at url: URL, options: NSFileCoordinator.WritingOptions, accessor: (URL) throws -> T) throws -> T {
        writeCount += 1
        return try accessor(url)
    }

    func readWrite<T>(reading sourceURL: URL, writing destinationURL: URL, accessor: (URL, URL) throws -> T) throws -> T {
        readWriteCount += 1
        return try accessor(sourceURL, destinationURL)
    }

    func move<T>(from sourceURL: URL, to destinationURL: URL, accessor: (URL, URL) throws -> T) throws -> T {
        moveCount += 1
        return try accessor(sourceURL, destinationURL)
    }
}
