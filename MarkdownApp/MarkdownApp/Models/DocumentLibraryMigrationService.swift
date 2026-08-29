import Foundation

nonisolated enum DocumentMigrationFaultPoint: String, Sendable {
    case download
    case copy
    case delete
    case crashAfterPrepared
    case crashAfterRecoveryBackup
    case crashAfterMerge
    case crashAfterVerification
    case crashBeforeModeCommit
    case crashAfterModeCommit
    case crashAfterCleanup
}

nonisolated protocol DocumentMigrationFaultChecking: Sendable {
    func checkpoint(_ point: DocumentMigrationFaultPoint) throws
}

nonisolated struct NoDocumentMigrationFaults: DocumentMigrationFaultChecking {
    func checkpoint(_ point: DocumentMigrationFaultPoint) throws {}
}

nonisolated enum DocumentLibraryMigrationError: LocalizedError, Equatable, Sendable {
    case anotherMigrationIsActive
    case journalPathsDoNotMatch
    case recoveryManifestDoesNotMatchSource
    case modeCommitRequired

    var errorDescription: String? {
        switch self {
        case .anotherMigrationIsActive: return "Another document migration is already active."
        case .journalPathsDoNotMatch: return "The pending migration no longer matches the active document roots."
        case .recoveryManifestDoesNotMatchSource: return "The verified recovery inventory does not match the merged source inventory."
        case .modeCommitRequired: return "Local cleanup cannot start before the new storage mode is committed."
        }
    }
}

