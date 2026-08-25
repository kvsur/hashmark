import Foundation

nonisolated struct GLMModelDiscoveryStrategy: AIModelDiscoveryStrategy {
    let provider = AIProvider.glm
    let isAvailable = false
    let catalogPath = ""

    func parse(_ data: Data, observedAt: Date) throws -> AIModelDiscoveryPage {
        throw AIModelCatalogError.unavailable
    }
}

