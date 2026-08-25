import Foundation

enum AIPromptLocale {
    static var uiLanguageName: String { "English" }
}

nonisolated enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openAI, anthropic, gemini, kimi, glm
    var id: String { rawValue }
}

nonisolated enum AIModelCapability: Hashable {
    case imageInput, pdfInput, genericFileInput
}

nonisolated struct TestCapability: Equatable {
    let isEnabled: Bool
}

nonisolated struct TestCapabilities: Equatable {
    let imageInput: TestCapability
    let inlinePDF: TestCapability
    let fileExtraction: TestCapability
}

nonisolated struct ResolvedAIProviderConfiguration: Equatable {
    let provider: AIProvider
    let effectiveCapabilities: TestCapabilities

    func allowsKnownSafeRequest(_ capability: AIModelCapability) -> Bool {
        switch capability {
        case .imageInput: effectiveCapabilities.imageInput.isEnabled
        case .pdfInput: effectiveCapabilities.inlinePDF.isEnabled
        case .genericFileInput: true
        }
    }
}

enum LocalizationController {
    @MainActor static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value)
    }
}

nonisolated protocol AIProviderAdapter: Sendable {
    var provider: AIProvider { get }
    var configuration: ResolvedAIProviderConfiguration { get }
    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference
    func delete(_ reference: AIProviderFileReference) async throws
}

