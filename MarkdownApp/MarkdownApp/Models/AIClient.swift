//
//  AIClient.swift
//  MarkdownApp
//
//  AI 流式请求层。格式完全由 AIConfig.responseFormat 决定、不假设 provider：
//  - ChatGPT：OpenAI 兼容 /chat/completions，Bearer 鉴权，SSE 取 choices[].delta.content
//  - Claude：Anthropic 兼容 /messages，x-api-key + anthropic-version，SSE 取 content_block_delta
//  BaseURL 由用户自填（官方或任意兼容端点）。共享的 SSE 读流/错误处理收敛在 SSEStream（DRY），
//  各 client 只负责「组请求」与「解析一行」。
//

import Foundation

// MARK: - 协议与工厂

protocol AIClient {
    /// 发起流式请求，逐段吐出增量文本（delta）。Task 取消即断流。
    func stream(messages: [AIMessage]) -> AsyncThrowingStream<String, Error>
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

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "尚未配置 AI，请先在设置中填写。"
        case .invalidURL:
            "BaseURL 无效，请检查 AI 配置。"
        case .http(let status, let body):
            switch status {
            case 401, 403: "鉴权失败（\(status)），请检查 API Key。"
            case 429: "请求过于频繁（429），请稍后再试。"
            default: "服务返回错误（\(status)）\(body.map { "：\($0)" } ?? "")"
            }
        case .network(let error):
            "网络错误：\(error.localizedDescription)"
        }
    }
}

// MARK: - 共享 SSE 读流

/// 一行 SSE 的解析结果。
enum SSELine {
    case token(String)   // 增量文本
    case done            // 明确结束
    case ignore          // 空行/事件行/无内容
}

enum SSEStream {
    /// 通用流式：发请求、校验状态码、逐行解析并 yield token。错误处理集中在此。
    static func run(
        request: URLRequest,
        parse: @escaping (String) -> SSELine
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
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
                        if Task.isCancelled { break }
                        switch parse(line) {
                        case .token(let text): continuation.yield(text)
                        case .done: continuation.finish(); return
                        case .ignore: continue
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 取 SSE 行里 `data:` 后的载荷；非 data 行返回 nil。
    static func dataPayload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - URL 拼接

private func endpointURL(base: String, path: String) -> URL? {
    var root = base.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !root.isEmpty else { return nil }
    if root.hasSuffix("/") { root = String(root.dropLast()) }
    // 兼容两种填法：用户填到 API 根（如 .../v1）则补 path；
    // 已填完整端点（如 .../v1/messages）则直接用，避免拼成 .../messages/messages 而 404。
    let full = root.hasSuffix(path) ? root : root + path
    return URL(string: full)
}

// MARK: - ChatGPT（OpenAI 兼容）

struct ChatGPTClient: AIClient {
    let config: AIConfig

    func stream(messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        do {
            let request = try makeRequest(messages)
            return SSEStream.run(request: request, parse: Self.parse)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func makeRequest(_ messages: [AIMessage]) throws -> URLRequest {
        guard let url = endpointURL(base: config.baseURL, path: "/chat/completions") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = Body(
            model: config.model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 解析一行：`data: {json}` 取 choices[0].delta.content；`data: [DONE]` 结束。
    private static func parse(_ line: String) -> SSELine {
        guard let payload = SSEStream.dataPayload(line) else { return .ignore }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let text = chunk.choices.first?.delta.content, !text.isEmpty
        else { return .ignore }
        return .token(text)
    }

    private struct Body: Encodable {
        let model: String
        let messages: [Msg]
        let stream = true
        struct Msg: Encodable { let role: String; let content: String }
    }

    private struct Chunk: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let delta: Delta
            struct Delta: Decodable { let content: String? }
        }
    }
}

// MARK: - Claude（Anthropic 兼容）

struct ClaudeClient: AIClient {
    let config: AIConfig
    /// Anthropic 要求必填 max_tokens；给一个足够大的默认值。
    private let maxTokens = 4096
    private let anthropicVersion = "2023-06-01"

    func stream(messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        do {
            let request = try makeRequest(messages)
            return SSEStream.run(request: request, parse: Self.parse)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    private func makeRequest(_ messages: [AIMessage]) throws -> URLRequest {
        guard let url = endpointURL(base: config.baseURL, path: "/messages") else {
            throw AIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        // Anthropic：system 是顶层字段，messages 只含 user/assistant。
        let system = messages.filter { $0.role == .system }
            .map(\.content).joined(separator: "\n\n")
        let turns = messages.filter { $0.role != .system }
            .map { Body.Msg(role: $0.role.rawValue, content: $0.content) }

        let body = Body(
            model: config.model,
            maxTokens: maxTokens,
            system: system.isEmpty ? nil : system,
            messages: turns
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 解析一行：只认 `data:` 里 type==content_block_delta 的 delta.text；message_stop 结束。
    private static func parse(_ line: String) -> SSELine {
        guard let payload = SSEStream.dataPayload(line),
              let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return .ignore }
        switch chunk.type {
        case "content_block_delta":
            if let text = chunk.delta?.text, !text.isEmpty { return .token(text) }
            return .ignore
        case "message_stop":
            return .done
        default:
            return .ignore
        }
    }

    private struct Body: Encodable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [Msg]
        let stream = true
        struct Msg: Encodable { let role: String; let content: String }

        enum CodingKeys: String, CodingKey {
            case model, system, messages, stream
            case maxTokens = "max_tokens"
        }
    }

    private struct Chunk: Decodable {
        let type: String
        let delta: Delta?
        struct Delta: Decodable { let text: String? }
    }
}
