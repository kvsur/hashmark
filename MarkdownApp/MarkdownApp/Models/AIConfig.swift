//
//  AIConfig.swift
//  MarkdownApp
//
//  AI API 配置模型。Codable 便于以 JSON 持久化（见 AIConfigStore）。
//  含敏感 APIKey，故存 Application Support 而非 Documents。
//

import Foundation

struct AIConfig: Codable, Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
    var responseFormat: ResponseFormat

    /// 上游响应体协议格式：决定日后如何解析 AI 返回（本期仅存配置，不发请求）。
    enum ResponseFormat: String, Codable, CaseIterable, Identifiable {
        case chatGPT
        case claude

        var id: String { rawValue }

        var label: String {
            switch self {
            case .chatGPT: "ChatGPT"
            case .claude: "Claude"
            }
        }
    }

    /// 尚未配置时的空默认值（首次进入 AI 配置即空表单）。
    static let empty = AIConfig(baseURL: "", model: "", apiKey: "", responseFormat: .chatGPT)

    /// AI 入口前置校验：三项必填都非空（responseFormat 有默认，不计）。
    /// 任一为空即不得进入 AI 模式（见 AIConfigGate）。
    var isComplete: Bool {
        [baseURL, model, apiKey].allSatisfy {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 由 baseURL 推断响应格式；推不出时为 nil。
    ///
    /// 只认 anthropic 这一个信号，且只往 .claude 一个方向推：
    /// URL 里带 anthropic 基本可断定是 Anthropic 协议（官方域名，或如 .../anthropic 这类兼容前缀）；
    /// 但「不带 anthropic」并不能反推是 OpenAI 协议——大量 Claude 兼容代理的域名里没有这个词，
    /// 反向自动切会把正确配置改坏。故只在有正面证据时给建议，其余一律交回用户。
    ///
    /// 存在的理由：格式与端点不匹配时上游只回 404，没有任何线索指向「格式选错了」，排查成本很高。
    var suggestedResponseFormat: ResponseFormat? {
        baseURL.localizedCaseInsensitiveContains("anthropic") ? .claude : nil
    }
}
