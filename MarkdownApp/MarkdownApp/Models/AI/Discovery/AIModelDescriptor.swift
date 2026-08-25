//
//  AIModelDescriptor.swift
//  MarkdownApp
//
//  Provider models API 的无损通用投影。缺失字段保持 nil/unknown，不解释成 false。
//

import Foundation

nonisolated enum AIModelDiscoverySource: String, Codable, Equatable, Sendable {
    case providerAPI
    case bundledManifest
    case localSnapshot
}

nonisolated struct AIModelProviderMetadata: Codable, Equatable, Sendable {
    var createdAt: Date?
    var owner: String?
    var version: String?
    var description: String?
    var inputTokenLimit: Int?
    var outputTokenLimit: Int?
    var shutdownAt: Date?
    var generationMethods: [String]
    var capabilitySignals: [AIModelCapability: Bool]
    var additionalFields: [String: String]

    init(
        createdAt: Date? = nil,
        owner: String? = nil,
        version: String? = nil,
        description: String? = nil,
        inputTokenLimit: Int? = nil,
        outputTokenLimit: Int? = nil,
        shutdownAt: Date? = nil,
        generationMethods: [String] = [],
        capabilitySignals: [AIModelCapability: Bool] = [:],
        additionalFields: [String: String] = [:]
    ) {
        self.createdAt = createdAt
        self.owner = owner
        self.version = version
        self.description = description
        self.inputTokenLimit = inputTokenLimit
        self.outputTokenLimit = outputTokenLimit
        self.shutdownAt = shutdownAt
        self.generationMethods = generationMethods
        self.capabilitySignals = capabilitySignals
        self.additionalFields = additionalFields
    }
}

nonisolated struct AIModelDescriptor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var displayName: String?
    var metadata: AIModelProviderMetadata
    var lifecycle: AIModelLifecycle
    var source: AIModelDiscoverySource
    var firstSeenAt: Date
    var lastSeenAt: Date
    var missingCount: Int

    var isWritingCandidate: Bool {
        metadata.generationMethods.isEmpty
            || metadata.generationMethods.contains(where: {
                ["generatecontent", "streamgeneratecontent", "messages", "responses", "chat"]
                    .contains($0.lowercased())
            })
    }
}

