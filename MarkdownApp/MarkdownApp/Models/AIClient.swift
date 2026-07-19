//
//  AIClient.swift
//  MarkdownApp
//
//  AI 流式请求层（协议 + 共享设施）。格式完全由 AIConfig.responseFormat 决定、不假设 provider。
//  支持 function tool calling：stream 产出 AIStreamEvent(.text/.toolCall)，工具调用需跨行累积，
//  故共享读流 SSEStream 采用「有状态解析器」（各 client 提供 SSEEventParser）。
//  端点不支持 tools 时优雅降级：带 tools 的请求若在产出任何内容前报 4xx，则无 tools 重试一次。
//  具体两格式实现见 ChatGPTClient / ClaudeClient。
//

import Foundation

// MARK: - 协议与工厂

protocol AIClient {
    /// 发起流式请求。tools 为空即普通生成；非空则允许模型发起工具调用。Task 取消即断流。
    func stream(messages: [AIMessage], tools: [AITool]) -> AsyncThrowingStream<AIStreamEvent, Error>
}

enum AIClientFactory {
    static func make(_ config: AIConfig) -> AIClient {
        switch config.responseFormat {
        case .chatGPT: ChatGPTClient(config: config)
        case .claude: ClaudeClient(config: config)
        }
    }
}

// MARK: - 错误

enum AIError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String?)
    case network(Error)

    /// 这些文案会经 AIWritingSession 的 error 阶段直达用户，属界面文案，需本地化。
    /// 必须走 LocalizationController.string 而非 Foundation 的 String(localized:)——
    /// 后者绕过取词拦截、只认系统语言，App 内切了语言也不会变（原因见 LocalizationController）。
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            LocalizationController.string("AI is not configured yet. Fill it in under Settings first.")
        case .invalidURL:
            LocalizationController.string("The base URL is invalid. Check your AI configuration.")
        case .http(let status, let body):
            switch status {
            case 401, 403: LocalizationController.string("Authentication failed (\(status)). Check your API key.")
            case 429: LocalizationController.string("Too many requests (429). Try again shortly.")
            // 响应体可能是大段 HTML/JSON 错误页，截断后再展示，避免文案爆炸、影响可读性。
            // 有无响应体分成两个独立句子，而不是拼一段可选后缀——拼接会把标点和语序写死。
            default:
                if let body {
                    LocalizationController.string("The service returned an error (\(status)): \(Self.truncated(body))")
                } else {
                    LocalizationController.string("The service returned an error (\(status)).")
                }
            }
        case .network(let error):
            LocalizationController.string("Network error: \(error.localizedDescription)")
        }
    }

    /// 截断过长的错误体：只保留开头一段，避免把整页 HTML/JSON 堆进提示里。
    private static func truncated(_ text: String, limit: Int = 300) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }
}

// MARK: - 多模态 user 消息装配（两家共用）

/// 把「文本 + 富媒体块（图片/PDF）」的 user 消息拼成 content blocks 数组：文本块在前、媒体块在后。
/// 各类媒体块结构两家不同（图片：ChatGPT image_url / Claude image source；PDF：ChatGPT file / Claude document），
/// 故由各 client 自行把附件映射成 mediaBlocks 交进来，这里只负责统一的「文本块 + 媒体块」装配（DRY）。
enum MultimodalContent {
    static func userContent(text: String, mediaBlocks: [JSONValue]) -> JSONValue {
        var blocks: [JSONValue] = []
        // 仅在有正文时加文本块，避免多余空块。
        if !text.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        blocks.append(contentsOf: mediaBlocks)
        return .array(blocks)
    }
}

// MARK: - 有状态 SSE 解析器

/// 跨行累积的 SSE 事件解析器：每消费一行，产出零或多个事件；done 表示流应结束。
/// 工具调用的 arguments 往往分散在多行，故解析器需持有累积状态（各 client 各自实现）。
protocol SSEEventParser: AnyObject {
    func consume(_ line: String) -> (events: [AIStreamEvent], done: Bool)
}

// MARK: - 共享读流与降级重试

enum SSEStream {
    /// 发请求、校验状态码、逐行喂给解析器并把事件交给 emit。HTTP/网络错误以 throw 抛出；取消经 Task 协作中断。
    static func pump(
        request: URLRequest,
        parser: SSEEventParser,
        emit: (AIStreamEvent) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            // 非 2xx：把响应体读出来当错误信息，便于定位。
            var body = ""
            for try await line in bytes.lines { body += line }
            throw AIError.http(status: http.statusCode, body: body.isEmpty ? nil : body)
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let (events, done) = parser.consume(line)
            for event in events { emit(event) }
            if done { return }
        }
    }

    /// 组织一次带「工具降级重试」的流式：先按给定 tools 请求；若带着 tools 且在产出任何内容前
    /// 报 4xx（端点很可能不支持 function tools），则无 tools 重试一次，保证可用性。
    /// makeRequest/makeParser 由各 client 提供（闭包注入，DRY）。
    static func streamWithToolFallback(
        tools: [AITool],
        makeRequest: @escaping ([AITool]) throws -> URLRequest,
        makeParser: @escaping () -> SSEEventParser
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var emitted = false
                let emit: (AIStreamEvent) -> Void = { event in
                    emitted = true
                    continuation.yield(event)
                }
                do {
                    try await pump(request: try makeRequest(tools), parser: makeParser(), emit: emit)
                    continuation.finish()
                } catch let error as AIError {
                    if case .http(let status, _) = error,
                       !tools.isEmpty, !emitted, (400..<500).contains(status) {
                        // 降级：无 tools 重试一次。makeRequest 用同一份 messages 重建请求，
                        // 只去掉 tools、不动消息内容——故带图请求在降级重试时仍带上图片块。
                        do {
                            try await pump(request: try makeRequest([]), parser: makeParser(), emit: emit)
                            continuation.finish()
                        } catch is CancellationError {
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: error)
                    }
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 取 SSE 行里 `data:` 后的载荷；非 data 行（如 `event:`、空行）返回 nil。
    static func dataPayload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - URL 拼接

/// 由用户填写的 baseURL 推导最终请求端点，尽量兼容各种填法（关键：Anthropic 官方与多数三方代理的
/// baseURL 都不带 /v1，所以默认要补上版本段，否则会拼成缺 /v1 的地址而 404）：
/// - 只填到主机根（如 https://api.anthropic.com）→ 自动补 /v1/<endpoint>；
/// - 填到版本根（如 .../v1）→ 只补 /<endpoint>，不重复 /v1；
/// - 已填完整端点（如 .../v1/messages，或某些代理的 .../messages）→ 原样使用，
///   既避免拼成 .../messages/messages，也尊重不带 /v1 的自定义代理。
func aiEndpointURL(base: String, endpoint: String, version: String = "v1") -> URL? {
    var root = base.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else { return nil }
    while root.hasSuffix("/") { root = String(root.dropLast()) }

    let endpointPath = "/" + endpoint   // "/messages"、"/chat/completions"
    let versionPath = "/" + version     // "/v1"

    // 1) 已是完整端点（无论带不带版本段）：原样用。
    if root.hasSuffix(endpointPath) { return URL(string: root) }
    // 2) 已带版本段：只补端点，避免 .../v1/v1/messages。
    if root.hasSuffix(versionPath) { return URL(string: root + endpointPath) }
    // 3) 只到主机根或自定义前缀：补版本段 + 端点。
    return URL(string: root + versionPath + endpointPath)
}
