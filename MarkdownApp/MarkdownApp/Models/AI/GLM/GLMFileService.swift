//
//  GLMFileService.swift
//  MarkdownApp
//
//  BigModel Files 生命周期。返回的 file URL 仅进入 GLM 视觉消息。
//

import Foundation

actor GLMFileService {
    private struct FilePayload: Decodable {
        let id: String
        let url: String?
        let filename: String?
        let mimeType: String?
        let expiresAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case id, url, filename
            case mimeType = "mime_type"
            case expiresAt = "expires_at"
        }
    }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var pending: [String: GLMUploadedFile] = [:]

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func upload(_ input: AIFileUploadRequest) async throws -> AIProviderFileReference {
        guard configuration.effectiveCapabilities.uploadedFileReference.isEnabled else {
            throw GLMWireError.unsupportedInput
        }
        let boundary = "MarkdownApp-\(UUID().uuidString)"
        var request = authenticatedRequest(url: filesEndpoint(), method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(input, boundary: boundary)
        let payload: FilePayload = try await send(request, as: FilePayload.self)
        let url = payload.url ?? "file://\(payload.id)"
        let uploaded = GLMUploadedFile(
            id: payload.id,
            url: url,
            name: payload.filename ?? input.name,
            mimeType: payload.mimeType ?? input.mimeType,
            purpose: input.purpose
        )
        pending[payload.id] = uploaded
        return AIProviderFileReference(
            provider: .glm,
            id: payload.id,
            purpose: input.purpose,
            expiresAt: payload.expiresAt.map(Date.init(timeIntervalSince1970:)),
            transportPayload: .object([
                "url": .string(uploaded.url),
                "name": .string(uploaded.name),
                "mime_type": .string(uploaded.mimeType)
            ])
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .glm else { throw AIError.providerUnavailable }
        _ = try await sendData(authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(reference.id),
            method: "DELETE"
        ))
        pending.removeValue(forKey: reference.id)
    }

    func requestFiles() -> [GLMUploadedFile] {
        pending.values.sorted { $0.id < $1.id }
    }

    func didCompleteResponse() {
        pending.removeAll()
    }

    private func filesEndpoint() -> URL {
        let endpoint = configuration.endpointURL
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/api/paas/v4/files"
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
        data.appendGLMUTF8("--\(boundary)\r\n")
        data.appendGLMUTF8("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        data.appendGLMUTF8("file-input\r\n")
        data.appendGLMUTF8("--\(boundary)\r\n")
        data.appendGLMUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safe(input.name))\"\r\n"
        )
        data.appendGLMUTF8("Content-Type: \(input.mimeType)\r\n\r\n")
        data.append(input.data)
        data.appendGLMUTF8("\r\n--\(boundary)--\r\n")
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
    nonisolated mutating func appendGLMUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}
