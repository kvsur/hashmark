//
//  AIConfigStore.swift
//  MarkdownApp
//
//  AI 配置的本地持久化：以 JSON 存 Library/Application Support/AIConfig.json。
//  选此目录而非 Documents——不对系统「文件」App 可见，适合放配置与敏感凭证。
//  只负责磁盘读写，不含 UI 逻辑（遵 CLAUDE.md：逻辑外移）。
//

import Foundation

struct AIConfigStore {
    private let fileManager = FileManager.default
    private let fileName = "AIConfig.json"

    /// Application Support 下的配置文件 URL。该目录默认可能不存在，写入前需创建。
    private var fileURL: URL {
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    /// 读取配置；文件缺失或损坏一律返回空默认值（首次进入即空表单）。
    func load() -> AIConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AIConfig.self, from: data)
        else { return .empty }
        return config
    }

    /// 保存配置：确保目录存在后原子写入 JSON。
    func save(_ config: AIConfig) throws {
        let url = fileURL
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(config)
        try data.write(to: url, options: .atomic)
    }
}
