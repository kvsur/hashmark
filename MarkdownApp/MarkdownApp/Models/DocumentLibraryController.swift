import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class DocumentLibraryController: ObservableObject {
    @Published private(set) var storageMode: DocumentStorageMode
    @Published private(set) var state: DocumentLibraryState
    @Published private(set) var identity: DocumentLibraryIdentity
    @Published private(set) var revision = 0
    @Published private(set) var cloudMetadata = ICloudMetadataSnapshot()

    let service: DocumentLibraryService
    let localRootURL: URL
    let localInboxURL: URL

    private let preferenceStore: DocumentStoragePreferenceStore
    private let fileManager: FileManager
    private let cloudContainerService: ICloudContainerService
    private let migrationService: DocumentLibraryMigrationService
    private let conflictResolver: DocumentConflictResolver
    private let metadataMonitor = ICloudMetadataMonitor()
    private var cloudResolution: ICloudContainerResolution?
    private var libraryPresenter: ICloudLibraryPresenter?
    private var identityTask: Task<Void, Never>?
    private var revisionTask: Task<Void, Never>?

    convenience init(fileManager: FileManager = .default) {
        let localRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = localRoot.appendingPathComponent("Inbox", isDirectory: true)
        self.init(
            localRootURL: localRoot,
            localInboxURL: inbox,
            preferenceStore: DocumentStoragePreferenceStore(),
            fileManager: fileManager
        )
    }

    init(
        localRootURL: URL,
        localInboxURL: URL,
        preferenceStore: DocumentStoragePreferenceStore,
        fileManager: FileManager = .default,
        cloudContainerService: ICloudContainerService = ICloudContainerService(),
        migrationService: DocumentLibraryMigrationService? = nil,
        conflictResolver: DocumentConflictResolver? = nil
    ) {
        self.localRootURL = localRootURL
        self.localInboxURL = localInboxURL
        self.preferenceStore = preferenceStore
        self.fileManager = fileManager
        self.cloudContainerService = cloudContainerService
        let localDeviceName: String
#if canImport(UIKit)
        localDeviceName = UIDevice.current.name
#else
        localDeviceName = "Device"
#endif
        let workspaceRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hashmark/DocumentMigration", isDirectory: true)
        self.migrationService = migrationService ?? DocumentLibraryMigrationService(
            workspace: DocumentMigrationWorkspace(rootURL: workspaceRoot),
            fileManager: fileManager,
            coordinator: CoordinatedFileAccessCoordinator(),
            deviceName: localDeviceName
        )
        self.conflictResolver = conflictResolver ?? DocumentConflictResolver(
            fileManager: fileManager,
            deviceName: localDeviceName,
            deviceFallback: LocalizationController.string("Device"),
            conflictLabel: LocalizationController.string("Conflict"),
            recoveredLabel: LocalizationController.string("Recovered")
        )

        // Until the cloud runtime is installed in S4, the only startable mode is local.
        // A future committed cloud preference remains visible as checking rather than silently forking.
        let committedMode = preferenceStore.loadMode()
        storageMode = committedMode
        state = committedMode == .local ? .localReady : .checkingCloud
        identity = DocumentLibraryIdentity(mode: committedMode, rootURL: localRootURL)
        service = DocumentLibraryService(
            store: FileStore(
                fileManager: fileManager,
                rootURL: localRootURL,
                localInboxURL: localInboxURL,
                accessCoordinator: DirectFileAccessCoordinator(),
                defaultDocumentName: LocalizationController.string("Untitled")
            )
        )
    }

    var activeRootURL: URL { identity.rootPath.isEmpty ? localRootURL : URL(fileURLWithPath: identity.rootPath) }

    func start() async {
        startIdentityObservationIfNeeded()
        guard storageMode == .iCloud else {
            await recoverCommittedMigrationIfNeeded()
            if case .failed = state { return }
            state = .localReady
            return
        }
        do {
            let resolution = try await prepareICloud()
            try await installCloudStore(resolution)
            identity = DocumentLibraryIdentity(mode: .iCloud, rootURL: resolution.documentsURL)
            state = .cloudReady
            revision &+= 1
            startCloudMonitoring(at: resolution.documentsURL)
            await recoverCommittedMigrationIfNeeded()
        } catch {
            await service.setMutationsFrozen(true)
            state = .cloudUnavailable(reason: error.localizedDescription)
        }
    }

    func prepareICloud() async throws -> ICloudContainerResolution {
        state = .checkingCloud
        let resolution = try await cloudContainerService.resolve()
        cloudResolution = resolution
        return resolution
    }

    func activateCloudMode(at resolution: ICloudContainerResolution) async throws {
        try await installCloudStore(resolution)
        commit(mode: .iCloud, rootURL: resolution.documentsURL, state: .cloudReady)
        startCloudMonitoring(at: resolution.documentsURL)
    }

    func activateLocalMode() async throws {
        stopCloudMonitoring()
        let store = makeLocalStore()
        try await service.replaceStore(store)
        await service.setMutationsFrozen(false)
        commit(mode: .local, rootURL: localRootURL, state: .localReady)
    }

    func enableICloud() async throws {
        guard storageMode == .local else { return }
        state = .migrating(direction: .enableICloud, progress: 0)
        await service.setMutationsFrozen(true)
        do {
            let resolution = try await prepareICloud()
            state = .migrating(direction: .enableICloud, progress: 0.1)
            var journal = try await migrationService.prepareEnable(
                localRootURL: localRootURL,
                localInboxURL: localInboxURL,
                cloudRootURL: resolution.documentsURL
            )
            state = .migrating(direction: .enableICloud, progress: 0.8)
            try await migrationService.checkpointBeforeModeCommit()
            await service.transitionStore(makeCloudStore(resolution), mutationsFrozen: false)
            commit(mode: .iCloud, rootURL: resolution.documentsURL, state: .cloudReady)
            startCloudMonitoring(at: resolution.documentsURL)
            journal = try await migrationService.markModeCommitted(journal)
            state = .migrating(direction: .enableICloud, progress: 0.95)
            journal = try await migrationService.cleanupLocalSource(
                localRootURL,
                preserving: localInboxURL,
                journal: journal
            )
            state = journal.cleanupDebtRelativePaths.isEmpty
                ? .cloudReady
                : .failed(message: "Some migrated local files could not be cleaned up safely.")
            revision &+= 1
        } catch {
            if storageMode == .local {
                await service.transitionStore(makeLocalStore(), mutationsFrozen: false)
            }
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    func disableICloud() async throws {
        guard storageMode == .iCloud else { return }
        state = .migrating(direction: .disableICloud, progress: 0)
        await service.setMutationsFrozen(true)
        do {
            let resolution: ICloudContainerResolution
            if let cloudResolution {
                resolution = cloudResolution
            } else {
                resolution = try await prepareICloud()
            }
            state = .migrating(direction: .disableICloud, progress: 0.1)
            var journal = try await migrationService.prepareDisable(
                cloudRootURL: resolution.documentsURL,
                localRootURL: localRootURL,
                localInboxURL: localInboxURL,
                cloudService: cloudContainerService
            )
            state = .migrating(direction: .disableICloud, progress: 0.85)
            try await migrationService.checkpointBeforeModeCommit()
            stopCloudMonitoring()
            await service.transitionStore(makeLocalStore(), mutationsFrozen: false)
            commit(mode: .local, rootURL: localRootURL, state: .localReady)
            journal = try await migrationService.markModeCommitted(journal)
            _ = try await migrationService.completeWithoutSourceCleanup(journal)
            state = .localReady
            revision &+= 1
        } catch {
            if storageMode == .iCloud, let resolution = cloudResolution {
                await service.transitionStore(makeCloudStore(resolution), mutationsFrozen: false)
                startCloudMonitoring(at: resolution.documentsURL)
            }
            state = .failed(message: error.localizedDescription)
            throw error
        }
    }

    func setFilePresentationActive(_ active: Bool) {
        if active {
            libraryPresenter?.register()
        } else {
            libraryPresenter?.unregister()
        }
    }

    /// Re-resolves the committed cloud account/container after a temporary
    /// availability or identity failure. The committed mode never changes.
    func retryICloudAccess() async {
        guard storageMode == .iCloud else { return }
        await start()
    }

    func contents(of directory: URL) async throws -> [DocumentNode] {
        try await service.contents(of: directory)
    }

    func tree() async throws -> [DocumentTreeNode] {
        try await service.tree()
    }

    func readText(at url: URL) async throws -> String {
        if storageMode == .iCloud {
            try await cloudContainerService.ensureDownloaded(at: url)
        }
        return try await service.readText(at: url)
    }

    func readExternalText(at url: URL) async throws -> String {
        try await service.readExternalText(at: url)
    }

    func isInsideLibrary(_ url: URL) async -> Bool {
        await service.isInsideLibrary(url)
    }

    func createFolder(named name: String, in directory: URL) async throws -> URL {
        try await mutate { try await service.createFolder(named: name, in: directory) }
    }

    func createMarkdown(named name: String, in directory: URL) async throws -> URL {
        try await mutate { try await service.createMarkdown(named: name, in: directory) }
    }

    func writeText(_ text: String, to url: URL) async throws {
        try await mutate { try await service.writeText(text, to: url) }
    }

    /// A dirty editor calls this after observing distinct remote bytes. The remote
    /// content is durably materialized first; only then does the draft regain the
    /// main path, so neither side can be the sole overwritten copy.
    func preserveRemoteTextAndSaveDraft(_ remoteText: String, draftText: String, at url: URL) async throws -> URL? {
        let preserved = try await conflictResolver.preserveRemoteText(
            remoteText,
            activeDraftText: draftText,
            beside: url
        )
        try await writeText(draftText, to: url)
        return preserved
    }

    func recoverDeletedDraft(_ text: String, formerlyAt url: URL) async throws -> URL {
        let recovered = try await conflictResolver.recoverDraft(text, formerlyAt: url, in: activeRootURL)
        revision &+= 1
        return recovered
    }

    @discardableResult
    func resolveVersionConflicts(at url: URL) async throws -> DocumentConflictResolutionReport {
        let report = try await conflictResolver.resolveVersions(at: url)
        if !report.resolvedVersionIdentifiers.isEmpty { revision &+= 1 }
        return report
    }

    func rename(_ node: DocumentNode, to name: String) async throws -> URL {
        try await mutate { try await service.rename(node, to: name) }
    }

    func delete(_ node: DocumentNode) async throws {
        try await mutate { try await service.delete(node) }
    }

    func importFile(from source: URL, to directory: URL) async throws -> URL {
        try await mutate { try await service.importFile(from: source, to: directory) }
    }

    func move(_ node: DocumentNode, to directory: URL) async throws -> URL {
        try await mutate { try await service.move(node, to: directory) }
    }

    func purgeInbox() async throws {
        try await mutate { try await service.purgeInbox() }
    }

    func publishExternalRevision() {
        revision &+= 1
    }

    func commit(mode: DocumentStorageMode, rootURL: URL, state: DocumentLibraryState) {
        preferenceStore.saveMode(mode)
        storageMode = mode
        self.state = state
        identity = DocumentLibraryIdentity(mode: mode, rootURL: rootURL)
        revision &+= 1
    }

    func updateState(_ state: DocumentLibraryState) {
        self.state = state
    }

    private func installCloudStore(_ resolution: ICloudContainerResolution) async throws {
        await service.transitionStore(makeCloudStore(resolution), mutationsFrozen: false)
    }

    private func makeCloudStore(_ resolution: ICloudContainerResolution) -> FileStore {
        FileStore(
            fileManager: fileManager,
            rootURL: resolution.documentsURL,
            localInboxURL: localInboxURL,
            accessCoordinator: CoordinatedFileAccessCoordinator(),
            defaultDocumentName: LocalizationController.string("Untitled")
        )
    }

    private func makeLocalStore() -> FileStore {
        FileStore(
            fileManager: fileManager,
            rootURL: localRootURL,
            localInboxURL: localInboxURL,
            accessCoordinator: DirectFileAccessCoordinator(),
            defaultDocumentName: LocalizationController.string("Untitled")
        )
    }

    private func startCloudMonitoring(at rootURL: URL) {
        stopCloudMonitoring()
        let presenter = ICloudLibraryPresenter(rootURL: rootURL) { [weak self] event in
            Task { @MainActor [weak self] in await self?.handleCloudEvent(event) }
        }
        libraryPresenter = presenter
        presenter.register()
        metadataMonitor.start(rootURL: rootURL) { [weak self] snapshot in
            guard let self else { return }
            cloudMetadata = snapshot
            if storageMode == .iCloud {
                if let firstError = snapshot.errorDescriptions.first {
                    state = .failed(message: firstError)
                } else {
                    state = snapshot.isSyncing ? .syncing : .cloudReady
                }
            }
        }
    }

    private func stopCloudMonitoring() {
        revisionTask?.cancel()
        revisionTask = nil
        libraryPresenter?.unregister()
        libraryPresenter = nil
        metadataMonitor.stop()
        cloudMetadata = ICloudMetadataSnapshot()
    }

    private func scheduleCloudRevision() {
        revisionTask?.cancel()
        revisionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.publishExternalRevision()
        }
    }

    private func handleCloudEvent(_ event: ICloudLibraryEvent) async {
        if case .versionConflict(let url) = event {
            do {
                _ = try await resolveVersionConflicts(at: url)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
        scheduleCloudRevision()
    }

    private func startIdentityObservationIfNeeded() {
        guard identityTask == nil else { return }
        identityTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSNotification.Name.NSUbiquityIdentityDidChange) {
                guard !Task.isCancelled else { return }
                await self?.handleIdentityChange()
            }
        }
    }

    private func handleIdentityChange() async {
        guard storageMode == .iCloud else { return }
        do {
            try await cloudContainerService.verifyIdentity()
        } catch {
            await service.setMutationsFrozen(true)
            stopCloudMonitoring()
            state = .cloudUnavailable(reason: error.localizedDescription)
        }
    }

    private func recoverCommittedMigrationIfNeeded() async {
        do {
            guard var journal = try await migrationService.loadJournal(),
                  journal.checkpoint == .modeCommitted else { return }
            switch (journal.direction, storageMode) {
            case (.enableICloud, .iCloud):
                journal = try await migrationService.cleanupLocalSource(
                    localRootURL,
                    preserving: localInboxURL,
                    journal: journal
                )
            case (.disableICloud, .local):
                journal = try await migrationService.completeWithoutSourceCleanup(journal)
            default:
                state = .failed(message: "The pending migration does not match the committed storage mode.")
                await service.setMutationsFrozen(true)
                return
            }
            if !journal.cleanupDebtRelativePaths.isEmpty {
                state = .failed(message: "Some migrated local files could not be cleaned up safely.")
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func mutate<T>(_ operation: () async throws -> T) async throws -> T {
        let result = try await operation()
        revision &+= 1
        return result
    }
}
