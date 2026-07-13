//
//  DocumentNode.swift
//  MarkdownApp
//
//  文件树中的一个节点：文件夹或 Markdown 文件。
//  节点直接映射磁盘上的真实条目，`url` 即其在文件系统中的位置。
//

import Foundation

struct DocumentNode: Identifiable, Hashable {
    enum Kind {
        case folder
        case markdown
    }

    let url: URL
    let kind: Kind
    let modifiedAt: Date
    /// 文件大小（字节）；文件夹为 nil。加载时由 FileStore 读入。
    let fileSize: Int64?
    /// 目录直接子项数（本 App 可见项：文件夹 + .md）；文件为 nil。加载时由 FileStore 浅层计数。
    let childCount: Int?

    /// 带默认值，兼容仅用于导航跳转、无需元信息的创建点。
    init(url: URL, kind: Kind, modifiedAt: Date, fileSize: Int64? = nil, childCount: Int? = nil) {
        self.url = url
        self.kind = kind
        self.modifiedAt = modifiedAt
        self.fileSize = fileSize
        self.childCount = childCount
    }

    /// 用 URL 作为稳定唯一标识。
    var id: URL { url }

    /// 磁盘上的完整名称（文件夹名，或含 .md 的文件名）。
    var name: String { url.lastPathComponent }

    var isFolder: Bool { kind == .folder }

    /// 列表展示用标题：Markdown 去掉扩展名，文件夹用原名。
    var displayName: String {
        isFolder ? name : url.deletingPathExtension().lastPathComponent
    }

    /// 列表图标。
    var systemImage: String {
        isFolder ? "folder.fill" : "doc.text"
    }

    /// 列表副标题：修改时间 + （文件夹）子项数 /（文件）大小。对齐系统「文件」App。
    var metadataText: String {
        let date = DocumentNode.relativeDateText(modifiedAt)
        if isFolder {
            return "\(date) · \(childCount ?? 0) 项"
        }
        guard let fileSize else { return date }
        return "\(date) · \(DocumentNode.byteFormatter.string(fromByteCount: fileSize))"
    }

    // MARK: - 格式化（静态复用，避免每行重建 Formatter）

    /// 相对日期：今天显示时间，昨天/前天用中文，更早显示 yyyy/M/d（近似系统「文件」App）。
    private static func relativeDateText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天" }
        let dayBeforeYesterday = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: Date()))
        if let dby = dayBeforeYesterday, cal.isDate(date, inSameDayAs: dby) { return "前天" }
        return dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
}
