//
//  AIWritingSession+Attachments.swift
//  MarkdownApp
//
//  Attachment presentation, Provider-scoped preparation, and deterministic cleanup.
//

import Foundation

extension AIWritingSession {
    func prepareAttachments(using adapter: AIProviderAdapter?) async throws -> [AIMessage] {
        guard !selectedAttachments.isEmpty else { return messages }
        guard let adapter else { throw AIAttachmentIssue.uploadUnavailable }
        attachmentPreparations = try AIAttachmentPolicy.validate(
            selectedAttachments,
            configuration: adapter.configuration
        )
        AIDiagnostics.attachmentPreflight(
            provider: adapter.provider,
            attachmentCount: attachmentPreparations.count,
            totalBytes: attachmentPreparations.reduce(0) { $0 + $1.byteCount },
            intents: attachmentPreparations.map { $0.intent.diagnosticName }
        )
        generationPhase = attachmentPreparations.contains(where: {
            $0.intent == .uploadReference || $0.intent == .extraction || $0.intent == .retrieval
        }) ? .uploading : .preparingAttachments
        if let generationPhase { presentationState.apply(generationPhase) }
        let prepared = try await attachmentOrchestrator.prepare(
            messages: messages,
            selectedAttachments: selectedAttachments,
            adapter: adapter
        )
        attachmentPreparations = prepared.preparations
        activeAttachmentReferences = prepared.references
        generationPhase = .connecting
        presentationState.apply(.connecting)
        return prepared.messages
    }

    func applyFileState(_ state: AIFileState) {
        guard let index = attachmentPreparations.firstIndex(where: {
            if case .ready = $0.state { return false }
            return true
        }) else { return }
        switch state {
        case .validating: attachmentPreparations[index].state = .validating
        case .uploading(let progress): attachmentPreparations[index].state = .uploading(progress: progress)
        case .extracting: attachmentPreparations[index].state = .extracting
        case .ready(let reference): attachmentPreparations[index].state = .ready(reference)
        case .failed: attachmentPreparations[index].state = .failed(.uploadUnavailable)
        case .expired: attachmentPreparations[index].state = .expired
        }
    }

    func releaseDetachedReferences() {
        guard let adapter = client as? AIProviderAdapter,
              !activeAttachmentReferences.isEmpty else { return }
        let references = activeAttachmentReferences
        activeAttachmentReferences = []
        Task {
            await attachmentOrchestrator.release(
                references,
                adapter: adapter,
                includeRetrieval: true
            )
        }
    }

    func releaseActiveReferences(using adapter: AIProviderAdapter?) async {
        guard let adapter, !activeAttachmentReferences.isEmpty else { return }
        let references = activeAttachmentReferences
        activeAttachmentReferences = []
        await attachmentOrchestrator.release(
            references,
            adapter: adapter,
            includeRetrieval: true
        )
    }

    func userFacingMessage(for error: Error) -> String {
        var message: String
        if let issue = error as? AIAttachmentIssue {
            message = issue.userMessage
        } else if error is AIProviderFileValidationError {
            message = LocalizationController.string("Some files couldn't be added.")
        } else {
            message = (error as? AIError)?.errorDescription ?? error.localizedDescription
        }
        if messages.contains(where: { !$0.imageAttachments.isEmpty }),
           let aiError = error as? AIError,
           case .http(let status, _) = aiError,
           (400..<500).contains(status) {
            message += "\n" + LocalizationController.string(
                "If this keeps failing, the model you selected may not support image attachments."
            )
        }
        return message
    }
}
