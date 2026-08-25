//
//  QwenFileService.swift
//  MarkdownApp
//
//  DashScope Files upload/extract 生命周期。文件引用不会跨 Provider 泄漏。
//

import Foundation

actor QwenFileService {
    private struct FilePayload: Decodable {
        let id: String
        let name: String?
        let filename: String?
        let mimeType: String?
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, filename
            case mimeType = "mime_type"
            case expiresAt = "expires_at"
        }
    }

    private struct ContentPayload: Decodable {
        let content: String
    }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var pending: [String: QwenUploadedFile] = [:]

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func upload(_ input: AIFileUploadRequest) async throws -> AIProviderFileReference {
        let boundary = "MarkdownApp-\(UUID().uuidString)"
        var request = authenticatedRequest(url: filesEndpoint(), method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(input, boundary: boundary)
        let payload: FilePayload = try await send(request, as: FilePayload.self)
        let extractedText = input.purpose == .extraction
            ? try await extractContent(id: payload.id)
            : nil
        let uploaded = QwenUploadedFile(
            id: payload.id,
            name: payload.name ?? payload.filename ?? input.name,
            mimeType: payload.mimeType ?? input.mimeType,
            purpose: input.purpose,
            extractedText: extractedText
        )
        pending[payload.id] = uploaded
        var transport: [String: JSONValue] = [
            "name": .string(uploaded.name),
            "mime_type": .string(uploaded.mimeType)
        ]
        if let extractedText { transport["extracted_text"] = .string(extractedText) }
        return AIProviderFileReference(
            provider: .qwen,
            id: payload.id,
            purpose: input.purpose,
            expiresAt: payload.expiresAt,
            transportPayload: .object(transport)
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .qwen else { throw AIError.providerUnavailable }
        _ = try await sendData(authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(reference.id),
            method: "DELETE"
        ))
        pending.removeValue(forKey: reference.id)
    }

    func requestFiles() -> [QwenUploadedFile] {
        pending.values.sorted { $0.id < $1.id }
    }

    func didCompleteResponse() {
        pending = pending.filter { $0.value.purpose == .retrieval }
    }

    private func extractContent(id: String) async throws -> String {
        let request = authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(id).appendingPathComponent("content"),
            method: "GET"
        )
        return try await send(request, as: ContentPayload.self).content
    }

    private func filesEndpoint() -> URL {
        let endpoint = configuration.endpointURL
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/api/v1/files"
        return components.url!
    }

    private func authenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipartBody(_ input: AIFileUploadRequest, boundary: String) -> Data {
        var data = Data()
        data.appendQwenUTF8("--\(boundary)\r\n")
        data.appendQwenUTF8("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        data.appendQwenUTF8("\(purpose(input.purpose))\r\n")
        data.appendQwenUTF8("--\(boundary)\r\n")
        data.appendQwenUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safe(input.name))\"\r\n"
        )
        data.appendQwenUTF8("Content-Type: \(input.mimeType)\r\n\r\n")
        data.append(input.data)
        data.appendQwenUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    private func purpose(_ value: AIFilePurpose) -> String {
        switch value {
        case .directInput: "file-input"
        case .extraction: "file-extract"
        case .retrieval: "file-search"
        }
    }

    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendData(request)
        do { return try JSONDecoder.qwen.decode(T.self, from: data) }
        catch { throw AIError.stream(error.localizedDescription) }
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.stream("invalid_http_response")
            }
            AIDiagnostics.response(http, request: request)
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
            }
            return data
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.network(error)
        }
    }
}

private extension Data {
    nonisolated mutating func appendQwenUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}

private extension JSONDecoder {
    nonisolated static var qwen: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
