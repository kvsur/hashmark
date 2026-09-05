//
//  FileStore.swift
//  MarkdownApp
//
//  基于 FileManager 的文档存储服务。
//  所有文档存放在 App 沙盒的 Documents 目录，目录结构即真实文件夹嵌套（支持无限级）。
//  只负责「磁盘读写」，不含 UI 逻辑（遵循 CLAUDE.md：视图轻量、逻辑外移）。
//

import Foundation

nonisolated struct FileStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let accessCoordinator: any FileAccessCoordinating
    private let defaultDocumentName: String

    let markdownExtension = "md"
    let rootURL: URL
    let inboxURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL,
        localInboxURL: URL,
        accessCoordinator: any FileAccessCoordinating,
        defaultDocumentName: String = "Untitled"
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        inboxURL = localInboxURL
        self.accessCoordinator = accessCoordinator
        self.defaultDocumentName = defaultDocumentName
    }

    /// 判断某 URL 是否落在系统 Inbox 内（含 Inbox 目录自身）。
    private func isInInbox(_ url: URL) -> Bool {
        let inbox = inboxURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == inbox || path.hasPrefix(inbox + "/")
    }

    // MARK: - 读取

    /// 列出某目录的直接子项：文件夹在前，两组分别按有效更新时间降序排列。
    /// 文件夹时间来自其后代 Markdown 的最新修改时间；同时间以自然名称稳定兜底。
    func contents(of directory: URL) throws -> [DocumentNode] {
        try accessCoordinator.read(at: directory) { coordinatedURL in
            activityRecords(in: coordinatedURL).map(documentNode(from:))
        }
    }

    /// 递归读出某目录下的整棵树（文件夹在前）。文件为叶子（children=nil），
    /// 文件夹的 children 为其内容（可能为空数组）。供 S10 快速切换器的折叠树使用。
    func tree(of directory: URL) throws -> [DocumentTreeNode] {
        try accessCoordinator.read(at: directory) { coordinatedURL in
            activityRecords(in: coordinatedURL).map(documentTreeNode(from:))
        }
    }

    // MARK: - 新建

    /// 在指定目录新建文件夹，返回新建 URL。名称冲突时自动追加序号。
    @discardableResult
    func createFolder(named name: String, in directory: URL) throws -> URL {
        try accessCoordinator.write(at: directory, options: .forMerging) { coordinatedDirectory in
            let url = uniqueURL(for: sanitized(name), extension: nil, in: coordinatedDirectory)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        }
    }

    /// 在指定目录新建空 Markdown 文档，返回新建 URL。
    @discardableResult
    func createMarkdown(named name: String, in directory: URL) throws -> URL {
        try accessCoordinator.write(at: directory, options: .forMerging) { coordinatedDirectory in
            let url = uniqueURL(for: sanitized(name), extension: markdownExtension, in: coordinatedDirectory)
            try Data().write(to: url, options: .atomic)
            return url
        }
    }

    // MARK: - 修改

    /// 重命名节点（保留原扩展名）。
    @discardableResult
    func rename(_ node: DocumentNode, to newName: String) throws -> URL {
        let directory = node.url.deletingLastPathComponent()
        let ext = node.isFolder ? nil : node.url.pathExtension
        let destination = uniqueURL(
            for: sanitized(newName),
            extension: ext,
            in: directory,
            excluding: node.url
        )
        guard destination.standardizedFileURL != node.url.standardizedFileURL else {
            return node.url
        }
        return try accessCoordinator.move(from: node.url, to: destination) { source, destination in
            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    /// 删除节点（文件夹递归删除）。
    func delete(_ node: DocumentNode) throws {
        try accessCoordinator.write(at: node.url, options: .forDeleting) { coordinatedURL in
            try fileManager.removeItem(at: coordinatedURL)
        }
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

        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? markdownExtension : source.pathExtension
        let destination = uniqueURL(for: sanitized(base), extension: ext, in: directory)
        try accessCoordinator.readWrite(reading: source, writing: destination) { coordinatedSource, coordinatedDestination in
            let data = try Data(contentsOf: coordinatedSource)
            try data.write(to: coordinatedDestination, options: .atomic)
        }

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
        return try accessCoordinator.move(from: node.url, to: destination) { source, destination in
            try fileManager.moveItem(at: source, to: destination)
            return destination
        }
    }

    // MARK: - 文本读写（供 S3 预览 / S4 编辑复用）

    func readText(at url: URL) throws -> String {
        try accessCoordinator.read(at: url) { coordinatedURL in
            do {
                return try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch let error as CocoaError where error.code == .fileReadInapplicableStringEncoding {
                throw DocumentLibraryError.unreadableText(url)
            }
        }
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
    func readExternalText(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try accessCoordinator.read(at: url) { coordinatedURL in
            do {
                return try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch let error as CocoaError where error.code == .fileReadInapplicableStringEncoding {
                throw DocumentLibraryError.unreadableText(url)
            }
        }
    }

    func writeText(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw DocumentLibraryError.unreadableText(url)
        }
        try accessCoordinator.write(at: url, options: .forReplacing) { coordinatedURL in
            try data.write(to: coordinatedURL, options: .atomic)
        }
    }

    // MARK: - 工具

    private func activityRecords(in directory: URL) -> [DocumentActivityRecord] {
        DocumentActivityResolver(fileManager: fileManager, markdownExtension: markdownExtension)
            .records(in: directory, excluding: inboxURL)
    }

    private func documentNode(from record: DocumentActivityRecord) -> DocumentNode {
        DocumentNode(
            url: record.url,
            kind: record.isFolder ? .folder : .markdown,
            modifiedAt: record.modifiedAt,
            fileSize: record.fileSize,
            childCount: record.childCount
        )
    }

    private func documentTreeNode(from record: DocumentActivityRecord) -> DocumentTreeNode {
        DocumentTreeNode(
            node: documentNode(from: record),
            children: record.children?.map(documentTreeNode(from:))
        )
    }

    /// 生成目录内不冲突的 URL：若已存在则追加 " 2"、" 3"…
    private func uniqueURL(
        for base: String,
        extension ext: String?,
        in directory: URL,
        excluding excludedURL: URL? = nil
    ) -> URL {
        func make(_ name: String) -> URL {
            let full = ext.map { "\(name).\($0)" } ?? name
            return directory.appendingPathComponent(full)
        }
        var candidate = make(base)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path)
            && candidate.standardizedFileURL != excludedURL?.standardizedFileURL {
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
        return trimmed.isEmpty ? defaultDocumentName : trimmed
    }
}
