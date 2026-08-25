import Foundation

// 独立命令行测试不加载 App 的本地化控制器；这里只提供模型编译所需的最小桩。
enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum FileStoreRegressionTests {
    static func main() throws {
        try testCRUDImportMoveAndTree()
        try testSaveRefreshesRecursiveActivityOrder()
        print("FileStoreRegressionTests: PASS")
    }

    private static func testCRUDImportMoveAndTree() throws {
        try withTemporaryStore { store, root, fileManager in
            let folderURL = try store.createFolder(named: "Folder", in: root)
            let firstURL = try store.createMarkdown(named: "Document", in: root)
            let collisionURL = try store.createMarkdown(named: "Document", in: root)
            expect(collisionURL.lastPathComponent == "Document 2.md", "create should retain unique-name behavior")

            try store.writeText("body", to: firstURL)
            expect(store.readText(at: firstURL) == "body", "saved Markdown should read back unchanged")

            let firstNode = try node(named: "Document.md", in: store.contents(of: root))
            let renamedURL = try store.rename(firstNode, to: "Renamed")
            expect(renamedURL.lastPathComponent == "Renamed.md", "rename should preserve Markdown extension")

            let external = fileManager.temporaryDirectory
                .appendingPathComponent("Import-\(UUID().uuidString).md")
            try Data("external".utf8).write(to: external)
            defer { try? fileManager.removeItem(at: external) }
            let importedURL = try store.importFile(from: external, to: root)
            expect(store.readText(at: importedURL) == "external", "import should preserve file contents")
            expect(fileManager.fileExists(atPath: external.path), "external import must not delete its source")

            let importedNode = try node(named: importedURL.lastPathComponent, in: store.contents(of: root))
            let movedURL = try store.move(importedNode, to: folderURL)
            expect(fileManager.fileExists(atPath: movedURL.path), "move panel path should still create destination")
            expect(!fileManager.fileExists(atPath: importedURL.path), "move panel path should remove source")

            let tree = store.tree(of: root)
            let folderPath = folderURL.standardizedFileURL.path
            let movedPath = movedURL.standardizedFileURL.path
            let folder = try unwrap(
                tree.first { $0.node.url.standardizedFileURL.path == folderPath },
                "folder should remain in tree"
            )
            expect(
                folder.children?.contains { $0.node.url.standardizedFileURL.path == movedPath } == true,
                "tree should include moved file"
            )

            let collisionNode = try node(named: collisionURL.lastPathComponent, in: store.contents(of: root))
            try store.delete(collisionNode)
            expect(!fileManager.fileExists(atPath: collisionURL.path), "delete should still remove selected file")
        }
    }

    private static func testSaveRefreshesRecursiveActivityOrder() throws {
        try withTemporaryStore { store, root, fileManager in
            let olderFolder = try store.createFolder(named: "Older", in: root)
            let newerFolder = try store.createFolder(named: "Newer", in: root)
            let olderFile = try store.createMarkdown(named: "Old", in: olderFolder)
            let newerFile = try store.createMarkdown(named: "New", in: newerFolder)
            try setDate(date(100), for: olderFile, fileManager: fileManager)
            try setDate(date(200), for: newerFile, fileManager: fileManager)

            var folders = store.contents(of: root).filter(\.isFolder)
            expect(folders.map(\.name) == ["Newer", "Older"], "initial folder activity order is incorrect")

            try store.writeText("updated", to: olderFile)
            try setDate(date(300), for: olderFile, fileManager: fileManager)
            folders = store.contents(of: root).filter(\.isFolder)
            expect(folders.map(\.name) == ["Older", "Newer"], "save should promote every ancestor on reload")
            expect(folders[0].modifiedAt == date(300), "folder metadata should show effective descendant date")
        }
    }

    private static func withTemporaryStore(
        _ body: (FileStore, URL, FileManager) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FileStoreRegressionTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        try body(FileStore(fileManager: fileManager, rootURL: root), root, fileManager)
    }

    private static func node(named name: String, in nodes: [DocumentNode]) throws -> DocumentNode {
        try unwrap(nodes.first { $0.name == name }, "missing node \(name)")
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw TestError(message: message) }
        return value
    }

    private static func setDate(_ date: Date, for url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private static func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private struct TestError: Error {
        let message: String
    }
}
