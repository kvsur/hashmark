//
//  AIModelCatalogDiff.swift
//  MarkdownApp
//
//  成功目录之间的可审计差异；一次 missing 不会删除已保存模型。
//

import Foundation

nonisolated struct AIModelRenameCandidate: Codable, Equatable, Sendable {
    let missingID: String
    let addedID: String
    let reason: String
}

nonisolated struct AIModelCatalogDiff: Codable, Equatable, Sendable {
    let provider: AIProvider
    let scopeKey: String
    let comparedAt: Date
    let added: [String]
    let missing: [String]
    let metadataChanged: [String]
    let lifecycleChanged: [String]
    let renameCandidates: [AIModelRenameCandidate]

    var isEmpty: Bool {
        added.isEmpty && missing.isEmpty && metadataChanged.isEmpty
            && lifecycleChanged.isEmpty && renameCandidates.isEmpty
    }
}

nonisolated enum AIModelCatalogDiffEngine {
    static func compare(
        previous: AIModelCatalogSnapshot?,
        current: AIModelCatalogSnapshot
    ) -> AIModelCatalogDiff {
        let old = Dictionary(uniqueKeysWithValues: (previous?.models ?? []).map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: current.models.map { ($0.id, $0) })
        let oldIDs = Set(old.keys)
        let newIDs = Set(new.keys)
        let added = newIDs.subtracting(oldIDs).sorted()
        let missing = oldIDs.subtracting(newIDs).sorted()
        let shared = oldIDs.intersection(newIDs)
        let metadataChanged = shared.filter { old[$0]?.metadata != new[$0]?.metadata }.sorted()
        let lifecycleChanged = shared.filter { old[$0]?.lifecycle != new[$0]?.lifecycle }.sorted()
        return AIModelCatalogDiff(
            provider: current.provider,
            scopeKey: current.scopeKey,
            comparedAt: current.fetchedAt,
            added: added,
            missing: missing,
            metadataChanged: metadataChanged,
            lifecycleChanged: lifecycleChanged,
            renameCandidates: renameCandidates(
                missing: missing.compactMap { old[$0] },
                added: added.compactMap { new[$0] }
            )
        )
    }

    static func mergeLastGood(
        previous: AIModelCatalogSnapshot?,
        current: AIModelCatalogSnapshot
    ) -> AIModelCatalogSnapshot {
        guard let previous else { return current }
        var result = Dictionary(uniqueKeysWithValues: current.models.map { ($0.id, $0) })
        for old in previous.models where result[old.id] == nil {
            var missing = old
            missing.missingCount += 1
            if missing.missingCount >= 3, missing.lifecycle == .active {
                missing.lifecycle = .deprecated
            }
            result[missing.id] = missing
        }
        return current.replacing(models: result.values.sorted { $0.id < $1.id })
    }

    private static func renameCandidates(
        missing: [AIModelDescriptor],
        added: [AIModelDescriptor]
    ) -> [AIModelRenameCandidate] {
        missing.compactMap { old in
            guard let match = added.first(where: { candidate in
                if let oldName = old.displayName?.lowercased(),
                   let newName = candidate.displayName?.lowercased(),
                   oldName == newName { return true }
                return old.metadata.owner != nil
                    && old.metadata.owner == candidate.metadata.owner
                    && old.metadata.createdAt == candidate.metadata.createdAt
            }) else { return nil }
            return AIModelRenameCandidate(
                missingID: old.id,
                addedID: match.id,
                reason: "matching provider metadata"
            )
        }
    }
}

