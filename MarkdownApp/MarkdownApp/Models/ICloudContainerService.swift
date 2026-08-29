import Foundation

nonisolated struct ICloudContainerResolution: Equatable, Sendable {
    let containerURL: URL
    let documentsURL: URL
    let identityFingerprint: String?
}

nonisolated struct ICloudItemStatus: Equatable, Sendable {
    let isUbiquitous: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadErrorDescription: String?
}

nonisolated enum ICloudItemReadiness: Equatable, Sendable {
    case localOrDownloaded
    case downloading
}

nonisolated enum ICloudContainerError: LocalizedError, Equatable, Sendable {
    case unavailable
    case identityChanged
    case downloadFailed(String)
    case downloadTimedOut(URL)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "iCloud Drive is unavailable for this account or device."
        case .identityChanged:
            return "The iCloud account changed while documents were in use."
        case .downloadFailed(let message):
            return message
        case .downloadTimedOut:
            return "The document could not be downloaded in time."
        }
    }
}

nonisolated protocol ICloudContainerRuntime: Sendable {
    func containerURL(for identifier: String) -> URL?
    func identityFingerprint() -> String?
    func createDirectory(at url: URL) throws
    func itemStatus(at url: URL) throws -> ICloudItemStatus
    func startDownloading(at url: URL) throws
}

nonisolated struct SystemICloudContainerRuntime: ICloudContainerRuntime, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func containerURL(for identifier: String) -> URL? {
        fileManager.url(forUbiquityContainerIdentifier: identifier)
    }

    func identityFingerprint() -> String? {
        fileManager.ubiquityIdentityToken.map { String(describing: $0) }
    }

    func createDirectory(at url: URL) throws {
        let coordinator = CoordinatedFileAccessCoordinator()
        try coordinator.write(at: url.deletingLastPathComponent(), options: .forMerging) { _ in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    func itemStatus(at url: URL) throws -> ICloudItemStatus {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingErrorKey
        ])
        return ICloudItemStatus(
            isUbiquitous: values.isUbiquitousItem ?? false,
            isDownloaded: values.ubiquitousItemDownloadingStatus == .current,
            isDownloading: values.ubiquitousItemIsDownloading ?? false,
            downloadErrorDescription: values.ubiquitousItemDownloadingError?.localizedDescription
        )
    }

    func startDownloading(at url: URL) throws {
        try fileManager.startDownloadingUbiquitousItem(at: url)
    }
}

actor ICloudContainerService {
    static let defaultContainerIdentifier = "iCloud.com.kvsur.MarkdownApp"

    private let runtime: any ICloudContainerRuntime
    private let containerIdentifier: String
    private var resolution: ICloudContainerResolution?

    init(
        containerIdentifier: String = ICloudContainerService.defaultContainerIdentifier,
        runtime: any ICloudContainerRuntime = SystemICloudContainerRuntime()
    ) {
        self.containerIdentifier = containerIdentifier
        self.runtime = runtime
    }

    func resolve() throws -> ICloudContainerResolution {
        guard let containerURL = runtime.containerURL(for: containerIdentifier) else {
            throw ICloudContainerError.unavailable
        }
        let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
        try runtime.createDirectory(at: documentsURL)
        let value = ICloudContainerResolution(
            containerURL: containerURL,
            documentsURL: documentsURL,
            identityFingerprint: runtime.identityFingerprint()
        )
        resolution = value
        return value
    }

    func verifyIdentity() throws {
        guard let resolution else { throw ICloudContainerError.unavailable }
        guard resolution.identityFingerprint == runtime.identityFingerprint() else {
            throw ICloudContainerError.identityChanged
        }
    }

    func readiness(of url: URL) throws -> ICloudItemReadiness {
        let status = try runtime.itemStatus(at: url)
        if !status.isUbiquitous || status.isDownloaded { return .localOrDownloaded }
        if let error = status.downloadErrorDescription {
            throw ICloudContainerError.downloadFailed(error)
        }
        return .downloading
    }

    func ensureDownloaded(at url: URL, timeout: TimeInterval = 30) async throws {
        try verifyIdentity()
        if try readiness(of: url) == .localOrDownloaded { return }
        try runtime.startDownloading(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if try readiness(of: url) == .localOrDownloaded { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw ICloudContainerError.downloadTimedOut(url)
    }
}
