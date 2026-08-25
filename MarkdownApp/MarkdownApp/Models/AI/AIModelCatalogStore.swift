//
//  AIModelCatalogStore.swift
//  MarkdownApp
//
//  profile + Provider + normalized endpoint scoped v2 cache。失败/空响应不会调用 save，
//  成功 missing 会保留 last-good 并累积 lifecycle evidence。
//

import Foundation

struct AIModelCatalogStore {
    private struct Storage: Codable {
        var version = 2
        var snapshotsByScope: [String: AIModelCatalogSnapshot] = [:]
        var diffHistory: [AIModelCatalogDiff] = []
    }

    private struct LegacyStorage: Codable {
        var modelIDsByProvider: [String: [String]] = [:]
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let legacyStorageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "AIModelCatalog.v2",
        legacyStorageKey: String = "AIModelCatalog.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.legacyStorageKey = legacyStorageKey
    }

    func modelIDs(for provider: AIProvider) -> [String] {
        latestSnapshot(for: provider)?.modelIDs ?? migratedLegacyModelIDs(for: provider)
    }

    func modelIDs(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String
    ) -> [String] {
        snapshot(profileID: profileID, provider: provider, endpoint: endpoint)?.modelIDs ?? []
    }

    func snapshot(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String
    ) -> AIModelCatalogSnapshot? {
        let key = scopeKey(profileID: profileID, provider: provider, endpoint: endpoint)
        return load().snapshotsByScope[key]
    }

    func latestSnapshot(for provider: AIProvider) -> AIModelCatalogSnapshot? {
        load().snapshotsByScope.values
            .filter { $0.provider == provider }
            .max { $0.fetchedAt < $1.fetchedAt }
    }

    func diffHistory(for provider: AIProvider) -> [AIModelCatalogDiff] {
        load().diffHistory.filter { $0.provider == provider }
    }

    @discardableResult
    func save(_ snapshot: AIModelCatalogSnapshot) -> AIModelCatalogDiff? {
        guard !snapshot.models.isEmpty else { return nil }
        var storage = load()
        let previous = storage.snapshotsByScope[snapshot.scopeKey]
        let diff = AIModelCatalogDiffEngine.compare(previous: previous, current: snapshot)
        let merged = AIModelCatalogDiffEngine.mergeLastGood(previous: previous, current: snapshot)
        storage.snapshotsByScope[snapshot.scopeKey] = merged
        if !diff.isEmpty {
            storage.diffHistory.append(diff)
            storage.diffHistory = Array(storage.diffHistory.suffix(100))
        }
        persist(storage)
        return diff
    }

    private func load() -> Storage {
        guard let data = defaults.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode(Storage.self, from: data)
        else { return Storage() }
        return storage
    }

    private func persist(_ storage: Storage) {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func migratedLegacyModelIDs(for provider: AIProvider) -> [String] {
        guard let data = defaults.data(forKey: legacyStorageKey),
              let legacy = try? JSONDecoder().decode(LegacyStorage.self, from: data)
        else { return [] }
        return normalized(legacy.modelIDsByProvider[provider.rawValue] ?? [])
    }

    private func scopeKey(
        profileID: UUID,
        provider: AIProvider,
        endpoint: String
    ) -> String {
        "\(profileID.uuidString.lowercased())|\(provider.rawValue)|\(AIModelCatalogScope.normalizedEndpoint(endpoint))"
    }

    private func normalized(_ values: [String]) -> [String] {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(trimmed)).sorted()
    }
}
