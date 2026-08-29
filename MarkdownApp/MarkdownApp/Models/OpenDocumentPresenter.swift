import Foundation

nonisolated enum OpenDocumentEvent: Equatable, Sendable {
    case changed(URL)
    case moved(from: URL, to: URL)
    case deleted(URL)
    case versionConflict(URL)
}

/// Presents exactly one open Markdown file. Directory-level presentation keeps
/// lists fresh; this presenter owns editor-specific identity and deletion events.
nonisolated final class OpenDocumentPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private let eventHandler: @Sendable (OpenDocumentEvent) -> Void
    private let operationQueue: OperationQueue
    private let lock = NSLock()
    private var itemURL: URL?
    private var registered = false

    init(url: URL, eventHandler: @escaping @Sendable (OpenDocumentEvent) -> Void) {
        itemURL = url
        self.eventHandler = eventHandler
        operationQueue = OperationQueue()
        operationQueue.name = "com.kvsur.MarkdownApp.OpenDocumentPresenter"
        operationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    var presentedItemURL: URL? { locked { itemURL } }
    var presentedItemOperationQueue: OperationQueue { operationQueue }

    func register() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        NSFileCoordinator.addFilePresenter(self)
        registered = true
    }

    func unregister() {
        lock.lock()
        defer { lock.unlock() }
        guard registered else { return }
        NSFileCoordinator.removeFilePresenter(self)
        registered = false
    }

    func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        eventHandler(.changed(url))
    }

    func presentedItemDidMove(to newURL: URL) {
        let oldURL = locked { () -> URL? in
            let oldURL = itemURL
            itemURL = newURL
            return oldURL
        }
        guard let oldURL else { return }
        eventHandler(.moved(from: oldURL, to: newURL))
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        guard let url = presentedItemURL else {
            completionHandler(nil)
            return
        }
        eventHandler(.deleted(url))
        completionHandler(nil)
    }

    func presentedItemDidGain(_ version: NSFileVersion) {
        guard let url = presentedItemURL else { return }
        eventHandler(.versionConflict(url))
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
