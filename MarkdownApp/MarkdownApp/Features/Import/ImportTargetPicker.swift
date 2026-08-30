//
//  ImportTargetPicker.swift
//  MarkdownApp
//
//  外部文件导入的「中间页」：为传入文件挑一个目标目录并触发导入。
//  选目录/新建文件夹的通用逻辑已抽到 DirectoryPicker，这里只描述「确认时导入」。
//

import SwiftUI

struct ImportTargetPicker: View {
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    /// 待导入的外部文件 URL。
    let sourceURL: URL
    /// 导入成功后回调新文件 URL。
    let onImported: (URL) -> Void

    var body: some View {
        DirectoryPicker(
            rootURL: documentLibrary.activeRootURL,
            title: "Choose Folder",
            prompt: "Import “\(sourceURL.lastPathComponent)” to",
            confirmLabel: "Import Here"
        ) { targetDir in
            let newURL = try await documentLibrary.importFile(from: sourceURL, to: targetDir)
            onImported(newURL)
        }
    }
}

/// 包装传入文件 URL，供 sheet(item:) 驱动导入中间页。
struct PendingImport: Identifiable {
    let id = UUID()
    let url: URL
}
