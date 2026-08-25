//
//  AICapabilityDecision.swift
//  MarkdownApp
//
//  Resolver 与 UI/Adapter 之间的可解释逐项能力结果。
//

import Foundation

nonisolated enum AICapabilityState: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unverified
}

nonisolated enum AICapabilitySource: String, Codable, Equatable, Sendable {
    case providerMetadata
    case exactManifest
    case familyManifest
    case runtimeVerification
    case conservativeFallback
}

nonisolated enum AICapabilityDecisionConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

nonisolated struct AICapabilityDecision: Codable, Equatable, Sendable {
    let capability: AIModelCapability
    let state: AICapabilityState
    let source: AICapabilitySource
    let confidence: AICapabilityDecisionConfidence
    let reason: String
    let observedAt: Date?
    let manifestVersion: String
    let protocolVersion: String
    let trialEligible: Bool

    var allowsKnownSafeRequest: Bool { state == .supported }
    var allowsTrialRequest: Bool { state == .supported || trialEligible }
}

nonisolated enum AICapabilityEvidenceOutcome: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case inconclusive
}

nonisolated struct AICapabilityEvidence: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let profileID: UUID
    let provider: AIProvider
    let normalizedEndpoint: String
    let model: String
    let capability: AIModelCapability
    let outcome: AICapabilityEvidenceOutcome
    let observedAt: Date
    let expiresAt: Date
    let manifestVersion: String
    let protocolVersion: String
    let reasonCode: String
}

