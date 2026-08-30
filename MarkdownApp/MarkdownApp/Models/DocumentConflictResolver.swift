import Foundation
import CryptoKit

nonisolated struct DocumentVersionSnapshot: Equatable, Sendable {
    let identifier: String
    let data: Data
    let modifiedAt: Date?
}

nonisolated protocol DocumentVersionAccessing: Sendable {
    func unresolvedVersions(at url: URL) throws -> [DocumentVersionSnapshot]
    func finishResolution(at url: URL, identifiers: Set<String>) throws
}

/// The Foundation adapter deliberately keeps NSFileVersion objects inside one
/// synchronous operation. The resolver only receives immutable byte snapshots.
nonisolated final class FoundationDocumentVersionAccess: DocumentVersionAccessing, @unchecked Sendable {
    private let coordinator: any FileAccessCoordinating

    init(coordinator: any FileAccessCoordinating = CoordinatedFileAccessCoordinator()) {
        self.coordinator = coordinator
    }

    func unresolvedVersions(at url: URL) throws -> [DocumentVersionSnapshot] {
        try (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
            DocumentVersionSnapshot(
                identifier: String(describing: version.persistentIdentifier),
                data: try coordinator.read(at: version.url) { try Data(contentsOf: $0) },
                modifiedAt: version.modificationDate
            )
        }
    }

    func finishResolution(at url: URL, identifiers: Set<String>) throws {
        let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        for version in versions where identifiers.contains(String(describing: version.persistentIdentifier)) {
            version.isResolved = true
        }
        guard (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty else { return }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}

nonisolated struct DocumentConflictResolutionReport: Equatable, Sendable {
    var materializedURLs: [URL] = []
    var deduplicatedVersionIdentifiers: [String] = []
    var resolvedVersionIdentifiers: [String] = []
}

actor DocumentConflictResolver {
    private let fileManager: FileManager
    private let coordinator: any FileAccessCoordinating
    private let versionAccess: any DocumentVersionAccessing
    private let URLFactory: DocumentConflictURLFactory
    private let conflictLabel: String
    private let recoveredLabel: String

    init(
        fileManager: FileManager = .default,
        coordinator: any FileAccessCoordinating = CoordinatedFileAccessCoordinator(),
        versionAccess: any DocumentVersionAccessing = FoundationDocumentVersionAccess(),
        deviceName: String,
        deviceFallback: String = "Device",
        conflictLabel: String = "Conflict",
        recoveredLabel: String = "Recovered",
        timestamp: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.coordinator = coordinator
        self.versionAccess = versionAccess
        URLFactory = DocumentConflictURLFactory(
            fileManager: fileManager,
            timestamp: timestamp,
            deviceName: deviceName,
            deviceFallback: deviceFallback
        )
        self.conflictLabel = conflictLabel
        self.recoveredLabel = recoveredLabel
    }

    /// Preserves remote bytes before the caller restores its in-memory draft as
    /// the main file. Identical bytes never create a redundant sibling.
    func preserveRemoteText(_ remoteText: String, activeDraftText: String, beside url: URL) throws -> URL? {
        let remoteData = Data(remoteText.utf8)
        guard remoteData != Data(activeDraftText.utf8) else { return nil }
        return try writeSibling(remoteData, basedOn: url, label: conflictLabel)
    }

    /// A dirty draft whose backing file was remotely deleted is recovered at the
    /// active library root. This stays inside iCloud mode, including while offline.
    func recoverDraft(_ text: String, formerlyAt url: URL, in rootURL: URL) throws -> URL {
        let requested = rootURL.appendingPathComponent(url.lastPathComponent)
        return try writeSibling(Data(text.utf8), basedOn: requested, label: recoveredLabel)
    }

    func resolveVersions(at url: URL) throws -> DocumentConflictResolutionReport {
        let snapshots = try versionAccess.unresolvedVersions(at: url).sorted {
            ($0.modifiedAt ?? .distantPast, $0.identifier) < ($1.modifiedAt ?? .distantPast, $1.identifier)
        }
        guard !snapshots.isEmpty else { return DocumentConflictResolutionReport() }

        let currentData = try coordinator.read(at: url) { try Data(contentsOf: $0) }
        var seenHashes = Set([Self.sha256(currentData)])
        var report = DocumentConflictResolutionReport()
        for snapshot in snapshots {
            let hash = Self.sha256(snapshot.data)
            if seenHashes.insert(hash).inserted {
                let destination = try writeSibling(snapshot.data, basedOn: url, label: conflictLabel)
                report.materializedURLs.append(destination)
            } else {
                report.deduplicatedVersionIdentifiers.append(snapshot.identifier)
            }
            report.resolvedVersionIdentifiers.append(snapshot.identifier)
        }

        try versionAccess.finishResolution(at: url, identifiers: Set(report.resolvedVersionIdentifiers))
        return report
    }

    private func writeSibling(_ data: Data, basedOn requestedURL: URL, label: String) throws -> URL {
        let requestedName = requestedURL.lastPathComponent
        let destination = try coordinator.write(
            at: requestedURL.deletingLastPathComponent(),
            options: .forMerging
        ) { coordinatedParent -> URL in
            try fileManager.createDirectory(at: coordinatedParent, withIntermediateDirectories: true)
            let coordinatedRequest = coordinatedParent.appendingPathComponent(requestedName)
            let uniqueURL = URLFactory.uniqueURL(for: coordinatedRequest, label: label)
            // The parent-directory coordinator serializes compliant creators, so
            // the collision check above and this atomic write form one operation.
            try data.write(to: uniqueURL, options: .atomic)
            return uniqueURL
        }
        let copied = try coordinator.read(at: destination) { try Data(contentsOf: $0) }
        guard Self.sha256(data) == Self.sha256(copied) else { throw CocoaError(.fileWriteUnknown) }
        return destination
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
