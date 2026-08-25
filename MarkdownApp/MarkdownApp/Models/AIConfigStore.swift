//
//  AIConfigStore.swift
//  MarkdownApp
//
//  Versioned Provider profiles in Application Support. The legacy AIConfig.json is
//  read once as a lossless migration source and left untouched as a recovery copy.
//

import Foundation

struct AIConfigStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.now = now
    }

    func load() -> AIConfig {
        loadDocument().activeProfile?.config ?? .empty
    }

    func load(provider: AIProvider) -> AIConfig {
        loadDocument().profile(for: provider)?.config
            ?? AIProviderProfile.makeDefault(provider: provider, at: now()).config
    }

    func profileID(for provider: AIProvider) -> UUID {
        loadDocument().profile(for: provider)?.id
            ?? AIProviderProfile.makeDefault(provider: provider, at: now()).id
    }

    func loadDocument() -> AISettingsDocument {
        if let data = try? Data(contentsOf: documentURL),
           let document = try? JSONDecoder().decode(AISettingsDocument.self, from: data),
           (try? AISettingsDocumentValidator.validate(document)) != nil {
            return document
        }
        let document = AISettingsDocument.bootstrap(legacy: loadLegacy(), at: now())
        try? persist(document)
        return document
    }

    func save(_ config: AIConfig) throws {
        var document = loadDocument()
        document.upsert(config, at: now())
        try AISettingsDocumentValidator.validate(document)
        try persist(document)
    }

    func reset(provider: AIProvider) throws {
        var document = loadDocument()
        document.reset(provider: provider, at: now())
        try AISettingsDocumentValidator.validate(document)
        try persist(document)
    }

    private var documentURL: URL {
        directoryURL.appendingPathComponent("AISettings.json")
    }

    private var legacyURL: URL {
        directoryURL.appendingPathComponent("AIConfig.json")
    }

    private func loadLegacy() -> AIConfig? {
        guard let data = try? Data(contentsOf: legacyURL) else { return nil }
        return try? JSONDecoder().decode(AIConfig.self, from: data)
    }

    private func persist(_ document: AISettingsDocument) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: documentURL, options: .atomic)
    }
}
