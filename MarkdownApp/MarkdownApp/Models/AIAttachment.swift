//
//  AIAttachment.swift
//  MarkdownApp
//
//  用户在发起 AI 生成前附加的一件上下文素材（供应商无关的中立表示）。
//  两类附件走两条不同的消费路径，别混为一谈：
//  - image：压缩后的 JPEG，由各 client 在序列化时拼成多模态图片块（OpenAI image_url / Anthropic image source）。
//  - documentReference：库内文档的正文，由 AIAction 在装配 user 文本时以 <reference> 注入，不进图片块。
//  带 id 便于附件条 UI 做 ForEach 与删除；消息层只关心其内容。
//

import Foundation

nonisolated struct AIAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: Kind

    enum Kind: Equatable {
        /// 已压缩降采样的 JPEG 数据（见 ImageAttachmentEncoder），media_type 固定 image/jpeg。
        case image(Data)
        /// 引用的库内文档：源 URL（用于去重/预勾选）+ 展示名 + 正文文本。
        /// url 只作附件条身份标识，消息层与 client 都不消费它。
        case documentReference(url: URL, name: String, text: String)
        /// 外部 PDF 文件：原始 PDF 数据 + 文件名。走原生多模态文档块（受视觉门控），
        /// 而非本地提取文本——保留版式与图，代价是依赖模型支持、跨 provider 兼容性不一。
        case pdf(data: Data, name: String)
    }

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    static func image(_ jpeg: Data) -> AIAttachment { AIAttachment(kind: .image(jpeg)) }
    static func documentReference(url: URL, name: String, text: String) -> AIAttachment {
        AIAttachment(kind: .documentReference(url: url, name: name, text: text))
    }
    static func pdf(data: Data, name: String) -> AIAttachment {
        AIAttachment(kind: .pdf(data: data, name: name))
    }

    /// 图片附件的 JPEG 数据；非图片为 nil（供 client 序列化图片块时筛选）。
    var imageJPEG: Data? {
        if case .image(let data) = kind { return data }
        return nil
    }

    /// PDF 附件的（文件名, 数据）；非 PDF 为 nil（供 client 序列化文档块时筛选）。
    var pdfPayload: (name: String, data: Data)? {
        if case .pdf(let data, let name) = kind { return (name, data) }
        return nil
    }

    /// 引用文档的源 URL；非文档引用为 nil（供附件条去重/预勾选）。
    var referencedURL: URL? {
        if case .documentReference(let url, _, _) = kind { return url }
        return nil
    }
}
