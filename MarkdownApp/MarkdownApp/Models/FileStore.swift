//
//  FileStore.swift
//  MarkdownApp
//
//  基于 FileManager 的文档存储服务。
//  所有文档存放在 App 沙盒的 Documents 目录，目录结构即真实文件夹嵌套（支持无限级）。
//  只负责「磁盘读写」，不含 UI 逻辑（遵循 CLAUDE.md：视图轻量、逻辑外移）。
//

import Foundation

struct FileStore {
    private let fileManager = FileManager.default

    let markdownExtension = "md"

    /// 所有文档的根目录：沙盒 Documents（可经 Info.plist 暴露给系统「文件」App）。
    var rootURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 读取

    /// 列出某目录的直接子项：文件夹在前，同类按名称自然排序。
    func contents(of directory: URL) -> [DocumentNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes: [DocumentNode] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            // 只展示文件夹与 .md 文件，其它类型忽略。
            if !isDir && url.pathExtension.lowercased() != markdownExtension {
                return nil
            }
            return DocumentNode(
                url: url,
                kind: isDir ? .folder : .markdown,
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }

        return nodes.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }   // 文件夹在前
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 递归读出某目录下的整棵树（文件夹在前）。文件为叶子（children=nil），
    /// 文件夹的 children 为其内容（可能为空数组）。供 S10 快速切换器的折叠树使用。
    func tree(of directory: URL) -> [DocumentTreeNode] {
        contents(of: directory).map { node in
            node.isFolder
                ? DocumentTreeNode(node: node, children: tree(of: node.url))
                : DocumentTreeNode(node: node, children: nil)
        }
    }

    // MARK: - 新建

    /// 在指定目录新建文件夹，返回新建 URL。名称冲突时自动追加序号。
    @discardableResult
    func createFolder(named name: String, in directory: URL) throws -> URL {
        let url = uniqueURL(for: sanitized(name), extension: nil, in: directory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// 在指定目录新建空 Markdown 文档，返回新建 URL。
    @discardableResult
    func createMarkdown(named name: String, in directory: URL) throws -> URL {
        let url = uniqueURL(for: sanitized(name), extension: markdownExtension, in: directory)
        try Data().write(to: url)
        return url
    }

    // MARK: - 修改

    /// 重命名节点（保留原扩展名）。
    @discardableResult
    func rename(_ node: DocumentNode, to newName: String) throws -> URL {
        let directory = node.url.deletingLastPathComponent()
        let ext = node.isFolder ? nil : node.url.pathExtension
        let destination = uniqueURL(for: sanitized(newName), extension: ext, in: directory)
        try fileManager.moveItem(at: node.url, to: destination)
        return destination
    }

    /// 删除节点（文件夹递归删除）。
    func delete(_ node: DocumentNode) throws {
        try fileManager.removeItem(at: node.url)
    }

    /// 把外部文件（分享/「打开方式」传入）拷贝进目标目录，返回新文件 URL（S6 导入落库）。
    /// 源 URL 可能受安全作用域保护；重名自动加序号；无扩展名按 md 兜底。
    @discardableResult
    func importFile(from source: URL, to directory: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? markdownExtension : source.pathExtension
        let destination = uniqueURL(for: sanitized(base), extension: ext, in: directory)
        try data.write(to: destination)
        return destination
    }

    /// 把节点移动到目标目录下（供后续 S6 导入复用）。
    @discardableResult
    func move(_ node: DocumentNode, to directory: URL) throws -> URL {
        let ext = node.isFolder ? nil : node.url.pathExtension
        let base = node.isFolder ? node.name : node.url.deletingPathExtension().lastPathComponent
        let destination = uniqueURL(for: base, extension: ext, in: directory)
        try fileManager.moveItem(at: node.url, to: destination)
        return destination
    }

    // MARK: - 文本读写（供 S3 预览 / S4 编辑复用）

    func readText(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// 判断某文件是否已在本 App 的 Documents 目录内（S11：据此决定是否显示「导入」）。
    /// 先解析符号链接再比路径，避免 /var 与 /private/var 之类差异导致误判。
    func isInsideStore(_ url: URL) -> Bool {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        return target == root || target.hasPrefix(root + "/")
    }

    /// 读取来自「文件」App 等外部来源的文本（S5 导入预览）。
    /// 外部 URL 受安全作用域保护，须先 start/stop AccessingSecurityScopedResource；
    /// 读不到返回 nil，供调用方区分「空文件」与「打不开」。
    func readExternalText(at url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func writeText(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url)
    }

    // MARK: - 工具

    /// 生成目录内不冲突的 URL：若已存在则追加 " 2"、" 3"…
    private func uniqueURL(for base: String, extension ext: String?, in directory: URL) -> URL {
        func make(_ name: String) -> URL {
            let full = ext.map { "\(name).\($0)" } ?? name
            return directory.appendingPathComponent(full)
        }
        var candidate = make(base)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(index)")
            index += 1
        }
        return candidate
    }

    /// 清理用户输入名称：去首尾空白、替换路径分隔符，空则给默认名。
    private func sanitized(_ name: String) -> String {
        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return trimmed.isEmpty ? "未命名" : trimmed
    }
}
