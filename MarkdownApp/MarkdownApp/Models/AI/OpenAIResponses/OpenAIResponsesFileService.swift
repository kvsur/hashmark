//
//  OpenAIResponsesFileService.swift
//  MarkdownApp
//
//  OpenAI Files 与 Vector Store 生命周期。File ID/Vector Store ID 永不离开 OpenAI Adapter。
//

import Foundation

actor OpenAIResponsesFileService {
    struct RequestResources {
        let oneShotFileIDs: [String]
        let vectorStoreIDs: [String]
    }

    private struct FilePayload: Decodable {
        let id: String
        let expiresAt: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case expiresAt = "expires_at"
        }
    }

    private struct VectorStorePayload: Decodable {
        let id: String
    }

    private struct VectorStoreFilePayload: Decodable {
        let status: String
    }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var oneShotFileIDs: Set<String> = []
    private var retrievalFileIDs: Set<String> = []
    private var vectorStoreID: String?

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func upload(_ request: AIFileUploadRequest) async throws -> AIProviderFileReference {
        let boundary = "MarkdownApp-\(UUID().uuidString)"
        var urlRequest = authenticatedRequest(url: endpoint("files"), method: "POST")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = multipartBody(request: request, boundary: boundary)

        let payload: FilePayload = try await send(urlRequest, as: FilePayload.self)
        var transport: [String: JSONValue] = ["file_id": .string(payload.id)]
        if request.purpose == .retrieval {
            let storeID = try await ensureVectorStore()
            try await attach(fileID: payload.id, to: storeID)
            retrievalFileIDs.insert(payload.id)
            transport["vector_store_id"] = .string(storeID)
        } else {
            oneShotFileIDs.insert(payload.id)
        }
        return AIProviderFileReference(
            provider: .openAI,
            id: payload.id,
            purpose: request.purpose,
            expiresAt: payload.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            transportPayload: .object(transport)
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .openAI else { throw AIError.providerUnavailable }
        let request = authenticatedRequest(url: endpoint("files", reference.id), method: "DELETE")
        _ = try await sendData(request)
        oneShotFileIDs.remove(reference.id)
        retrievalFileIDs.remove(reference.id)
    }

    func requestResources() -> RequestResources {
        RequestResources(
            oneShotFileIDs: oneShotFileIDs.sorted(),
            vectorStoreIDs: vectorStoreID.map { [$0] } ?? []
        )
    }

    func didCompleteResponse() {
        oneShotFileIDs.removeAll()
    }

    private func ensureVectorStore() async throws -> String {
        if let vectorStoreID { return vectorStoreID }
        var request = authenticatedRequest(url: endpoint("vector_stores"), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "name": .string("MarkdownApp temporary retrieval"),
            "expires_after": .object([
                "anchor": .string("last_active_at"),
                "days": .number(1)
            ])
        ]))
        let payload: VectorStorePayload = try await send(request, as: VectorStorePayload.self)
        vectorStoreID = payload.id
        return payload.id
    }

    private func attach(fileID: String, to vectorStoreID: String) async throws {
        var request = authenticatedRequest(
            url: endpoint("vector_stores", vectorStoreID, "files"),
            method: "POST"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "file_id": .string(fileID)
        ]))
        let initial: VectorStoreFilePayload = try await send(request, as: VectorStoreFilePayload.self)
        if initial.status == "completed" { return }
        guard initial.status != "failed", initial.status != "cancelled" else {
            throw AIError.providerUnavailable
        }

        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(500))
            let statusRequest = authenticatedRequest(
                url: endpoint("vector_stores", vectorStoreID, "files", fileID),
                method: "GET"
            )
            let status: VectorStoreFilePayload = try await send(
                statusRequest,
                as: VectorStoreFilePayload.self
            )
            if status.status == "completed" { return }
            if status.status == "failed" || status.status == "cancelled" {
                throw AIError.providerUnavailable
            }
        }
        throw AIError.providerUnavailable
    }

    private func endpoint(_ components: String...) -> URL {
        components.reduce(configuration.endpointURL.deletingLastPathComponent()) {
            $0.appendingPathComponent($1)
        }
    }

    private func authenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func multipartBody(request: AIFileUploadRequest, boundary: String) -> Data {
        var data = Data()
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        data.appendUTF8("user_data\r\n")
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(request.name))\"\r\n"
        )
        data.appendUTF8("Content-Type: \(request.mimeType)\r\n\r\n")
        data.append(request.data)
        data.appendUTF8("\r\n--\(boundary)--\r\n")
        return data
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendData(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.stream(error.localizedDescription)
        }
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.stream("invalid_http_response")
            }
            AIDiagnostics.response(http, request: request)
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.http(
                    status: http.statusCode,
                    body: String(data: data, encoding: .utf8)
                )
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
