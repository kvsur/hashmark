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

    /// 系统在「拷贝到本 App」时自动创建的收件目录 Documents/Inbox。
    /// 由系统管理（只可读/删、不可写），属暂存区而非用户目录：不展示、不可选为目标，
    /// 导入后其中的源件应被清理。
    var inboxURL: URL {
        rootURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// 判断某 URL 是否落在系统 Inbox 内（含 Inbox 目录自身）。
    private func isInInbox(_ url: URL) -> Bool {
        let inbox = inboxURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == inbox || path.hasPrefix(inbox + "/")
    }

    // MARK: - 读取

    /// 列出某目录的直接子项：文件夹在前，同类按名称自然排序。
    /// 顺带读入元信息（文件大小 / 目录子项数），供列表副标题展示。
    func contents(of directory: URL) -> [DocumentNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let nodes: [DocumentNode] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            // 隐藏系统 Inbox（暂存区，非用户目录）：不进浏览器、也不进选目录器。
            if isDir && url.standardizedFileURL == inboxURL.standardizedFileURL {
                return nil
            }
            // 只展示文件夹与 .md 文件，其它类型忽略。
            if !isDir && url.pathExtension.lowercased() != markdownExtension {
                return nil
            }
            return DocumentNode(
                url: url,
                kind: isDir ? .folder : .markdown,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                fileSize: isDir ? nil : values?.fileSize.map(Int64.init),
                // 文件夹子项数用浅层计数，不递归（避免列一层就读整棵树）。
                childCount: isDir ? visibleChildCount(of: url) : nil
            )
        }

        return nodes.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }   // 文件夹在前
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 某目录下「本 App 可见项」（文件夹 + .md，排除系统 Inbox）的浅层数量。
    /// 只读一层、不构建节点、不递归，用于列表里目录行的「N 项」。
    private func visibleChildCount(of directory: URL) -> Int {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return urls.reduce(into: 0) { count, url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if url.standardizedFileURL != inboxURL.standardizedFileURL { count += 1 }
            } else if url.pathExtension.lowercased() == markdownExtension {
                count += 1
            }
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

    /// 清空系统 Inbox 里的残留源件（如取消导入留下的），best-effort，不抛错。
    /// 仅在导入中间页关闭后调用——此时正在导入的文件要么已消费、要么已被用户放弃，
    /// 故不会误删正在处理的传入文件（规避冷启动即打开文件的竞态）。
    func purgeInbox() {
        guard let items = try? fileManager.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: nil
        ) else { return }
        for item in items { try? fileManager.removeItem(at: item) }
    }

    /// 把外部文件（分享/「打开方式」传入）拷贝进目标目录，返回新文件 URL（S6 导入落库）。
    /// 源 URL 可能受安全作用域保护；重名自动加序号；无扩展名按 md 兜底。
    /// 若源件来自系统 Inbox（暂存区），拷贝成功后清理它，避免 Inbox 残留与重复。
    @discardableResult
    func importFile(from source: URL, to directory: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? markdownExtension : source.pathExtension
        let destination = uniqueURL(for: sanitized(base), extension: ext, in: directory)
        try data.write(to: destination)

        // 只清理落在本 App Inbox 内的源件；外部安全作用域文件（如经文件 App 选取）绝不删。
        if isInInbox(source) {
            try? fileManager.removeItem(at: source)
        }
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

    /// 判断某文件是否已是本 App 目录内的「真实文档」（S11：据此决定是否显示「导入」）。
    /// 先解析符号链接再比路径，避免 /var 与 /private/var 之类差异导致误判。
    func isInsideStore(_ url: URL) -> Bool {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let inbox = inboxURL.resolvingSymlinksInPath().standardizedFileURL.path
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        // 系统 Inbox 是分享/「打开方式」的落点、暂存区，不算用户目录里的真实文档，
        // 判否好让只读预览把「导入」按钮显示出来（否则分享进来的文件无法入库）。
        if target == inbox || target.hasPrefix(inbox + "/") { return false }
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
        // 兜底文件名会落进用户的文档库，按当前界面语言取词。
        return trimmed.isEmpty ? LocalizationController.string("Untitled") : trimmed
    }
}
