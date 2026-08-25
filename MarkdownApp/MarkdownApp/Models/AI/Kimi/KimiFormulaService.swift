//
//  KimiFormulaService.swift
//  MarkdownApp
//
//  Kimi 官方 Formula 工具声明与 Fiber 执行。搜索结果由 Moonshot 返回为受保护的
//  encrypted_output，只能原样交回同一 Provider，不能在 App 中解读或记录。
//

import Foundation
#if DEBUG
import OSLog
#endif

nonisolated enum KimiFormulaContract {
    static let webSearchURI = "moonshot/web-search:latest"
    static let webSearchToolName = "web_search"

    static func makeToolsRequest(
        configuration: ResolvedAIProviderConfiguration
    ) -> URLRequest {
        authorizedRequest(
            url: KimiNativeEndpoints.formulaTools(from: configuration.endpointURL),
            configuration: configuration
        )
    }

    static func makeFiberRequest(
        configuration: ResolvedAIProviderConfiguration,
        name: String,
        arguments: String
    ) throws -> URLRequest {
        var request = authorizedRequest(
            url: KimiNativeEndpoints.formulaFibers(from: configuration.endpointURL),
            configuration: configuration
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "name": .string(name),
            "arguments": .string(arguments)
        ]))
        return request
    }

    static func webSearchTool(from data: Data) throws -> JSONValue {
        let response = try JSONDecoder().decode(KimiFormulaToolsResponse.self, from: data)
        guard let tool = response.tools.first(where: { toolName($0) == webSearchToolName })
        else { throw KimiWireError.missingFormulaTool }
        return tool
    }

    static func fiberOutput(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(KimiFormulaFiberResponse.self, from: data)
        guard response.status == "succeeded",
              let result = response.context?.output?.nonEmpty
                ?? response.context?.encryptedOutput?.nonEmpty
        else { throw KimiWireError.invalidFormulaResult }
        return result
    }

    static func webSearchArguments(query: String) throws -> String {
        let data = try JSONEncoder().encode(JSONValue.object(["query": .string(query)]))
        guard let value = String(data: data, encoding: .utf8) else {
            throw KimiWireError.invalidFormulaResult
        }
        return value
    }

    static func appendingWebSearchResult(
        to messages: [AIMessage],
        callID: String,
        arguments: String,
        result: String
    ) -> [AIMessage] {
        messages + [
            .assistant(
                text: "",
                toolCalls: [AIToolCall(
                    id: callID,
                    name: webSearchToolName,
                    arguments: arguments
                )]
            ),
            .toolResult(callId: callID, name: webSearchToolName, content: result)
        ]
    }

    private static func authorizedRequest(
        url: URL,
        configuration: ResolvedAIProviderConfiguration
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120
        return request
    }

    private static func toolName(_ value: JSONValue) -> String? {
        guard case .object(let tool) = value,
              case .object(let function)? = tool["function"],
              case .string(let name)? = function["name"]
        else { return nil }
        return name
    }
}

nonisolated private struct KimiFormulaToolsResponse: Decodable {
    let tools: [JSONValue]
}

nonisolated private struct KimiFormulaFiberResponse: Decodable {
    struct Context: Decodable {
        let output: String?
        let encryptedOutput: String?

        enum CodingKeys: String, CodingKey {
            case output
            case encryptedOutput = "encrypted_output"
        }
    }

    let status: String
    let context: Context?
}

private extension String {
    nonisolated var nonEmpty: String? { isEmpty ? nil : self }
}

actor KimiFormulaService {
#if DEBUG
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MarkdownApp",
        category: "AI"
    )
#endif

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var cachedWebSearchTool: JSONValue?

    init(
        configuration: ResolvedAIProviderConfiguration,
        session: URLSession
    ) {
        self.configuration = configuration
        self.session = session
    }

    func webSearchTool() async throws -> JSONValue {
        if let cachedWebSearchTool { return cachedWebSearchTool }
        let request = KimiFormulaContract.makeToolsRequest(configuration: configuration)
        let data = try await responseData(for: request, stage: "tools")
        let tool = try KimiFormulaContract.webSearchTool(from: data)
        cachedWebSearchTool = tool
        return tool
    }

    func executeWebSearch(arguments: String) async throws -> String {
        let request = try KimiFormulaContract.makeFiberRequest(
            configuration: configuration,
            name: KimiFormulaContract.webSearchToolName,
            arguments: arguments
        )
        let data = try await responseData(for: request, stage: "fiber")
        return try KimiFormulaContract.fiberOutput(from: data)
    }

    private func responseData(for request: URLRequest, stage: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KimiWireError.invalidEvent
        }
#if DEBUG
        Self.logger.notice(
            "[AI-Debug] kimi-formula stage=\(stage, privacy: .public) status=\(http.statusCode)"
        )
#endif
        guard (200..<300).contains(http.statusCode) else {
            throw KimiWireError.remote(
                type: "http_status_\(http.statusCode)",
                message: String(data: data.prefix(32_768), encoding: .utf8)
                    ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return data
    }
}
