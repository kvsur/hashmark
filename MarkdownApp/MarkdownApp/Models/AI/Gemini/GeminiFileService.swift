//
//  GeminiFileService.swift
//  MarkdownApp
//
//  Gemini resumable Files 与 File Search Store 生命周期。资源名不离开 Gemini Adapter。
//

import Foundation

actor GeminiFileService {
    struct RequestResources {
        let directFiles: [GeminiUploadedFile]
        let fileSearchStoreNames: [String]
    }

    private struct UploadEnvelope: Decodable {
        let file: FilePayload
    }

    private struct FilePayload: Decodable {
        let name: String
        let uri: String
        let mimeType: String
        let expirationTime: String?

        enum CodingKeys: String, CodingKey {
            case name, uri
            case mimeType = "mimeType"
            case expirationTime = "expirationTime"
        }
    }

    private struct StorePayload: Decodable { let name: String }
    private struct OperationPayload: Decodable {
        let name: String?
        let done: Bool?
        let error: GeminiWireErrorPayload?
    }

    private let configuration: ResolvedAIProviderConfiguration
    private let session: URLSession
    private var directFiles: [String: GeminiUploadedFile] = [:]
    private var retrievalFiles: Set<String> = []
    private var fileSearchStoreName: String?

    init(configuration: ResolvedAIProviderConfiguration, session: URLSession) {
        self.configuration = configuration
        self.session = session
    }

    func upload(_ input: AIFileUploadRequest) async throws -> AIProviderFileReference {
        let uploadURL = try await startUpload(input)
        let payload = try await finalizeUpload(input, uploadURL: uploadURL)
        let file = GeminiUploadedFile(
            name: payload.name,
            uri: payload.uri,
            mimeType: payload.mimeType,
            purpose: input.purpose
        )
        var transport: [String: JSONValue] = [
            "uri": .string(payload.uri),
            "mime_type": .string(payload.mimeType)
        ]
        if input.purpose == .retrieval {
            let store = try await ensureFileSearchStore()
            try await importFile(payload.name, into: store)
            retrievalFiles.insert(payload.name)
            transport["file_search_store_name"] = .string(store)
        } else {
            directFiles[payload.name] = file
        }
        return AIProviderFileReference(
            provider: .gemini,
            id: payload.name,
            purpose: input.purpose,
            expiresAt: payload.expirationTime.flatMap(ISO8601DateFormatter().date),
            transportPayload: .object(transport)
        )
    }

    func delete(_ reference: AIProviderFileReference) async throws {
        guard reference.provider == .gemini else { throw AIError.providerUnavailable }
        var request = authenticatedRequest(url: apiURL("v1beta", reference.id), method: "DELETE")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        _ = try await sendData(request)
        directFiles.removeValue(forKey: reference.id)
        retrievalFiles.remove(reference.id)
    }

    func requestResources() -> RequestResources {
        RequestResources(
            directFiles: directFiles.values.sorted { $0.name < $1.name },
            fileSearchStoreNames: fileSearchStoreName.map { [$0] } ?? []
        )
    }

    func didCompleteResponse() {
        directFiles.removeAll()
    }

    private func startUpload(_ input: AIFileUploadRequest) async throws -> URL {
        var request = authenticatedRequest(url: apiURL("upload", "v1beta", "files"), method: "POST")
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(input.data.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        request.setValue(input.mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "file": .object(["display_name": .string(input.name)])
        ]))
        let (_, response) = try await rawData(request)
        guard let value = response.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let url = URL(string: value)
        else { throw GeminiWireError.missingUploadURL }
        return url
    }

    private func finalizeUpload(
        _ input: AIFileUploadRequest,
        uploadURL: URL
    ) async throws -> FilePayload {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(input.data.count), forHTTPHeaderField: "Content-Length")
        request.setValue(input.mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = input.data
        return try await send(request, as: UploadEnvelope.self).file
    }

    private func ensureFileSearchStore() async throws -> String {
        if let fileSearchStoreName { return fileSearchStoreName }
        var request = authenticatedRequest(url: apiURL("v1beta", "fileSearchStores"), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object([
            "displayName": .string("MarkdownApp temporary retrieval"),
            "embedding_model": .string("models/gemini-embedding-2")
        ]))
        let payload: StorePayload = try await send(request, as: StorePayload.self)
        fileSearchStoreName = payload.name
        return payload.name
    }

    private func importFile(_ name: String, into store: String) async throws {
        let path = store + ":importFile"
        var request = authenticatedRequest(url: apiURL("v1beta", path), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["fileName": .string(name)]))
        var operation: OperationPayload = try await send(request, as: OperationPayload.self)
        guard operation.error == nil else { throw AIError.providerUnavailable }
        for _ in 0..<60 where operation.done != true {
            try await Task.sleep(for: .milliseconds(500))
            guard let operationName = operation.name else { throw AIError.providerUnavailable }
            operation = try await send(
                authenticatedRequest(url: apiURL("v1beta", operationName), method: "GET"),
                as: OperationPayload.self
            )
            if operation.error != nil { throw AIError.providerUnavailable }
        }
        guard operation.done == true else { throw AIError.providerUnavailable }
    }

    private func apiURL(_ components: String...) -> URL {
        let endpoint = configuration.endpointURL
        var url = URLComponents()
        url.scheme = endpoint.scheme
        url.host = endpoint.host
        url.port = endpoint.port
        url.path = "/" + components.joined(separator: "/")
        return url.url!
    }

    private func authenticatedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await sendData(request)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AIError.stream(error.localizedDescription) }
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        try await rawData(request).0
    }

    private func rawData(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.stream("invalid_http_response")
            }
            AIDiagnostics.response(http, request: request)
            guard (200..<300).contains(http.statusCode) else {
                throw AIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
            }
            return (data, http)
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIError.network(error)
        }
    }
}