private actor FakeAdapter: AIProviderAdapter {
    enum Mode {
        case normal
        case wrongProvider
        case expired
        case delaySecond
    }

    nonisolated let provider: AIProvider
    nonisolated let configuration: ResolvedAIProviderConfiguration
    private let mode: Mode
    private var uploadCount = 0
    private var deletedIDs: [String] = []

    init(provider: AIProvider = .kimi, mode: Mode = .normal) {
        self.provider = provider
        self.mode = mode
        self.configuration = makeConfiguration(provider, image: true, pdf: true, extraction: true)
    }

    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference {
        uploadCount += 1
        if mode == .delaySecond, uploadCount == 2 {
            try await Task.sleep(for: .seconds(5))
        }
        let resultProvider: AIProvider = mode == .wrongProvider ? .openAI : provider
        let expiresAt = mode == .expired ? Date(timeIntervalSince1970: 1) : nil
        return AIProviderFileReference(
            provider: resultProvider,
            id: "file-\(uploadCount)",
            purpose: request.purpose,
            expiresAt: expiresAt,
            transportPayload: .object([
                "name": .string(request.name),
                "mime_type": .string(request.mimeType),
                "extracted_text": .string("fixture extraction")
            ])
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        deletedIDs.append(reference.id)
    }

    func deletes() -> [String] { deletedIDs }
}

private func makeConfiguration(
    _ provider: AIProvider,
    image: Bool,
    pdf: Bool,
    extraction: Bool
) -> ResolvedAIProviderConfiguration {
    ResolvedAIProviderConfiguration(
        provider: provider,
        effectiveCapabilities: TestCapabilities(
            imageInput: TestCapability(isEnabled: image),
            inlinePDF: TestCapability(isEnabled: pdf),
            fileExtraction: TestCapability(isEnabled: extraction)
        )
    )
}

private var failures: [String] = []

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

@main
enum AttachmentOrchestrationTests {
    static func main() async {
        testProviderRoutes()
        testProviderLimits()
        testReferenceReuseAndRetrievalIdentity()
        await testOriginalMessageBinding()
        await testProviderAndExpiryGuards()
        await testCancellationCleanup()

        if failures.isEmpty {
            print("AttachmentOrchestrationTests: PASS")
        } else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
    }

    private static func testProviderRoutes() {
        let image = AIAttachment.image(Data([1]))
        let pdf = AIAttachment.pdf(data: Data([2]), name: "fixture.pdf")
        let document = AIAttachment.documentReference(
            url: URL(fileURLWithPath: "/fixture.md"),
            name: "fixture.md",
            text: "context"
        )

        for provider in AIProvider.allCases {
            let config = makeConfiguration(provider, image: true, pdf: true, extraction: true)
            expect((try? AIAttachmentPolicy.intent(for: image, configuration: config)) == .directInput,
                   "\(provider.rawValue) image route changed")
            let expectedPDF: AIAttachmentIntent = provider == .kimi ? .extraction : .directInput
            expect((try? AIAttachmentPolicy.intent(for: pdf, configuration: config)) == expectedPDF,
                   "\(provider.rawValue) PDF route changed")
            expect((try? AIAttachmentPolicy.intent(for: document, configuration: config)) == .textContext,
                   "\(provider.rawValue) text context route changed")
        }

        do {
            _ = try AIAttachmentPolicy.intent(
                for: image,
                configuration: makeConfiguration(.openAI, image: false, pdf: true, extraction: false)
            )
            failures.append("Unsupported image silently downgraded")
        } catch AIAttachmentIssue.unsupportedByModel {
            // expected
        } catch {
            failures.append("Unsupported image returned the wrong typed issue")
        }
    }

    private static func testProviderLimits() {
        let config = makeConfiguration(.openAI, image: true, pdf: true, extraction: true)
        let tooMany = (0..<11).map { index in
            AIAttachment.documentReference(
                url: URL(fileURLWithPath: "/\(index).md"),
                name: "\(index).md",
                text: "x"
            )
        }
        do {
            _ = try AIAttachmentPolicy.validate(tooMany, configuration: config)
            failures.append("Provider attachment count limit was skipped")
        } catch AIAttachmentIssue.tooMany(let maxCount) {
            expect(maxCount == 10, "OpenAI conservative count limit changed")
        } catch {
            failures.append("Attachment count returned the wrong typed issue")
        }

        do {
            _ = try AIAttachmentPolicy.validate(
                [.image(Data(repeating: 0, count: (4 << 20) + 1))],
                configuration: config
            )
            failures.append("Provider attachment byte limit was skipped")
        } catch AIAttachmentIssue.itemTooLarge {
            // expected
        } catch {
            failures.append("Attachment byte limit returned the wrong typed issue")
        }

        do {
            _ = try AIAttachmentPolicy.validate(
                [.image(Data([1])), .pdf(data: Data([2]), name: "mixed.pdf")],
                configuration: makeConfiguration(.glm, image: true, pdf: true, extraction: true)
            )
            failures.append("GLM mixed-media restriction was skipped")
        } catch AIAttachmentIssue.mixedMediaUnsupported {
            // expected
        } catch {
            failures.append("GLM mixed-media restriction returned the wrong typed issue")
        }
    }

    private static func testReferenceReuseAndRetrievalIdentity() {
        let reference = AIProviderFileReference(
            provider: .gemini,
            id: "files/reusable",
            purpose: .retrieval,
            expiresAt: Date.now.addingTimeInterval(60),
            transportPayload: .object([
                "file_search_store_name": .string("fileSearchStores/session")
            ])
        )
        let first = try? reference.validated(for: .gemini)
        let second = try? reference.validated(for: .gemini)
        expect(first == reference && second == reference,
               "Valid Provider retrieval reference was not reusable")
        expect(reference.transportPayload?.string(for: "file_search_store_name") ==
               "fileSearchStores/session",
               "Retrieval identity escaped or changed in the neutral lifecycle")
    }

    private static func testOriginalMessageBinding() async {
        let pdf = AIAttachment.pdf(data: Data([1, 2, 3]), name: "bound.pdf")
        let messages = [
            AIMessage(role: .user, content: "first"),
            AIMessage(role: .user, content: "second", attachments: [pdf])
        ]
        let adapter = FakeAdapter()
        do {
            let result = try await AIAttachmentOrchestrator().prepare(
                messages: messages,
                selectedAttachments: [pdf],
                adapter: adapter
            )
            expect(result.messages[0].providerFiles.isEmpty,
                   "Uploaded reference moved to a different message")
            expect(result.messages[1].providerFiles.map(\.id) == ["file-1"],
                   "Uploaded reference was not bound to its original message")
            expect(result.messages[1].attachments.isEmpty,
                   "Extracted PDF was also sent as a direct attachment")
            expect(result.preparations.first?.state == .ready(result.references.first),
                   "Attachment did not reach ready state")
            await AIAttachmentOrchestrator().release(
                result.references,
                adapter: adapter,
                includeRetrieval: true
            )
            let deleted = await adapter.deletes()
            expect(deleted == ["file-1"], "Normal cleanup did not delete the upload")
        } catch {
            failures.append("Original-message binding failed: \(error)")
        }
    }

    private static func testProviderAndExpiryGuards() async {
        for (mode, expected) in [
            (FakeAdapter.Mode.wrongProvider, AIAttachmentIssue.providerMismatch),
            (FakeAdapter.Mode.expired, AIAttachmentIssue.expiredReference)
        ] {
            let pdf = AIAttachment.pdf(data: Data([1]), name: "guard.pdf")
            let adapter = FakeAdapter(mode: mode)
            do {
                _ = try await AIAttachmentOrchestrator().prepare(
                    messages: [AIMessage(role: .user, content: "guard", attachments: [pdf])],
                    selectedAttachments: [pdf],
                    adapter: adapter
                )
                failures.append("Invalid Provider reference was accepted")
            } catch let issue as AIAttachmentIssue {
                expect(issue == expected, "Provider reference returned the wrong typed issue")
                let deleted = await adapter.deletes()
                expect(deleted == ["file-1"],
                       "Rejected Provider reference was not cleaned up")
            } catch {
                failures.append("Provider reference guard returned an untyped error")
            }
        }
    }

    private static func testCancellationCleanup() async {
        let first = AIAttachment.pdf(data: Data([1]), name: "first.pdf")
        let second = AIAttachment.pdf(data: Data([2]), name: "second.pdf")
        let adapter = FakeAdapter(mode: .delaySecond)
        let task = Task {
            try await AIAttachmentOrchestrator().prepare(
                messages: [AIMessage(
                    role: .user,
                    content: "cancel",
                    attachments: [first, second]
                )],
                selectedAttachments: [first, second],
                adapter: adapter
            )
        }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()
        _ = await task.result
        let deleted = await adapter.deletes()
        expect(deleted.contains("file-1"),
               "Cancellation left an earlier upload behind")
    }
}
