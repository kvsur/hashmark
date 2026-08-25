//
//  AIModelCatalogStore.swift
//  MarkdownApp
//
//  按 Provider 持久化用户账号实际返回的模型列表。它只改善设置页选择体验；
//  高级能力仍由日期化 manifest 决定，动态列表不能自动取得搜索/图片等权限。
//

import Foundation

struct AIModelCatalogStore {
    private struct Storage: Codable {
        var modelIDsByProvider: [String: [String]] = [:]
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "AIModelCatalog.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func modelIDs(for provider: AIProvider) -> [String] {
        load().modelIDsByProvider[provider.rawValue] ?? []
    }

    func save(_ snapshot: AIModelCatalogSnapshot) {
        var storage = load()
        storage.modelIDsByProvider[snapshot.provider.rawValue] = Self.normalized(
            snapshot.modelIDs
        )
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func load() -> Storage {
        guard let data = defaults.data(forKey: storageKey),
              let storage = try? JSONDecoder().decode(Storage.self, from: data)
        else { return Storage() }
        return storage
    }

    private static func normalized(_ values: [String]) -> [String] {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(trimmed)).sorted()
    }
}
