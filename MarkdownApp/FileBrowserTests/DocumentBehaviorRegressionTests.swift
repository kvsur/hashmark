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
        testATXHeadingParsingAndTitleInference()
        testMarkdownOutlineUsesSharedATXSemantics()
        testDocumentRouteAndNamingState()
        testSaveRenameAndContinuedEditingOrder()
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

    private static func testATXHeadingParsingAndTitleInference() {
        expect(
            MarkdownATXHeadingParser.parse(line: "\t##  Release Notes ##  ")
                == MarkdownATXHeading(level: 2, title: "Release Notes"),
            "shared ATX parsing should preserve the existing outline semantics"
        )
        expect(MarkdownATXHeadingParser.parse(line: "#tag") == nil, "ATX markers require whitespace")
        expect(MarkdownATXHeadingParser.parse(line: "####### Too deep") == nil, "ATX levels stop at six")
        expect(MarkdownATXHeadingParser.parse(line: "### ###") == nil, "an empty ATX title is invalid")

        let inferredCases: [(String, String?)] = [
            ("# One\nbody", "One"),
            ("## Two\r\nbody", "Two"),
            ("   ### Three ###\nbody", "Three"),
            ("#### Four\nbody", nil),
            ("paragraph\n# Later", nil),
            ("\n# Later", nil),
            ("Title\n=====", nil),
            ("###\nbody", nil)
        ]
        for (source, expected) in inferredCases {
            expect(
                MarkdownDocumentTitleInference.title(from: source) == expected,
                "title inference returned the wrong result for \(String(reflecting: source))"
            )
        }
    }

    private static func testMarkdownOutlineUsesSharedATXSemantics() {
        let source = "# Same\n```\n## Hidden\n```\n## Same ##\n#tag\n"
        let items = MarkdownOutline.items(in: source)
        expect(items.map(\.level) == [1, 2], "outline should keep H1-H6 recognition outside fences")
        expect(items.map(\.title) == ["Same", "Same"], "outline should use the shared title cleanup")
        expect(items.map(\.occurrence) == [0, 0], "occurrences should remain scoped by level and title")
        expect(items.first?.range.location == 0, "outline ranges should remain UTF-16 source locations")
    }

    private static func testDocumentRouteAndNamingState() {
        let node = self.node(URL(fileURLWithPath: "/Library/Untitled.md"))
        let existingRoute = DocumentRoute(node: node)
        expect(existingRoute.initialMode == .preview && !existingRoute.isNewDocument,
               "existing document routes should default to preview without auto-title eligibility")

        let newRoute = DocumentRoute(node: node, initialMode: .edit, isNewDocument: true)
        var naming = DocumentNamingState(route: newRoute)
        expect(naming.input.isEmpty && naming.actualName == "Untitled",
               "a new route should show the fallback name only as the placeholder")
        expect(naming.isAutomaticTitleEligible, "a manually created route should start auto-title eligible")

        let numberedFallback = URL(fileURLWithPath: "/Library/Untitled 2.md")
        naming.didRename(to: numberedFallback, submittedName: "", origin: .explicit)
        expect(naming.input.isEmpty && naming.actualName == "Untitled 2",
               "a successful blank commit should retain blank input and update its placeholder")
        expect(naming.isAutomaticTitleEligible, "a blank commit should retain auto-title eligibility")

        naming.didFailRename(origin: .automatic)
        expect(naming.isAutomaticTitleEligible, "a failed inferred rename must remain retryable")
        let inferred = URL(fileURLWithPath: "/Library/Release Notes.md")
        naming.didRename(to: inferred, submittedName: "Release Notes", origin: .automatic)
        expect(naming.input == "Release Notes" && !naming.isAutomaticTitleEligible,
               "a successful inferred rename should run once and expose the actual name")

        var explicitlyNamed = DocumentNamingState(route: newRoute)
        explicitlyNamed.didRename(to: inferred, submittedName: "Release Notes", origin: .explicit)
        expect(!explicitlyNamed.isAutomaticTitleEligible,
               "a successful non-empty explicit name should take priority over inference")

        var moved = DocumentNamingState(route: newRoute)
        moved.synchronizeWithExternalURL(URL(fileURLWithPath: "/Library/Remote.md"))
        expect(moved.input == "Remote" && !moved.isAutomaticTitleEligible,
               "an external move should synchronize the field and retire fallback eligibility")
    }

    private static func testSaveRenameAndContinuedEditingOrder() {
        let oldURL = URL(fileURLWithPath: "/Library/Untitled.md")
        let newURL = URL(fileURLWithPath: "/Library/Notes.md")
        var draft = DocumentDraft(node: node(oldURL))
        draft.loadIfNeeded(text: "")
        draft.text = "# Notes"
        var writes: [String] = []

        let beforeRename = draft.text
        writes.append("write:\(draft.node.url.path):\(beforeRename)")
        draft.markSaved(beforeRename, at: oldURL)
        draft.text += "\ncontinued while renaming"
        draft.move(to: newURL)
        draft.save { text, url in writes.append("write:\(url.path):\(text)") }

        expect(
            writes == [
                "write:/Library/Untitled.md:# Notes",
                "write:/Library/Notes.md:# Notes\ncontinued while renaming"
            ],
            "persistence must save the old snapshot before rename and later edits only to the new URL"
        )
        expect(draft.node.url == newURL && !draft.isDirty,
               "a completed rename transaction should finish clean on the new URL")
    }

    private static func node(_ url: URL) -> DocumentNode {
        DocumentNode(url: url, kind: .markdown, modifiedAt: .distantPast)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
