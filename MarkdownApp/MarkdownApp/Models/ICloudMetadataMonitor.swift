import Foundation

nonisolated struct ICloudMetadataSnapshot: Equatable, Sendable {
    var itemCount = 0
    var downloadingCount = 0
    var uploadingCount = 0
    var errorDescriptions: [String] = []

    var isSyncing: Bool { downloadingCount > 0 || uploadingCount > 0 }
}

@MainActor
final class ICloudMetadataMonitor: NSObject {
    private var query: NSMetadataQuery?
    private var handler: ((ICloudMetadataSnapshot) -> Void)?

    func start(rootURL: URL, handler: @escaping (ICloudMetadataSnapshot) -> Void) {
        stop()
        self.handler = handler
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, rootURL.path)
        query.notificationBatchingInterval = 0.35
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(queryChanged), name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(queryChanged), name: .NSMetadataQueryDidUpdate, object: query)
        self.query = query
        query.start()
    }

    func stop() {
        query?.stop()
        NotificationCenter.default.removeObserver(self)
        query = nil
        handler = nil
    }

    @objc private func queryChanged(_ notification: Notification) {
        publishSnapshot()
    }

    private func publishSnapshot() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var snapshot = ICloudMetadataSnapshot()
        for case let item as NSMetadataItem in query.results {
            snapshot.itemCount += 1
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? NSNumber)?.boolValue == true {
                snapshot.downloadingCount += 1
            }
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? NSNumber)?.boolValue == true {
                snapshot.uploadingCount += 1
            }
            if let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? Error {
                snapshot.errorDescriptions.append(error.localizedDescription)
            }
            if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? Error {
                snapshot.errorDescriptions.append(error.localizedDescription)
            }
        }
        handler?(snapshot)
    }
}
