//
//  AIProviderCapabilityRules.swift
//  MarkdownApp
//
//  声明式 Manifest 到旧请求边界的兼容投影。型号与前缀不再定义在 Swift 中。
//

import Foundation

nonisolated enum AIProviderCapabilityRules {
    static func support(
        _ capability: AIModelCapability,
        provider: AIProvider
    ) -> CapabilitySupport {
        guard let policy = AIModelManifestRepository.shared.provider(provider) else {
            return .unsupported
        }
        return policy.legacySupport(for: capability)
    }
}
