//
//  AnthropicFileService.swift
//  MarkdownApp
//
//  Anthropic Files beta 生命周期。file_id 仅存活在此 Adapter 实例内。
//

import Foundation

actor AnthropicFileService {
    private struct FilePayload: Decodable {
        let id: String
        let mimeType: String

        enum CodingKeys: String, CodingKey {
            case id
            case mimeType = "mime_type"
        }
    }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var pending: [String: AnthropicUploadedFile] = [:]

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
        pending[payload.id] = AnthropicUploadedFile(
            id: payload.id,
            mimeType: payload.mimeType,
            purpose: input.purpose
        )
        return AIProviderFileReference(
            provider: .anthropic,
            id: payload.id,
            purpose: input.purpose,
            expiresAt: nil,
            transportPayload: .object(["mime_type": .string(payload.mimeType)])
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .anthropic else { throw AIError.providerUnavailable }
        _ = try await sendData(authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(reference.id),
            method: "DELETE"
        ))
        pending.removeValue(forKey: reference.id)
    }

    func requestFiles() -> [AnthropicUploadedFile] {
        pending.values.sorted { $0.id < $1.id }
    }

    func didCompleteResponse() {
        pending = pending.filter { $0.value.purpose == .retrieval }
    }

    private func filesEndpoint() -> URL {
        configuration.endpointURL.deletingLastPathComponent().appendingPathComponent("files")
    }

    private func authenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("files-api-2025-04-14", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipartBody(_ input: AIFileUploadRequest, boundary: String) -> Data {
        var data = Data()
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safe(input.name))\"\r\n"
        )
        data.appendUTF8("Content-Type: \(input.mimeType)\r\n\r\n")
        data.append(input.data)
        data.appendUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendData(request)
        do { return try JSONDecoder().decode(T.self, from: data) }
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
    nonisolated mutating func appendUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}
