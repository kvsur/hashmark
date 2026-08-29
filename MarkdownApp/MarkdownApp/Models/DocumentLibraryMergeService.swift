import Foundation
import CryptoKit

nonisolated struct DocumentLibraryMergeReport: Equatable, Sendable {
    var processedSourceRelativePaths: [String] = []
    var copiedRelativePaths: [String] = []
    var deduplicatedRelativePaths: [String] = []
    var conflictRelativePaths: [String] = []
    var createdDirectoryRelativePaths: [String] = []
}

nonisolated enum DocumentLibraryMergeError: LocalizedError, Equatable, Sendable {
    case sourceIsNotDirectory(URL)
    case destinationIsNotDirectory(URL)
    case symbolicLinkNotSupported(URL)
    case invalidRelativePath(URL)
    case copiedBytesMismatch(String)

    var errorDescription: String? {
        switch self {
        case .sourceIsNotDirectory:
            return "The merge source is not a directory."
        case .destinationIsNotDirectory:
            return "The merge destination is not a directory."
        case .symbolicLinkNotSupported:
            return "Symbolic links are not supported in the document library."
        case .invalidRelativePath:
            return "A merge item escaped its source or destination root."
        case .copiedBytesMismatch(let path):
            return "The copied document failed byte verification at \(path)."
        }
    }
}

