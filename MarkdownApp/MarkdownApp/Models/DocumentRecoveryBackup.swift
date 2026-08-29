import Foundation
import CryptoKit

nonisolated struct DocumentRecoveryBackupManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Entry: Codable, Equatable, Sendable {
        let relativePath: String
        let byteCount: Int
        let sha256: String
    }

    let schemaVersion: Int
    let migrationID: UUID
    let sourceRootPath: String
    let createdAt: Date
    let directories: [String]
    let entries: [Entry]
}

nonisolated enum DocumentRecoveryBackupError: LocalizedError, Equatable, Sendable {
    case backupAlreadyExists(URL)
    case sourceIsNotDirectory(URL)
    case symbolicLinkNotSupported(URL)
    case invalidRelativePath(URL)
    case manifestMismatch(String)

    var errorDescription: String? {
        switch self {
        case .backupAlreadyExists:
            return "A recovery backup already exists for this migration."
        case .sourceIsNotDirectory:
            return "The migration source is not a readable directory."
        case .symbolicLinkNotSupported:
            return "Symbolic links are not supported in the document library."
        case .invalidRelativePath:
            return "A document escaped the migration source root."
        case .manifestMismatch(let path):
            return "The recovery backup does not match its manifest at \(path)."
        }
    }
}

nonisolated struct DocumentRecoveryBackupService: @unchecked Sendable {
    static let payloadDirectoryName = "Documents"
    static let manifestFilename = "manifest.json"

    private let fileManager: FileManager
    private let sourceCoordinator: any FileAccessCoordinating

    init(
        fileManager: FileManager = .default,
        sourceCoordinator: any FileAccessCoordinating = DirectFileAccessCoordinator()
    ) {
        self.fileManager = fileManager
        self.sourceCoordinator = sourceCoordinator
    }

    @discardableResult
    func createBackup(
        migrationID: UUID,
        sourceRootURL: URL,
        backupURL: URL,
        excluding excludedURL: URL?,
        now: Date = Date()
    ) throws -> DocumentRecoveryBackupManifest {
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            throw DocumentRecoveryBackupError.backupAlreadyExists(backupURL)
        }
        let sourceValues = try sourceRootURL.resourceValues(forKeys: [.isDirectoryKey])
        guard sourceValues.isDirectory == true else {
            throw DocumentRecoveryBackupError.sourceIsNotDirectory(sourceRootURL)
        }

        let payloadURL = backupURL.appendingPathComponent(Self.payloadDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: payloadURL, withIntermediateDirectories: true)

        do {
            let inventory = try sourceCoordinator.read(at: sourceRootURL) { coordinatedSource in
                try copyInventory(from: coordinatedSource, to: payloadURL, excluding: excludedURL)
            }
            let manifest = DocumentRecoveryBackupManifest(
                schemaVersion: DocumentRecoveryBackupManifest.currentSchemaVersion,
                migrationID: migrationID,
                sourceRootPath: sourceRootURL.standardizedFileURL.path,
                createdAt: now,
                directories: inventory.directories.sorted(),
                entries: inventory.entries.sorted { $0.relativePath < $1.relativePath }
            )
            let data = try JSONEncoder.recoveryBackup.encode(manifest)
            try data.write(
                to: backupURL.appendingPathComponent(Self.manifestFilename),
                options: .atomic
            )
            try verifyBackup(at: backupURL)
            // 这是迁移期间保留的冗余恢复副本，云端或本地已保有已验证主副本；
            // 排除设备备份可避免把整套文档再重复上传一次，但不会删除本机恢复材料。
            try excludeFromDeviceBackup(backupURL)
            return manifest
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
    }

    func loadManifest(at backupURL: URL) throws -> DocumentRecoveryBackupManifest {
        let data = try Data(contentsOf: backupURL.appendingPathComponent(Self.manifestFilename))
        return try JSONDecoder.recoveryBackup.decode(DocumentRecoveryBackupManifest.self, from: data)
    }

    func verifyBackup(at backupURL: URL) throws {
        let manifest = try loadManifest(at: backupURL)
        guard manifest.schemaVersion == DocumentRecoveryBackupManifest.currentSchemaVersion else {
            throw DocumentRecoveryBackupError.manifestMismatch(Self.manifestFilename)
        }
        let payloadURL = backupURL.appendingPathComponent(Self.payloadDirectoryName, isDirectory: true)
        for directory in manifest.directories {
            var isDirectory: ObjCBool = false
            let url = payloadURL.appendingPathComponent(directory, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw DocumentRecoveryBackupError.manifestMismatch(directory)
            }
        }
        for entry in manifest.entries {
            let url = payloadURL.appendingPathComponent(entry.relativePath)
            let data = try Data(contentsOf: url)
            guard data.count == entry.byteCount, Self.sha256(data) == entry.sha256 else {
                throw DocumentRecoveryBackupError.manifestMismatch(entry.relativePath)
            }
        }
    }

    private func copyInventory(
        from sourceRootURL: URL,
        to payloadURL: URL,
        excluding excludedURL: URL?
    ) throws -> (directories: [String], entries: [DocumentRecoveryBackupManifest.Entry]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: sourceRootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            throw DocumentRecoveryBackupError.sourceIsNotDirectory(sourceRootURL)
        }
        let excludedPath = excludedURL?.resolvingSymlinksInPath().standardizedFileURL.path
        var directories: [String] = []
        var entries: [DocumentRecoveryBackupManifest.Entry] = []

        for case let sourceURL as URL in enumerator {
            let resolvedPath = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
            if let excludedPath, resolvedPath == excludedPath || resolvedPath.hasPrefix(excludedPath + "/") {
                enumerator.skipDescendants()
                continue
            }
            let values = try sourceURL.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                throw DocumentRecoveryBackupError.symbolicLinkNotSupported(sourceURL)
            }
            let relativePath = try Self.relativePath(of: sourceURL, under: sourceRootURL)
            let destinationURL = payloadURL.appendingPathComponent(relativePath)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                directories.append(relativePath)
            } else if values.isRegularFile == true, sourceURL.pathExtension.lowercased() == "md" {
                let data = try Data(contentsOf: sourceURL)
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destinationURL, options: .atomic)
                entries.append(.init(
                    relativePath: relativePath,
                    byteCount: data.count,
                    sha256: Self.sha256(data)
                ))
            }
        }
        return (directories, entries)
    }

    private func excludeFromDeviceBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func relativePath(of url: URL, under rootURL: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath + "/") else {
            throw DocumentRecoveryBackupError.invalidRelativePath(url)
        }
        return String(itemPath.dropFirst(rootPath.count + 1))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    nonisolated static var recoveryBackup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var recoveryBackup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
