//
//  AICapabilityVerificationRecorder.swift
//  MarkdownApp
//
//  Converts real Adapter outcomes into scoped capability evidence. Only an
//  unambiguous provider rejection may become unsupported; operational failures
//  stay inconclusive and can never downgrade a model.
//

import Foundation

nonisolated enum AICapabilityFailureClassifier {
    static func classify(_ error: Error) -> AICapabilityFailureKind {
        if error is CancellationError { return .cancelled }
        guard let error = error as? AIError else {
            if let urlError = error as? URLError {
                return urlError.code == .cancelled ? .cancelled : .network
            }
            return .unknown
        }
        switch error {
        case .http(let status, let body):
            return AICapabilityFailurePolicy.classifyHTTP(status: status, body: body)
        case .remote(_, let code, let message):
            guard let status = AIError.equivalentHTTPStatus(code: code, message: message) else {
                return .invalidRequest
            }
            return AICapabilityFailurePolicy.classifyHTTP(status: status, body: message)
        case .network(let underlying):
            if let urlError = underlying as? URLError, urlError.code == .cancelled {
                return .cancelled
            }
            return .network
        case .webSearchNotExecuted, .stream:
            return .invalidRequest
        case .notConfigured, .dataSharingConsentRequired, .invalidURL, .providerUnavailable,
             .webSearchUnavailable:
            return .invalidRequest
        }
    }

}

nonisolated enum AICapabilityVerificationRecorder {
    static func recordNativeSearchSuccess(
        configuration: ResolvedAIProviderConfiguration
    ) {
        guard configuration.usesNativeWebSearch else { return }
        AICapabilityVerificationStore().recordSuccess(
            profileID: configuration.profileID,
            provider: configuration.provider,
            endpoint: configuration.baseURL,
            model: configuration.model,
            capability: .nativeWebSearch,
            reasonCode: "native_search_executed"
        )
    }

    static func recordNativeSearchFailure(
        _ error: Error,
        configuration: ResolvedAIProviderConfiguration
    ) {
        guard configuration.webSearchRequested else { return }
        AICapabilityVerificationStore().recordFailure(
            profileID: configuration.profileID,
            provider: configuration.provider,
            endpoint: configuration.baseURL,
            model: configuration.model,
            capability: .nativeWebSearch,
            failure: AICapabilityFailureClassifier.classify(error)
        )
    }
}