nonisolated struct DocumentLibraryMergeService: @unchecked Sendable {
    private let fileManager: FileManager
    private let coordinator: any FileAccessCoordinating
    private let conflictURLFactory: DocumentConflictURLFactory

    init(
        fileManager: FileManager = .default,
        coordinator: any FileAccessCoordinating,
        conflictTimestamp: @escaping () -> Date = Date.init,
        conflictDeviceName: String
    ) {
        self.fileManager = fileManager
        self.coordinator = coordinator
        conflictURLFactory = DocumentConflictURLFactory(
            fileManager: fileManager,
            timestamp: conflictTimestamp,
            deviceName: conflictDeviceName
        )
    }

    func merge(
        from sourceRootURL: URL,
        into destinationRootURL: URL,
        excluding excludedURL: URL? = nil,
        reserving reservedDestinationURLs: [URL] = []
    ) throws -> DocumentLibraryMergeReport {
        guard try isDirectory(sourceRootURL) else {
            throw DocumentLibraryMergeError.sourceIsNotDirectory(sourceRootURL)
        }
        guard try isDirectory(destinationRootURL) else {
            throw DocumentLibraryMergeError.destinationIsNotDirectory(destinationRootURL)
        }
        var report = DocumentLibraryMergeReport()
        try mergeDirectory(
            sourceRootURL,
            into: destinationRootURL,
            sourceRootURL: sourceRootURL,
            destinationRootURL: destinationRootURL,
            excludedPath: excludedURL?.standardizedFileURL.path,
            reservedDestinationPaths: Set(reservedDestinationURLs.map { $0.standardizedFileURL.path }),
            report: &report
        )
        report.copiedRelativePaths.sort()
        report.processedSourceRelativePaths.sort()
        report.deduplicatedRelativePaths.sort()
        report.conflictRelativePaths.sort()
        report.createdDirectoryRelativePaths.sort()
        return report
    }

    private func mergeDirectory(
        _ sourceDirectory: URL,
        into requestedDestination: URL,
        sourceRootURL: URL,
        destinationRootURL: URL,
        excludedPath: String?,
        reservedDestinationPaths: Set<String>,
        report: inout DocumentLibraryMergeReport
    ) throws {
        try rejectSymbolicLink(sourceDirectory)
        let destinationDirectory: URL
        if fileManager.fileExists(atPath: requestedDestination.path) {
            try rejectSymbolicLink(requestedDestination)
            if try isDirectory(requestedDestination) {
                destinationDirectory = requestedDestination
            } else {
                destinationDirectory = uniqueConflictURL(for: requestedDestination, isDirectory: true)
                try createDirectory(destinationDirectory)
                report.createdDirectoryRelativePaths.append(try relativePath(of: destinationDirectory, under: destinationRootURL))
                report.conflictRelativePaths.append(try relativePath(of: destinationDirectory, under: destinationRootURL))
            }
        } else {
            try createDirectory(requestedDestination)
            destinationDirectory = requestedDestination
            report.createdDirectoryRelativePaths.append(try relativePath(of: destinationDirectory, under: destinationRootURL))
        }

        let children = try coordinator.read(at: sourceDirectory) { coordinatedSource in
            try fileManager.contentsOfDirectory(
                at: coordinatedSource,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        for sourceURL in children {
            let sourcePath = sourceURL.standardizedFileURL.path
            if let excludedPath,
               sourcePath == excludedPath || sourcePath.hasPrefix(excludedPath + "/") {
                continue
            }
            try rejectSymbolicLink(sourceURL)
            if try isDirectory(sourceURL) {
                var requested = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                if reservedDestinationPaths.contains(requested.standardizedFileURL.path) {
                    requested = uniqueConflictURL(for: requested, isDirectory: true)
                    report.conflictRelativePaths.append(try relativePath(of: requested, under: destinationRootURL))
                }
                try mergeDirectory(
                    sourceURL,
                    into: requested,
                    sourceRootURL: sourceRootURL,
                    destinationRootURL: destinationRootURL,
                    excludedPath: excludedPath,
                    reservedDestinationPaths: reservedDestinationPaths,
                    report: &report
                )
            } else if sourceURL.pathExtension.lowercased() == "md" {
                var requested = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                if reservedDestinationPaths.contains(requested.standardizedFileURL.path) {
                    requested = uniqueConflictURL(for: requested, isDirectory: false)
                    report.conflictRelativePaths.append(try relativePath(of: requested, under: destinationRootURL))
                }
                try mergeFile(
                    sourceURL,
                    into: requested,
                    sourceRootURL: sourceRootURL,
                    destinationRootURL: destinationRootURL,
                    report: &report
                )
            }
        }
    }

    private func mergeFile(
        _ sourceURL: URL,
        into requestedDestination: URL,
        sourceRootURL: URL,
        destinationRootURL: URL,
        report: inout DocumentLibraryMergeReport
    ) throws {
        let sourceRelativePath = try relativePath(of: sourceURL, under: sourceRootURL)
        report.processedSourceRelativePaths.append(sourceRelativePath)
        let destinationURL: URL
        if fileManager.fileExists(atPath: requestedDestination.path) {
            try rejectSymbolicLink(requestedDestination)
            if !(try isDirectory(requestedDestination)), try filesAreIdentical(sourceURL, requestedDestination) {
                report.deduplicatedRelativePaths.append(sourceRelativePath)
                return
            }
            destinationURL = uniqueConflictURL(for: requestedDestination, isDirectory: false)
            report.conflictRelativePaths.append(try relativePath(of: destinationURL, under: destinationRootURL))
        } else {
            destinationURL = requestedDestination
        }

        let sourceData = try coordinator.read(at: sourceURL) { try Data(contentsOf: $0) }
        try coordinator.readWrite(reading: sourceURL, writing: destinationURL) { coordinatedSource, coordinatedDestination in
            let data = try Data(contentsOf: coordinatedSource)
            try fileManager.createDirectory(
                at: coordinatedDestination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: coordinatedDestination, options: .atomic)
        }
        let destinationData = try coordinator.read(at: destinationURL) { try Data(contentsOf: $0) }
        guard Self.sha256(sourceData) == Self.sha256(destinationData) else {
            throw DocumentLibraryMergeError.copiedBytesMismatch(sourceRelativePath)
        }
        report.copiedRelativePaths.append(try relativePath(of: destinationURL, under: destinationRootURL))
    }

    private func uniqueConflictURL(for requestedURL: URL, isDirectory: Bool) -> URL {
        conflictURLFactory.uniqueURL(for: requestedURL, isDirectory: isDirectory)
    }

    private func filesAreIdentical(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsData = try coordinator.read(at: lhs) { try Data(contentsOf: $0) }
        let rhsData = try coordinator.read(at: rhs) { try Data(contentsOf: $0) }
        return Self.sha256(lhsData) == Self.sha256(rhsData)
    }

    private func createDirectory(_ url: URL) throws {
        let name = url.lastPathComponent
        try coordinator.write(at: url.deletingLastPathComponent(), options: .forMerging) { coordinatedParent in
            try fileManager.createDirectory(
                at: coordinatedParent.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        try coordinator.read(at: url) { coordinatedURL in
            try coordinatedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        let isSymbolicLink = try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
        if isSymbolicLink { throw DocumentLibraryMergeError.symbolicLinkNotSupported(url) }
    }

    private func relativePath(of url: URL, under rootURL: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath + "/") else {
            throw DocumentLibraryMergeError.invalidRelativePath(url)
        }
        return String(itemPath.dropFirst(rootPath.count + 1))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
