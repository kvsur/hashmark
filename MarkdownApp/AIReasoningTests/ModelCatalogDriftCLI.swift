import Foundation

private struct AuditModel: Codable, Equatable {
    let id: String
    let displayName: String?
    let lifecycle: String
    let metadata: [String: String]
}

private struct AuditSnapshot: Codable {
    let schemaVersion: Int
    let protocolEvidenceVersion: String
    let provider: String
    let endpoint: String
    let capturedAt: String
    let models: [AuditModel]
}

private struct RenameCandidate: Codable, Equatable {
    let missingID: String
    let addedID: String
}

private struct DriftReport: Codable {
    let schemaDrift: [String]
    let added: [String]
    let missing: [String]
    let renameCandidates: [RenameCandidate]
    let lifecycleChanged: [String]
    let metadataChanged: [String]

    var isEmpty: Bool {
        schemaDrift.isEmpty && added.isEmpty && missing.isEmpty
            && renameCandidates.isEmpty && lifecycleChanged.isEmpty
            && metadataChanged.isEmpty
    }
}

@main
enum ModelCatalogDriftCLI {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            FileHandle.standardError.write(
                Data("usage: model-catalog-drift <baseline.json> <candidate.json>\n".utf8)
            )
            exit(64)
        }
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(
            AuditSnapshot.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        )
        let candidate = try decoder.decode(
            AuditSnapshot.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        )
        let report = compare(baseline, candidate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(report.isEmpty ? 0 : 2)
    }

    private static func compare(
        _ baseline: AuditSnapshot,
        _ candidate: AuditSnapshot
    ) -> DriftReport {
        var schemaDrift: [String] = []
        if baseline.schemaVersion != candidate.schemaVersion {
            schemaDrift.append("schemaVersion")
        }
        if baseline.protocolEvidenceVersion != candidate.protocolEvidenceVersion {
            schemaDrift.append("protocolEvidenceVersion")
        }
        if baseline.provider != candidate.provider { schemaDrift.append("provider") }
        if baseline.endpoint != candidate.endpoint { schemaDrift.append("endpoint") }

        let old = Dictionary(uniqueKeysWithValues: baseline.models.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: candidate.models.map { ($0.id, $0) })
        let oldIDs = Set(old.keys)
        let newIDs = Set(new.keys)
        let added = newIDs.subtracting(oldIDs).sorted()
        let missing = oldIDs.subtracting(newIDs).sorted()
        let shared = oldIDs.intersection(newIDs)
        let lifecycleChanged = shared.filter {
            old[$0]?.lifecycle != new[$0]?.lifecycle
        }.sorted()
        let metadataChanged = shared.filter {
            old[$0]?.displayName != new[$0]?.displayName
                || old[$0]?.metadata != new[$0]?.metadata
        }.sorted()
        let renameCandidates = missing.compactMap { missingID -> RenameCandidate? in
            guard let missingModel = old[missingID],
                  let addedID = added.first(where: {
                      guard let addedModel = new[$0] else { return false }
                      if let oldName = missingModel.displayName?.lowercased(),
                         let newName = addedModel.displayName?.lowercased(),
                         oldName == newName { return true }
                      return missingModel.metadata["owner"] != nil
                          && missingModel.metadata["owner"] == addedModel.metadata["owner"]
                          && missingModel.metadata["createdAt"] == addedModel.metadata["createdAt"]
                  })
            else { return nil }
            return RenameCandidate(missingID: missingID, addedID: addedID)
        }.sorted { $0.missingID < $1.missingID }

        return DriftReport(
            schemaDrift: schemaDrift.sorted(),
            added: added,
            missing: missing,
            renameCandidates: renameCandidates,
            lifecycleChanged: lifecycleChanged,
            metadataChanged: metadataChanged
        )
    }
}
