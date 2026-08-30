import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum DocumentLibraryMergeTests {
    static func main() throws {
        try testRecursiveMergeDedupesAndPreservesDivergence()
        try testFileFolderCollisionsPreserveBothSides()
        try testExistingConflictNamesNeverOverwrite()
        try testCopiedFilesPreserveModificationDatesAndActivityOrder()
        print("DocumentLibraryMergeTests: PASS")
    }

    private static func testRecursiveMergeDedupesAndPreservesDivergence() throws {
        try withRoots { source, destination in
            try write("same", to: source.appendingPathComponent("Same.md"))
            try write("same", to: destination.appendingPathComponent("Same.md"))
            try write("local", to: source.appendingPathComponent("Nested/Note.md"))
            try write("cloud", to: destination.appendingPathComponent("Nested/Note.md"))
            try FileManager.default.createDirectory(
                at: source.appendingPathComponent("Empty", isDirectory: true),
                withIntermediateDirectories: true
            )

            let report = try service().merge(from: source, into: destination)
            expect(report.deduplicatedRelativePaths == ["Same.md"], "identical files must dedupe by hash")
            let destinationText = try read(destination.appendingPathComponent("Nested/Note.md"))
            expect(destinationText == "cloud", "existing destination bytes must never be overwritten")
            let conflict = destination.appendingPathComponent("Nested/Note (Conflict 2023-11-14 221320 iPhone).md")
            let conflictText = try read(conflict)
            expect(conflictText == "local", "divergent source bytes must survive as a deterministic conflict copy")
            expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("Nested/Note.md").path), "merge must not delete its source")
            expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Empty").path), "empty source folders must merge")
        }
    }

    private static func testFileFolderCollisionsPreserveBothSides() throws {
        try withRoots { source, destination in
            try write("source-file", to: source.appendingPathComponent("AsFolder.md"))
            try FileManager.default.createDirectory(
                at: destination.appendingPathComponent("AsFolder.md", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: source.appendingPathComponent("AsFile", isDirectory: true),
                withIntermediateDirectories: true
            )
            try write("nested", to: source.appendingPathComponent("AsFile/Nested.md"))
            try write("destination-file", to: destination.appendingPathComponent("AsFile"))

            _ = try service().merge(from: source, into: destination)
            let sourceFileConflict = destination.appendingPathComponent("AsFolder (Conflict 2023-11-14 221320 iPhone).md")
            let sourceFileText = try read(sourceFileConflict)
            expect(sourceFileText == "source-file", "source file must survive a destination-folder collision")
            let destinationFileText = try read(destination.appendingPathComponent("AsFile"))
            expect(destinationFileText == "destination-file", "destination file must survive a source-folder collision")
            let sourceFolderConflict = destination.appendingPathComponent("AsFile (Conflict 2023-11-14 221320 iPhone)/Nested.md")
            let nestedText = try read(sourceFolderConflict)
            expect(nestedText == "nested", "source folder hierarchy must survive beside the destination file")
        }
    }

    private static func testExistingConflictNamesNeverOverwrite() throws {
        try withRoots { source, destination in
            try write("incoming", to: source.appendingPathComponent("Note.md"))
            try write("existing", to: destination.appendingPathComponent("Note.md"))
            let firstConflict = destination.appendingPathComponent("Note (Conflict 2023-11-14 221320 iPhone).md")
            try write("older-conflict", to: firstConflict)

            _ = try service().merge(from: source, into: destination)
            let firstConflictText = try read(firstConflict)
            expect(firstConflictText == "older-conflict", "an existing conflict copy must not be overwritten")
            let secondConflict = destination.appendingPathComponent("Note (Conflict 2023-11-14 221320 iPhone) 2.md")
            let secondConflictText = try read(secondConflict)
            expect(secondConflictText == "incoming", "collision suffix must preserve the new divergent bytes")
        }
    }

    private static func testCopiedFilesPreserveModificationDatesAndActivityOrder() throws {
        try withRoots { source, destination in
            let newestDate = Date(timeIntervalSince1970: 1_700_000_000)
            let oldestDate = Date(timeIntervalSince1970: 1_600_000_000)
            let newestSource = source.appendingPathComponent("Newest.md")
            let oldestSource = source.appendingPathComponent("Oldest.md")
            try write("newest", to: newestSource)
            try write("oldest", to: oldestSource)
            try setModificationDate(newestDate, for: newestSource)
            try setModificationDate(oldestDate, for: oldestSource)

            _ = try service().merge(from: source, into: destination)

            let newestDestination = destination.appendingPathComponent("Newest.md")
            let oldestDestination = destination.appendingPathComponent("Oldest.md")
            let copiedNewestDate = try modificationDate(of: newestDestination)
            let copiedOldestDate = try modificationDate(of: oldestDestination)
            expect(
                copiedNewestDate == newestDate,
                "a copied document must retain its source modification date"
            )
            expect(
                copiedOldestDate == oldestDate,
                "copy order must not replace document activity dates"
            )
            let orderedNames = DocumentActivityResolver().records(in: destination).map { $0.url.lastPathComponent }
            expect(
                orderedNames == ["Newest.md", "Oldest.md"],
                "documents restored from iCloud must remain ordered by their original activity"
            )
        }
    }

    private static func service() -> DocumentLibraryMergeService {
        DocumentLibraryMergeService(
            coordinator: DirectFileAccessCoordinator(),
            conflictTimestamp: { Date(timeIntervalSince1970: 1_700_000_000) },
            conflictDeviceName: "iPhone"
        )
    }

    private static func withRoots(_ body: (URL, URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentLibraryMergeTests-\(UUID().uuidString)", isDirectory: true)
        let source = base.appendingPathComponent("Source", isDirectory: true)
        let destination = base.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(source, destination)
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private static func modificationDate(of url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
