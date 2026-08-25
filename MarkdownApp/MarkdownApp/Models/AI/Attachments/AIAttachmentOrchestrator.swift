//
//  AIAttachmentOrchestrator.swift
//  MarkdownApp
//
//  按原消息绑定 direct/upload/extract/retrieval，负责取消清理和 Provider reference 校验。
//

import Foundation

actor AIAttachmentOrchestrator {
    func prepare(
        messages: [AIMessage],
        selectedAttachments: [AIAttachment],
        adapter: AIProviderAdapter
    ) async throws -> AIPreparedAttachmentTurn {
        var preparations = try AIAttachmentPolicy.validate(
            selectedAttachments,
            configuration: adapter.configuration
        )
        let preparationByID = Dictionary(uniqueKeysWithValues: preparations.enumerated().map {
            ($0.element.id, $0.offset)
        })
        for index in preparations.indices where preparations[index].intent == .textContext {
            // Document reference 已由 AIAction 作为可见 reference block 写入正文。
            preparations[index].state = .ready(nil)
        }
        var createdReferences: [AIProviderFileReference] = []

        do {
            var preparedMessages: [AIMessage] = []
            for message in messages {
                try Task.checkCancellation()
                var direct: [AIAttachment] = []
                var references = message.providerFiles
                for attachment in message.attachments {
                    guard let preparationIndex = preparationByID[attachment.id] else {
                        throw AIAttachmentIssue.unsupportedMIME("unknown")
                    }
                    let intent = preparations[preparationIndex].intent
                    switch intent {
                    case .textContext:
                        // AIAction 已显式把文本作为 reference block 注入，wire 不重复发送。
                        preparations[preparationIndex].state = .ready(nil)
                    case .directInput:
                        direct.append(attachment)
                        preparations[preparationIndex].state = .ready(nil)
                    case .uploadReference, .extraction, .retrieval:
                        preparations[preparationIndex].state = intent == .extraction
                            ? .extracting
                            : .uploading(progress: nil)
                        let descriptor = attachment.uploadDescriptor
                        guard let purpose = intent.filePurpose else {
                            throw AIAttachmentIssue.uploadUnavailable
                        }
                        let uploaded = try await adapter.upload(AIFileUploadRequest(
                            name: descriptor.name,
                            mimeType: descriptor.mimeType,
                            data: descriptor.data,
                            purpose: purpose
                        ))
                        // 即使 Provider 回了错误归属/已过期引用，失败路径也必须尝试清理。
                        createdReferences.append(uploaded)
                        let reference: AIProviderFileReference
                        do {
                            reference = try uploaded.validated(for: adapter.provider)
                        } catch AIProviderFileValidationError.providerMismatch {
                            throw AIAttachmentIssue.providerMismatch
                        } catch AIProviderFileValidationError.expiredReference {
                            throw AIAttachmentIssue.expiredReference
                        }
                        references.append(reference)
                        preparations[preparationIndex].state = .ready(reference)
                    }
                }
                preparedMessages.append(AIMessage(
                    role: message.role,
                    content: message.content,
                    toolCalls: message.toolCalls,
                    reasoningBlocks: message.reasoningBlocks,
                    toolCallId: message.toolCallId,
                    toolName: message.toolName,
                    attachments: direct,
                    providerFiles: references
                ))
            }
            return AIPreparedAttachmentTurn(
                messages: preparedMessages,
                preparations: preparations,
                references: createdReferences
            )
        } catch {
            for reference in createdReferences { try? await adapter.delete(reference) }
            throw error
        }
    }

    func release(
        _ references: [AIProviderFileReference],
        adapter: AIProviderAdapter,
        includeRetrieval: Bool = false
    ) async {
        for reference in references where includeRetrieval || reference.purpose != .retrieval {
            try? await adapter.delete(reference)
        }
    }
}
