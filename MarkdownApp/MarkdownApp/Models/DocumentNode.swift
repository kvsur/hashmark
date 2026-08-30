//
//  DocumentNode.swift
//  MarkdownApp
//
//  文件树中的一个节点：文件夹或 Markdown 文件。
//  节点直接映射磁盘上的真实条目，`url` 即其在文件系统中的位置。
//

import Foundation

nonisolated struct DocumentNode: Identifiable, Hashable, Sendable {
    enum Kind: Sendable {
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
    @MainActor var metadataText: String {
        let date = DocumentNode.relativeDateText(modifiedAt)
        if isFolder {
            // 子项数走复数变体（catalog 里按语言配 one/other，俄语还有 few/many），不手拼量词。
            return "\(date) · \(LocalizationController.string("\(childCount ?? 0) items"))"
        }
        guard let fileSize else { return date }
        return "\(date) · \(fileSize.formatted(.byteCount(style: .file).locale(LocalizationController.current)))"
    }

    // MARK: - 格式化

    /// 相对日期：今天显示时间，昨天/前天用文字，更早显示短日期（近似系统「文件」App）。
    ///
    /// 日期/时间格式一律交给 FormatStyle 按 locale 决定，不写死 "yyyy/M/d" / "HH:mm"——
    /// 各地区的日期顺序与 12/24 小时制并不相同（德语 d.M.yyyy、英语区习惯 12 小时制）。
    /// 也不再用 static let 缓存 Formatter：那样切换语言后会永久停留在启动时的语言。
    @MainActor private static func relativeDateText(_ date: Date) -> String {
        let locale = LocalizationController.current
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute().locale(locale))
        }
        if cal.isDateInYesterday(date) { return LocalizationController.string("Yesterday") }
        let dayBeforeYesterday = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: Date()))
        if let dby = dayBeforeYesterday, cal.isDate(date, inSameDayAs: dby) {
            return LocalizationController.string("Day before yesterday")
        }
        return date.formatted(.dateTime.year().month().day().locale(locale))
    }
}
