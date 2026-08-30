import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

enum ReleaseQAError: LocalizedError, Sendable, Equatable {
    case crash(DocumentMigrationFaultPoint)
    case diskFull
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .crash(let point): return "Simulated termination at \(point.rawValue)."
        case .diskFull: return "The device has no remaining storage."
        case .quotaExceeded: return "The iCloud storage quota is exceeded."
        }
    }
}

final class ReleaseQAFaults: DocumentMigrationFaultChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var armedPoint: DocumentMigrationFaultPoint?
    private let injectedError: ReleaseQAError

    init(_ point: DocumentMigrationFaultPoint, error: ReleaseQAError? = nil) {
        armedPoint = point
        injectedError = error ?? .crash(point)
    }

    func checkpoint(_ point: DocumentMigrationFaultPoint) throws {
        lock.lock()
        defer { lock.unlock() }
        guard armedPoint == point else { return }
        armedPoint = nil
        throw injectedError
    }
}

final class ReleaseQACloudRuntime: ICloudContainerRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var storedContainerURL: URL?
    private var storedIdentity: String?

    init(containerURL: URL?, identity: String? = "release-account") {
        storedContainerURL = containerURL
        storedIdentity = identity
    }

    func update(containerURL: URL?, identity: String?) {
        lock.withLock {
            storedContainerURL = containerURL
            storedIdentity = identity
        }
    }

    func containerURL(for identifier: String) -> URL? { lock.withLock { storedContainerURL } }
    func identityFingerprint() -> String? { lock.withLock { storedIdentity } }
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func itemStatus(at url: URL) throws -> ICloudItemStatus {
        ICloudItemStatus(
            isUbiquitous: false,
            isDownloaded: true,
            isDownloading: false,
            downloadErrorDescription: nil
        )
    }
    func startDownloading(at url: URL) throws {}
}

@MainActor
struct ReleaseQAFixture {
    let baseURL: URL
    let localRootURL: URL
    let inboxURL: URL
    let cloudContainerURL: URL
    let cloudDocumentsURL: URL
    let preferences: DocumentStoragePreferenceStore
    let cloudRuntime: ReleaseQACloudRuntime
    let cloudService: ICloudContainerService
    let migrationService: DocumentLibraryMigrationService

    func makeController() -> DocumentLibraryController {
        DocumentLibraryController(
            localRootURL: localRootURL,
            localInboxURL: inboxURL,
            preferenceStore: preferences,
            cloudContainerService: cloudService,
            migrationService: migrationService
        )
    }
}

@MainActor
func withReleaseQAFixture(
    faults: any DocumentMigrationFaultChecking = NoDocumentMigrationFaults(),
    _ body: (ReleaseQAFixture) async throws -> Void
) async throws {
    let fileManager = FileManager.default
    let base = fileManager.temporaryDirectory
        .appendingPathComponent("DocumentReleaseQATests-\(UUID().uuidString)", isDirectory: true)
    let local = base.appendingPathComponent("Local/Documents", isDirectory: true)
    let inbox = local.appendingPathComponent("Inbox", isDirectory: true)
    let cloudContainer = base.appendingPathComponent("CloudContainer", isDirectory: true)
    let cloudDocuments = cloudContainer.appendingPathComponent("Documents", isDirectory: true)
    try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: cloudDocuments, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: base) }

    let suite = "DocumentReleaseQATests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { throw ReleaseQATestError("missing defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }
    let runtime = ReleaseQACloudRuntime(containerURL: cloudContainer)
    let cloudService = ICloudContainerService(runtime: runtime)
    let migration = DocumentLibraryMigrationService(
        workspace: DocumentMigrationWorkspace(rootURL: base.appendingPathComponent("Application Support/Migration")),
        coordinator: DirectFileAccessCoordinator(),
        deviceName: "Release QA",
        faults: faults
    )
    try await body(
        ReleaseQAFixture(
            baseURL: base,
            localRootURL: local,
            inboxURL: inbox,
            cloudContainerURL: cloudContainer,
            cloudDocumentsURL: cloudDocuments,
            preferences: DocumentStoragePreferenceStore(defaults: defaults),
            cloudRuntime: runtime,
            cloudService: cloudService,
            migrationService: migration
        )
    )
}

struct ReleaseQATestError: Error { let message: String; init(_ message: String) { self.message = message } }

func releaseQAWrite(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
}

func releaseQARead(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

func releaseQAMarkdownURLs(in root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension.lowercased() == "md" else { return nil }
        return url
    }
}

func releaseQAExpect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
    guard try condition() else { fatalError(message) }
}
