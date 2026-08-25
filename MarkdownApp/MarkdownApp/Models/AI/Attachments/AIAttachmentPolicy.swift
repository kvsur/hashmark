//
//  AIAttachmentPolicy.swift
//  MarkdownApp
//
//  Provider/model-aware MIME、数量、体积与原生路径 preflight 的唯一事实点。
//

import Foundation

nonisolated struct AIProviderAttachmentLimits: Equatable {
    let maxCount: Int
    let maxImageCount: Int
    let maxImageBytes: Int
    let maxDocumentBytes: Int
    let maxTotalBytes: Int
    let disallowsMixedImageAndDocument: Bool
}

nonisolated enum AIAttachmentPolicy {
    static func limits(for provider: AIProvider) -> AIProviderAttachmentLimits {
        // App 采用比上游更保守的边界，但每家独立建模；后续日期化刷新只改此处。
        switch provider {
        case .openAI:
            .init(maxCount: 10, maxImageCount: 4, maxImageBytes: 4 << 20,
                  maxDocumentBytes: 8 << 20, maxTotalBytes: 24 << 20,
                  disallowsMixedImageAndDocument: false)
        case .anthropic:
            .init(maxCount: 10, maxImageCount: 4, maxImageBytes: 5 << 20,
                  maxDocumentBytes: 8 << 20, maxTotalBytes: 28 << 20,
                  disallowsMixedImageAndDocument: false)
        case .gemini:
            .init(maxCount: 10, maxImageCount: 4, maxImageBytes: 4 << 20,
                  maxDocumentBytes: 8 << 20, maxTotalBytes: 20 << 20,
                  disallowsMixedImageAndDocument: false)
        case .kimi:
            .init(maxCount: 8, maxImageCount: 4, maxImageBytes: 4 << 20,
                  maxDocumentBytes: 8 << 20, maxTotalBytes: 24 << 20,
                  disallowsMixedImageAndDocument: false)
        case .glm:
            .init(maxCount: 6, maxImageCount: 4, maxImageBytes: 4 << 20,
                  maxDocumentBytes: 8 << 20, maxTotalBytes: 18 << 20,
                  disallowsMixedImageAndDocument: true)
        }
    }

    static func intent(
        for attachment: AIAttachment,
        configuration: ResolvedAIProviderConfiguration
    ) throws -> AIAttachmentIntent {
        switch attachment.kind {
        case .documentReference:
            // Text references are already flattened into visible prompt context. We still
            // resolve generic-file support, but never turn an unverified binary path into
            // a hidden upload or block the safe text baseline.
            _ = configuration.allowsKnownSafeRequest(.genericFileInput)
            return .textContext
        case .image:
            guard configuration.allowsKnownSafeRequest(.imageInput) else {
                throw AIAttachmentIssue.unsupportedByModel
            }
            return .directInput
        case .pdf:
            guard configuration.allowsKnownSafeRequest(.pdfInput) else {
                throw AIAttachmentIssue.unsupportedByModel
            }
            // Kimi 的普通文档契约明确走 Files/extract，不能伪装成视觉图片。
            if configuration.provider == .kimi,
               configuration.effectiveCapabilities.fileExtraction.isEnabled {
                return .extraction
            }
            guard configuration.effectiveCapabilities.inlinePDF.isEnabled else {
                if configuration.effectiveCapabilities.fileExtraction.isEnabled {
                    return .extraction
                }
                throw AIAttachmentIssue.unsupportedByModel
            }
            return .directInput
        }
    }

    static func validate(
        _ attachments: [AIAttachment],
        configuration: ResolvedAIProviderConfiguration
    ) throws -> [AIAttachmentPreparation] {
        let limits = limits(for: configuration.provider)
        guard attachments.count <= limits.maxCount else {
            throw AIAttachmentIssue.tooMany(maxCount: limits.maxCount)
        }
        let imageCount = attachments.filter { $0.imageJPEG != nil }.count
        guard imageCount <= limits.maxImageCount else {
            throw AIAttachmentIssue.tooMany(maxCount: limits.maxImageCount)
        }
        let estimatedBodyBytes = attachments.reduce(0) { $0 + $1.estimatedTransportBytes }
        guard estimatedBodyBytes <= limits.maxTotalBytes else {
            throw AIAttachmentIssue.totalTooLarge(maxBytes: limits.maxTotalBytes)
        }
        let hasImage = imageCount > 0
        let hasPDF = attachments.contains { $0.pdfPayload != nil }
        if limits.disallowsMixedImageAndDocument, hasImage, hasPDF {
            throw AIAttachmentIssue.mixedMediaUnsupported
        }

        return try attachments.map { attachment in
            let descriptor = attachment.uploadDescriptor
            guard ["image/jpeg", "application/pdf", "text/plain"].contains(descriptor.mimeType) else {
                throw AIAttachmentIssue.unsupportedMIME(descriptor.mimeType)
            }
            let maxBytes = attachment.imageJPEG == nil
                ? limits.maxDocumentBytes
                : limits.maxImageBytes
            guard descriptor.byteCount <= maxBytes else {
                throw AIAttachmentIssue.itemTooLarge(maxBytes: maxBytes)
            }
            return AIAttachmentPreparation(
                id: attachment.id,
                name: descriptor.name,
                mimeType: descriptor.mimeType,
                byteCount: descriptor.byteCount,
                intent: try intent(for: attachment, configuration: configuration),
                state: .validating
            )
        }
    }
}

nonisolated extension AIAttachment {
    var byteCount: Int {
        switch kind {
        case .image(let data), .pdf(let data, _): data.count
        case .documentReference(_, _, let text): text.utf8.count
        }
    }

    var uploadDescriptor: (name: String, mimeType: String, data: Data, byteCount: Int) {
        switch kind {
        case .image(let data):
            return ("image.jpg", "image/jpeg", data, data.count)
        case .pdf(let data, let name):
            return (name, "application/pdf", data, data.count)
        case .documentReference(_, let name, let text):
            let data = Data(text.utf8)
            return (name, "text/plain", data, data.count)
        }
    }

    /// direct input 会 base64 膨胀；preflight 用估算 wire body 而非只看原始文件大小。
    var estimatedTransportBytes: Int {
        switch kind {
        case .image(let data), .pdf(let data, _):
            return ((data.count + 2) / 3) * 4
        case .documentReference(_, _, let text):
            return text.utf8.count
        }
    }
}
