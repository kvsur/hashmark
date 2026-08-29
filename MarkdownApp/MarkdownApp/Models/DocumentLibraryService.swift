import Foundation

nonisolated enum DocumentLibraryError: LocalizedError, Equatable, Sendable {
    case mutationsFrozen
    case unreadableText(URL)

    var errorDescription: String? {
        switch self {
        case .mutationsFrozen:
            return "Document changes are temporarily unavailable."
        case .unreadableText:
            return "The document could not be read as UTF-8 text."
        }
    }
}

actor DocumentLibraryService {
    private var store: FileStore
    private var mutationsFrozen = false

    init(store: FileStore) {
        self.store = store
    }

    var rootURL: URL { store.rootURL }
    var localInboxURL: URL { store.inboxURL }

    func replaceStore(_ store: FileStore) throws {
        guard !mutationsFrozen else { throw DocumentLibraryError.mutationsFrozen }
        self.store = store
    }

    func transitionStore(_ store: FileStore, mutationsFrozen: Bool) {
        self.store = store
        self.mutationsFrozen = mutationsFrozen
    }

    func setMutationsFrozen(_ frozen: Bool) {
        mutationsFrozen = frozen
    }

    func contents(of directory: URL) throws -> [DocumentNode] {
        try store.contents(of: directory)
    }

    func tree(of directory: URL? = nil) throws -> [DocumentTreeNode] {
        try store.tree(of: directory ?? store.rootURL)
    }

    func readText(at url: URL) throws -> String {
        try store.readText(at: url)
    }

    func readExternalText(at url: URL) throws -> String {
        try store.readExternalText(at: url)
    }

    func isInsideLibrary(_ url: URL) -> Bool {
        store.isInsideStore(url)
    }

    func createFolder(named name: String, in directory: URL) throws -> URL {
        try requireMutable()
        return try store.createFolder(named: name, in: directory)
    }

    func createMarkdown(named name: String, in directory: URL) throws -> URL {
        try requireMutable()
        return try store.createMarkdown(named: name, in: directory)
    }

    func writeText(_ text: String, to url: URL) throws {
        try requireMutable()
        try store.writeText(text, to: url)
    }

    func rename(_ node: DocumentNode, to name: String) throws -> URL {
        try requireMutable()
        return try store.rename(node, to: name)
    }

    func delete(_ node: DocumentNode) throws {
        try requireMutable()
        try store.delete(node)
    }

    func importFile(from source: URL, to directory: URL) throws -> URL {
        try requireMutable()
        return try store.importFile(from: source, to: directory)
    }

    func move(_ node: DocumentNode, to directory: URL) throws -> URL {
        try requireMutable()
        return try store.move(node, to: directory)
    }

    func purgeInbox() throws {
        try requireMutable()
        store.purgeInbox()
    }

    private func requireMutable() throws {
        guard !mutationsFrozen else { throw DocumentLibraryError.mutationsFrozen }
    }
}
