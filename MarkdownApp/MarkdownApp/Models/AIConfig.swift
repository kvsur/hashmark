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
    /// 该接口/模型是否支持图片（视觉）输入。App 无法可靠判断任意 provider+model 的视觉能力
    /// （文本模型收到内联图片常返回 200 文字拒绝、事后难检测），故由用户在配置里自声明——
    /// 与 responseFormat 手动选同一思路。仅门控「添加图片」入口；文档引用是纯文本，不受此限。
    /// 默认 false：宁可让用户主动开启，也不默认发图给不支持的模型。
    var supportsImages: Bool = false

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

// MARK: - Codable 迁移

// supportsImages 是后加的字段，旧的已存配置 JSON 里没有这个键。
// Swift 合成的 Decodable 不认属性默认值——缺键会直接 keyNotFound 抛错、把整份旧配置读废。
// 故自定义 Decodable：缺 supportsImages 时回退 false。Encodable 仍用合成实现（含新键）。
extension AIConfig {
    enum CodingKeys: String, CodingKey {
        case baseURL, model, apiKey, responseFormat, supportsImages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        responseFormat = try container.decode(ResponseFormat.self, forKey: .responseFormat)
        supportsImages = try container.decodeIfPresent(Bool.self, forKey: .supportsImages) ?? false
    }
}
