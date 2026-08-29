import Foundation

enum LocalizationController {
    static var current: Locale { .current }
    static func string(_ key: String) -> String { key }
}

@main
enum DocumentBehaviorRegressionTests {
    static func main() {
        testDraftLoadSaveAndSwitchOrder()
        testExternalDocumentChangePolicy()
        testExternalOpenResolution()
        testDocumentReferenceResolution()
        print("DocumentBehaviorRegressionTests: PASS")
    }

    private static func testExternalDocumentChangePolicy() {
        let originalURL = URL(fileURLWithPath: "/Library/Open.md")
        var draft = DocumentDraft(node: node(originalURL))
        draft.loadIfNeeded(text: "baseline")

        expect(draft.decision(forRemoteText: "baseline") == .ignore,
               "an unchanged clean file should not reload")
        expect(draft.decision(forRemoteText: "remote") == .reload,
               "a clean draft should accept distinct remote content")
        draft.reloadCleanText("remote", at: originalURL)
        expect(draft.text == "remote" && !draft.isDirty,
               "a clean external reload must establish a new baseline")

        draft.text = "local draft"
        expect(draft.decision(forRemoteText: "remote") == .ignore,
               "an attribute-only event matching the saved baseline should be ignored")
        expect(draft.decision(forRemoteText: "local draft") == .markSaved,
               "a notification for the editor's own completed write should only mark saved")
        expect(draft.decision(forRemoteText: "other device") == .preserveRemoteAndSaveDraft,
               "distinct remote bytes must not replace a dirty draft")

        let movedURL = URL(fileURLWithPath: "/Library/Renamed.md")
        draft.move(to: movedURL)
        expect(draft.node.url == movedURL && draft.text == "local draft" && draft.isDirty,
               "remote moves must update identity without discarding the draft")
    }

    private static func testDraftLoadSaveAndSwitchOrder() {
        let firstURL = URL(fileURLWithPath: "/Library/First.md")
        let secondURL = URL(fileURLWithPath: "/Library/Nested/Second.md")
        let first = node(firstURL)
        let second = node(secondURL)
        var events: [String] = []
        var draft = DocumentDraft(node: first)

        draft.loadIfNeeded { url in
            events.append("read:\(url.path)")
            return "first"
        }
        draft.loadIfNeeded { _ in
            events.append("unexpected second read")
            return "wrong"
        }
        expect(events == ["read:/Library/First.md"], "a document should load once on repeated appearances")
        expect(draft.text == "first" && !draft.isDirty, "initial load should establish the clean baseline")

        draft.save { _, _ in events.append("unexpected clean write") }
        expect(events.count == 1, "a clean draft should not be written")

        draft.text = "edited first"
        let switched = draft.switchTo(
            second,
            readText: { url in
                events.append("read:\(url.path)")
                return "second"
            },
            writeText: { text, url in
                events.append("write:\(url.path):\(text)")
            }
        )
        expect(switched, "a different URL should switch documents")
        expect(
            events.suffix(2) == ["write:/Library/First.md:edited first", "read:/Library/Nested/Second.md"],
            "switching should save the dirty old URL before reading the new URL"
        )
        expect(draft.node.url == secondURL && draft.text == "second" && !draft.isDirty,
               "switching should replace identity and establish a clean new baseline")

        let eventCount = events.count
        expect(!draft.switchTo(second, readText: { _ in "wrong" }, writeText: { _, _ in }),
               "selecting the current URL should be a no-op")
        expect(events.count == eventCount, "same-URL selection should perform no I/O")
    }

    private static func testExternalOpenResolution() {
        let url = URL(fileURLWithPath: "/External/Release Notes.md")
        var reads: [URL] = []
        let document = ImportedDocument.load(from: url) { requested in
            reads.append(requested)
            return "# Notes"
        }
        expect(reads == [url], "external open should read exactly the delivered URL")
        expect(document?.url == url, "external preview should preserve source URL identity")
        expect(document?.title == "Release Notes", "external preview title should remove the extension")
        expect(document?.markdown == "# Notes", "external preview should preserve source text")

        let empty = ImportedDocument.load(from: url) { _ in "" }
        expect(empty != nil, "an empty readable file should still open as an empty preview")
        expect(ImportedDocument.load(from: url) { _ in nil } == nil,
               "an unreadable external file should not create a preview payload")
    }

    private static func testDocumentReferenceResolution() {
        let firstURL = URL(fileURLWithPath: "/Library/Folder/First.md")
        let emptyURL = URL(fileURLWithPath: "/Library/Folder/Empty.md")
        let ignoredURL = URL(fileURLWithPath: "/Library/Ignored.md")
        let folder = DocumentTreeNode(
            node: DocumentNode(
                url: URL(fileURLWithPath: "/Library/Folder", isDirectory: true),
                kind: .folder,
                modifiedAt: .distantPast
            ),
            children: [
                DocumentTreeNode(node: node(firstURL), children: nil),
                DocumentTreeNode(node: node(emptyURL), children: nil)
            ]
        )
        let roots = [folder, DocumentTreeNode(node: node(ignoredURL), children: nil)]
        let values = [firstURL: "  first body  ", emptyURL: " \n ", ignoredURL: "ignored"]
        let attachments = DocumentReferenceResolver.attachments(
            in: roots,
            selectedURLs: [firstURL, emptyURL],
            readText: { values[$0] ?? "" }
        )

        expect(attachments.count == 1, "empty and unselected documents should not become AI references")
        guard case .documentReference(let url, let name, let text) = attachments.first?.kind else {
            fatalError("selected non-empty document should become a documentReference attachment")
        }
        expect(url == firstURL, "AI reference should retain URL identity for deduplication")
        expect(name == "First", "AI reference should use the document display name")
        expect(text == "first body", "AI reference should trim surrounding whitespace")
    }

    private static func node(_ url: URL) -> DocumentNode {
        DocumentNode(url: url, kind: .markdown, modifiedAt: .distantPast)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
