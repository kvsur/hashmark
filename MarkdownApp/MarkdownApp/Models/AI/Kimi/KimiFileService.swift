//
//  KimiFileService.swift
//  MarkdownApp
//
//  Moonshot Files/extract 生命周期；普通文档先提取，再作为文本进入 chat。
//

import Foundation

actor KimiFileService {
    private struct FilePayload: Decodable {
        let id: String
        let filename: String?
        let bytes: Int?
        let createdAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case id, filename, bytes
            case createdAt = "created_at"
        }
    }

    private struct ContentPayload: Decodable { let content: String }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var pending: [String: KimiUploadedFile] = [:]

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
        let isMedia = input.mimeType.hasPrefix("image/") || input.mimeType.hasPrefix("video/")
        let extracted = isMedia && input.purpose == .directInput
            ? nil
            : try await extractContent(id: payload.id)
        let uploaded = KimiUploadedFile(
            id: payload.id,
            name: payload.filename ?? input.name,
            mimeType: input.mimeType,
            purpose: input.purpose,
            extractedText: extracted
        )
        pending[payload.id] = uploaded
        var transport: [String: JSONValue] = [
            "name": .string(uploaded.name),
            "mime_type": .string(uploaded.mimeType)
        ]
        if let extracted { transport["extracted_text"] = .string(extracted) }
        return AIProviderFileReference(
            provider: .kimi,
            id: payload.id,
            purpose: input.purpose,
            expiresAt: nil,
            transportPayload: .object(transport)
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .kimi else { throw AIError.providerUnavailable }
        _ = try await sendData(authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(reference.id),
            method: "DELETE"
        ))
        pending.removeValue(forKey: reference.id)
    }

    func requestFiles() -> [KimiUploadedFile] {
        pending.values.sorted { $0.id < $1.id }
    }

    func didCompleteResponse() {
        pending.removeAll()
    }

    private func extractContent(id: String) async throws -> String {
        let request = authenticatedRequest(
            url: filesEndpoint().appendingPathComponent(id).appendingPathComponent("content"),
            method: "GET"
        )
        let data = try await sendData(request)
        if let payload = try? JSONDecoder().decode(ContentPayload.self, from: data) {
            return payload.content
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw AIError.stream("invalid_file_content")
        }
        return text
    }

    private func filesEndpoint() -> URL {
        KimiNativeEndpoints.files(from: configuration.endpointURL)
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
        data.appendKimiUTF8("--\(boundary)\r\n")
        data.appendKimiUTF8("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        data.appendKimiUTF8("\(uploadPurpose(input))\r\n")
        data.appendKimiUTF8("--\(boundary)\r\n")
        data.appendKimiUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safe(input.name))\"\r\n"
        )
        data.appendKimiUTF8("Content-Type: \(input.mimeType)\r\n\r\n")
        data.append(input.data)
        data.appendKimiUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func uploadPurpose(_ input: AIFileUploadRequest) -> String {
        if input.purpose == .directInput, input.mimeType.hasPrefix("image/") { return "image" }
        if input.purpose == .directInput, input.mimeType.hasPrefix("video/") { return "video" }
        return "file-extract"
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
    nonisolated mutating func appendKimiUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}