actor DocumentLibraryMigrationService {
    private let workspace: DocumentMigrationWorkspace
    private let journalStore: DocumentMigrationJournalStore
    private let backupService: DocumentRecoveryBackupService
    private let fileManager: FileManager
    private let coordinator: any FileAccessCoordinating
    private let deviceName: String
    private let faults: any DocumentMigrationFaultChecking

    init(
        workspace: DocumentMigrationWorkspace,
        fileManager: FileManager = .default,
        coordinator: any FileAccessCoordinating,
        deviceName: String,
        faults: any DocumentMigrationFaultChecking = NoDocumentMigrationFaults()
    ) {
        self.workspace = workspace
        journalStore = DocumentMigrationJournalStore(journalURL: workspace.journalURL, fileManager: fileManager)
        backupService = DocumentRecoveryBackupService(fileManager: fileManager, sourceCoordinator: coordinator)
        self.fileManager = fileManager
        self.coordinator = coordinator
        self.deviceName = deviceName
        self.faults = faults
    }

    func prepareEnable(
        localRootURL: URL,
        localInboxURL: URL,
        cloudRootURL: URL
    ) throws -> DocumentMigrationJournal {
        var journal = try loadOrCreateEnableJournal(localRootURL: localRootURL, cloudRootURL: cloudRootURL)
        if journal.checkpoint == .prepared {
            try faults.checkpoint(.crashAfterPrepared)
        }
        if journal.checkpoint == .prepared {
            _ = try backupService.createBackup(
                migrationID: journal.id,
                sourceRootURL: localRootURL,
                backupURL: URL(fileURLWithPath: journal.recoveryBackupPath, isDirectory: true),
                excluding: localInboxURL,
                now: journal.startedAt
            )
            try journal.advance(to: .recoveryBackupCreated)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterRecoveryBackup)
        }
        if journal.checkpoint == .recoveryBackupCreated {
            try faults.checkpoint(.copy)
            let report = try DocumentLibraryMergeService(
                fileManager: fileManager,
                coordinator: coordinator,
                conflictTimestamp: { journal.startedAt },
                conflictDeviceName: deviceName
            ).merge(from: localRootURL, into: cloudRootURL, excluding: localInboxURL)
            journal.completedRelativePaths = report.processedSourceRelativePaths
            try journal.advance(to: .mergeCompleted)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterMerge)
        }
        if journal.checkpoint == .mergeCompleted {
            let backupURL = URL(fileURLWithPath: journal.recoveryBackupPath, isDirectory: true)
            try backupService.verifyBackup(at: backupURL)
            let manifest = try backupService.loadManifest(at: backupURL)
            guard Set(manifest.entries.map(\.relativePath)) == Set(journal.completedRelativePaths) else {
                throw DocumentLibraryMigrationError.recoveryManifestDoesNotMatchSource
            }
            try journal.advance(to: .verificationCompleted)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterVerification)
        }
        return journal
    }

    func prepareDisable(
        cloudRootURL: URL,
        localRootURL: URL,
        localInboxURL: URL,
        cloudService: ICloudContainerService
    ) async throws -> DocumentMigrationJournal {
        var journal = try loadOrCreateJournal(
            direction: .disableICloud,
            sourceRootURL: cloudRootURL,
            destinationRootURL: localRootURL
        )
        if journal.checkpoint == .prepared {
            try faults.checkpoint(.crashAfterPrepared)
        }
        if journal.checkpoint == .prepared {
            for url in try markdownFiles(in: cloudRootURL) {
                try faults.checkpoint(.download)
                try await cloudService.ensureDownloaded(at: url)
            }
            _ = try backupService.createBackup(
                migrationID: journal.id,
                sourceRootURL: cloudRootURL,
                backupURL: URL(fileURLWithPath: journal.recoveryBackupPath, isDirectory: true),
                excluding: nil,
                now: journal.startedAt
            )
            try journal.advance(to: .recoveryBackupCreated)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterRecoveryBackup)
        }
        if journal.checkpoint == .recoveryBackupCreated {
            try faults.checkpoint(.copy)
            let report = try DocumentLibraryMergeService(
                fileManager: fileManager,
                coordinator: coordinator,
                conflictTimestamp: { journal.startedAt },
                conflictDeviceName: deviceName
            ).merge(
                from: cloudRootURL,
                into: localRootURL,
                reserving: [localInboxURL]
            )
            journal.completedRelativePaths = report.processedSourceRelativePaths
            try journal.advance(to: .mergeCompleted)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterMerge)
        }
        if journal.checkpoint == .mergeCompleted {
            let backupURL = URL(fileURLWithPath: journal.recoveryBackupPath, isDirectory: true)
            try backupService.verifyBackup(at: backupURL)
            let manifest = try backupService.loadManifest(at: backupURL)
            guard Set(manifest.entries.map(\.relativePath)) == Set(journal.completedRelativePaths) else {
                throw DocumentLibraryMigrationError.recoveryManifestDoesNotMatchSource
            }
            try journal.advance(to: .verificationCompleted)
            try journalStore.save(journal)
            try faults.checkpoint(.crashAfterVerification)
        }
        return journal
    }

    func checkpointBeforeModeCommit() throws { try faults.checkpoint(.crashBeforeModeCommit) }

    func markModeCommitted(_ journal: DocumentMigrationJournal) throws -> DocumentMigrationJournal {
        var journal = journal
        try journal.advance(to: .modeCommitted)
        try journalStore.save(journal)
        try faults.checkpoint(.crashAfterModeCommit)
        return journal
    }

    func cleanupLocalSource(
        _ localRootURL: URL,
        preserving localInboxURL: URL,
        journal: DocumentMigrationJournal
    ) throws -> DocumentMigrationJournal {
        guard journal.checkpoint == .modeCommitted || journal.checkpoint == .cleanupCompleted else {
            throw DocumentLibraryMigrationError.modeCommitRequired
        }
        if journal.checkpoint == .cleanupCompleted { return journal }
        var journal = journal
        var debt: [String] = []
        let urls = try markdownAndEmptyDirectories(in: localRootURL, excluding: localInboxURL)
        for url in urls {
            do {
                try faults.checkpoint(.delete)
                try fileManager.removeItem(at: url)
            } catch {
                debt.append(relativePath(of: url, under: localRootURL))
            }
        }
        journal.cleanupDebtRelativePaths = debt.sorted()
        if debt.isEmpty { try journal.advance(to: .cleanupCompleted) }
        try journalStore.save(journal)
        if journal.checkpoint == .cleanupCompleted {
            try faults.checkpoint(.crashAfterCleanup)
        }
        return journal
    }

    func completeWithoutSourceCleanup(_ journal: DocumentMigrationJournal) throws -> DocumentMigrationJournal {
        var journal = journal
        try journal.advance(to: .cleanupCompleted)
        try journalStore.save(journal)
        try faults.checkpoint(.crashAfterCleanup)
        return journal
    }

    func loadJournal() throws -> DocumentMigrationJournal? { try journalStore.load() }

    private func loadOrCreateEnableJournal(localRootURL: URL, cloudRootURL: URL) throws -> DocumentMigrationJournal {
        try loadOrCreateJournal(direction: .enableICloud, sourceRootURL: localRootURL, destinationRootURL: cloudRootURL)
    }

    private func loadOrCreateJournal(
        direction: DocumentMigrationDirection,
        sourceRootURL: URL,
        destinationRootURL: URL
    ) throws -> DocumentMigrationJournal {
        if let existing = try journalStore.load() {
            if existing.checkpoint == .cleanupCompleted {
                try DocumentMigrationJournalStore(
                    journalURL: workspace.historyJournalURL(for: existing.id),
                    fileManager: fileManager
                ).save(existing)
                try journalStore.clear()
            } else {
                guard existing.direction == direction else { throw DocumentLibraryMigrationError.anotherMigrationIsActive }
                guard existing.sourceRootPath == sourceRootURL.standardizedFileURL.path,
                      existing.destinationRootPath == destinationRootURL.standardizedFileURL.path else {
                    throw DocumentLibraryMigrationError.journalPathsDoNotMatch
                }
                return existing
            }
        }
        let id = UUID()
        let journal = DocumentMigrationJournal(
            id: id,
            direction: direction,
            sourceRootURL: sourceRootURL,
            destinationRootURL: destinationRootURL,
            recoveryBackupURL: workspace.recoveryBackupURL(for: id)
        )
        try journalStore.save(journal)
        return journal
    }

    private func markdownFiles(in root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true && url.pathExtension.lowercased() == "md" ? url : nil
        }
    }

    private func markdownAndEmptyDirectories(in root: URL, excluding excluded: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let excludedPath = excluded.standardizedFileURL.path
        var files: [URL] = []
        var directories: [URL] = []
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            if path == excludedPath || path.hasPrefix(excludedPath + "/") {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true { directories.append(url) }
            else if values.isRegularFile == true, url.pathExtension.lowercased() == "md" { files.append(url) }
        }
        return files + directories.sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }
}
