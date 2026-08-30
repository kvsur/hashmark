//
//  DocumentActivityResolver.swift
//  MarkdownApp
//
//  单次扫描文档目录，计算文件夹的真实活动时间并生成稳定排序的轻量快照。
//

import Foundation

nonisolated struct DocumentActivityRecord: Hashable, Sendable {
    enum Kind: Hashable {
        case folder
        case markdown
    }

    let url: URL
    let kind: Kind
    /// Markdown 文件为自身修改时间；文件夹为后代 Markdown 最新时间，空树回退目录时间。
    let modifiedAt: Date
    let fileSize: Int64?
    let children: [DocumentActivityRecord]?

    nonisolated var isFolder: Bool {
        switch kind {
        case .folder: true
        case .markdown: false
        }
    }
    var childCount: Int? { children?.count }
}

nonisolated struct DocumentActivityResolver {
    private struct DirectorySnapshot {
        let records: [DocumentActivityRecord]
        /// 只传播 Markdown 文件时间；空子目录自身时间不能提升祖先目录。
        let latestMarkdownDate: Date?
    }

    private let fileManager: FileManager
    private let markdownExtension: String

    init(fileManager: FileManager = .default, markdownExtension: String = "md") {
        self.fileManager = fileManager
        self.markdownExtension = markdownExtension.lowercased()
    }

    func records(in directory: URL, excluding excludedDirectory: URL? = nil) -> [DocumentActivityRecord] {
        var visitedDirectories = Set<String>()
        return scan(
            directory: directory,
            excludedDirectory: excludedDirectory?.standardizedFileURL,
            visitedDirectories: &visitedDirectories
        ).records
    }

    private func scan(
        directory: URL,
        excludedDirectory: URL?,
        visitedDirectories: inout Set<String>
    ) -> DirectorySnapshot {
        let canonicalPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard visitedDirectories.insert(canonicalPath).inserted else {
            return DirectorySnapshot(records: [], latestMarkdownDate: nil)
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return DirectorySnapshot(records: [], latestMarkdownDate: nil)
        }

        var records: [DocumentActivityRecord] = []
        var latestMarkdownDate: Date?

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true else { continue }

            let ownDate = values.contentModificationDate ?? .distantPast
            if values.isDirectory == true {
                if url.standardizedFileURL == excludedDirectory { continue }

                let childSnapshot = scan(
                    directory: url,
                    excludedDirectory: excludedDirectory,
                    visitedDirectories: &visitedDirectories
                )
                if let childLatest = childSnapshot.latestMarkdownDate {
                    latestMarkdownDate = Self.later(latestMarkdownDate, childLatest)
                }
                records.append(DocumentActivityRecord(
                    url: url,
                    kind: .folder,
                    modifiedAt: childSnapshot.latestMarkdownDate ?? ownDate,
                    fileSize: nil,
                    children: childSnapshot.records
                ))
            } else if url.pathExtension.lowercased() == markdownExtension {
                latestMarkdownDate = Self.later(latestMarkdownDate, ownDate)
                records.append(DocumentActivityRecord(
                    url: url,
                    kind: .markdown,
                    modifiedAt: ownDate,
                    fileSize: values.fileSize.map(Int64.init),
                    children: nil
                ))
            }
        }

        return DirectorySnapshot(
            records: records.sorted(by: Self.isOrderedBefore),
            latestMarkdownDate: latestMarkdownDate
        )
    }

    private nonisolated static func later(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return max(current, candidate)
    }

    private nonisolated static func isOrderedBefore(
        _ lhs: DocumentActivityRecord,
        _ rhs: DocumentActivityRecord
    ) -> Bool {
        if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
    }
}
