import Foundation

nonisolated enum ICloudLibraryEvent: Equatable, Sendable {
    case itemAppeared(URL)
    case itemChanged(URL)
    case itemMoved(from: URL, to: URL)
    case itemDeleted(URL)
    case versionConflict(URL)
    case rootChanged(URL)
}

nonisolated final class ICloudLibraryPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    private let eventHandler: @Sendable (ICloudLibraryEvent) -> Void
    private let operationQueue: OperationQueue
    private let lock = NSLock()
    private var itemURL: URL?
    private var registered = false

    init(rootURL: URL, eventHandler: @escaping @Sendable (ICloudLibraryEvent) -> Void) {
        itemURL = rootURL
        self.eventHandler = eventHandler
        operationQueue = OperationQueue()
        operationQueue.name = "com.kvsur.MarkdownApp.iCloudPresenter"
        operationQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    var presentedItemURL: URL? {
        lock.withLock { itemURL }
    }

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
        eventHandler(.rootChanged(url))
    }

    func presentedSubitemDidAppear(at url: URL) {
        eventHandler(.itemAppeared(url))
    }

    func presentedSubitemDidChange(at url: URL) {
        eventHandler(.itemChanged(url))
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        eventHandler(.itemMoved(from: oldURL, to: newURL))
    }

    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        eventHandler(.itemDeleted(url))
        completionHandler(nil)
    }

    func presentedSubitem(at url: URL, didGain version: NSFileVersion) {
        eventHandler(.versionConflict(url))
    }
}

nonisolated private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
