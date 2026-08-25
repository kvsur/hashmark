import Foundation

@main
enum DocumentActivityResolverTests {
    static func main() throws {
        try testRecursiveActivityAndStableGrouping()
        try testMissingDirectoryAndSymlinkLoop()
        try testWideDirectoryPerformance()
        print("DocumentActivityResolverTests: PASS")
    }

    private static func testRecursiveActivityAndStableGrouping() throws {
        try withTemporaryDirectory { root, fileManager in
            let folderOld = root.appendingPathComponent("Folder Old", isDirectory: true)
            let deep = folderOld.appendingPathComponent("Deep", isDirectory: true)
            let folderNew = root.appendingPathComponent("Folder New", isDirectory: true)
            let empty = root.appendingPathComponent("Empty", isDirectory: true)
            let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
            for directory in [deep, folderNew, empty, inbox] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            try write("old", to: deep.appendingPathComponent("old.md"), date: date(200), fileManager: fileManager)
            try write("new", to: folderNew.appendingPathComponent("new.md"), date: date(400), fileManager: fileManager)
            try write("latest", to: root.appendingPathComponent("latest.md"), date: date(500), fileManager: fileManager)
            try write("a", to: root.appendingPathComponent("a.md"), date: date(100), fileManager: fileManager)
            try write("z", to: root.appendingPathComponent("z.md"), date: date(100), fileManager: fileManager)
            try write("hidden", to: root.appendingPathComponent(".hidden.md"), date: date(900), fileManager: fileManager)
            try write("ignored", to: root.appendingPathComponent("ignored.txt"), date: date(800), fileManager: fileManager)
            try write("inbox", to: inbox.appendingPathComponent("inbox.md"), date: date(700), fileManager: fileManager)
            try setDate(date(300), for: empty, fileManager: fileManager)

            let records = DocumentActivityResolver(fileManager: fileManager)
                .records(in: root, excluding: inbox)

            expect(
                records.map { $0.url.lastPathComponent } == [
                    "Folder New", "Empty", "Folder Old", "latest.md", "a.md", "z.md"
                ],
                "folder/file grouping or activity ordering is incorrect"
            )
            expect(records[0].modifiedAt == date(400), "folder should inherit newest descendant Markdown date")
            expect(records[1].modifiedAt == date(300), "empty folder should fall back to its own date")
            expect(records[2].modifiedAt == date(200), "deep descendant date should propagate to ancestor")
            expect(records[2].childCount == 1, "folder child count should remain shallow")
            expect(records[3].modifiedAt == date(500), "file should retain its own modification date")
        }
    }

    private static func testMissingDirectoryAndSymlinkLoop() throws {
        try withTemporaryDirectory { root, fileManager in
            let folder = root.appendingPathComponent("Folder", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            try write("body", to: folder.appendingPathComponent("doc.md"), date: date(200), fileManager: fileManager)
            try fileManager.createSymbolicLink(
                at: folder.appendingPathComponent("Loop", isDirectory: true),
                withDestinationURL: root
            )

            let resolver = DocumentActivityResolver(fileManager: fileManager)
            let records = resolver.records(in: root)
            expect(records.count == 1, "symbolic link should not become a visible record")
            expect(records[0].children?.count == 1, "symbolic link loop should be skipped")

            let missing = root.appendingPathComponent("Missing", isDirectory: true)
            expect(resolver.records(in: missing).isEmpty, "unreadable or missing directory should resolve safely")
        }
    }

    private static func testWideDirectoryPerformance() throws {
        try withTemporaryDirectory { root, fileManager in
            for folderIndex in 0..<30 {
                let folder = root.appendingPathComponent("Folder \(folderIndex)", isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
                for fileIndex in 0..<20 {
                    let file = folder.appendingPathComponent("Document \(fileIndex).md")
                    try Data().write(to: file)
                }
            }

            let start = ContinuousClock.now
            let records = DocumentActivityResolver(fileManager: fileManager).records(in: root)
            let elapsed = start.duration(to: .now)
            expect(records.count == 30, "wide fixture should preserve every direct folder")
            expect(elapsed < .seconds(2), "600-file activity scan exceeded the 2-second safety budget")
        }
    }

    private static func withTemporaryDirectory(
        _ body: (URL, FileManager) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DocumentActivityResolverTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: root) }
        try body(root, fileManager)
    }

    private static func write(
        _ text: String,
        to url: URL,
        date: Date,
        fileManager: FileManager
    ) throws {
        try Data(text.utf8).write(to: url)
        try setDate(date, for: url, fileManager: fileManager)
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
}
