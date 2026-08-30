//
//  ContentView.swift
//  MarkdownApp
//
//  App 主壳：一个 NavigationStack，根为根目录的文件浏览器。
//  文件夹通过 navigationDestination 逐级下钻，支持无限级目录（S2）；
//  Markdown 文件下钻到文档屏（S3 预览 / S4 编辑，同屏切换）。
//  外部分享/「打开方式」传入的文件经 onOpenURL → 选目录中间页 → 导入并跳到预览（S6）。
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var documentLibrary: DocumentLibraryController
    @Environment(\.scenePhase) private var scenePhase

    /// 显式导航路径，用于导入完成后以代码方式跳到新文件的预览。
    @State private var path: [DocumentNode] = []
    /// 外部传入、正在「只读预览」的文件（onOpenURL 传入）；非 nil 时弹出只读预览。
    /// 用户在预览里自行决定是否导入，未导入则原样放弃。复用应用内导入的同一套件。
    @State private var incoming: ImportedDocument?
    /// 递增以通知首页浏览器重载（外部导入完成后）。
    @State private var homeReloadToken = 0

    var body: some View {
        NavigationStack(path: $path) {
            FileBrowserView(directory: documentLibrary.activeRootURL, isRoot: true, reloadToken: homeReloadToken) { newDoc in
                // 首页 AI 生成新文档后，直接推入栈进入编辑/预览。
                path.append(newDoc)
            }
            .navigationDestination(for: DocumentNode.self) { node in
                    // 同一目的地按类型分流：文件夹继续下钻，文档进入文档屏（预览/编辑）。
                    if node.isFolder {
                        FileBrowserView(directory: node.url)
                    } else {
                        DocumentView(node: node)
                    }
                }
        }
        .rebuildsOnLanguageChange()
        // 其它 App 分享/「打开方式」传入文件时触发：先只读预览，不直接落盘。
        // 读入文本后进预览；读不出（非文本/无权限）则忽略。与应用内「打开文件预览」同一路径。
        .onOpenURL { url in
            Task {
                guard let text = try? await documentLibrary.readExternalText(at: url) else { return }
                incoming = ImportedDocument(
                    url: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    markdown: text
                )
            }
        }
        .sheet(item: $incoming) { doc in
            ReadOnlyPreviewView(
                sourceURL: doc.url,
                title: doc.title,
                markdown: doc.markdown,
                onImported: { homeReloadToken += 1 }
            )
        }
        // 预览关闭后（无论导入或放弃）清理系统 Inbox 残留。
        .onChange(of: incoming?.id) { newID in
            if newID == nil {
                Task { try? await documentLibrary.purgeInbox() }
            }
        }
        .onChange(of: documentLibrary.identity) { _ in
            path.removeAll()
            homeReloadToken &+= 1
        }
        .task {
            await documentLibrary.start()
#if DEBUG
            await ICloudDeviceSmokeRunner.runIfRequested(using: documentLibrary)
#endif
        }
        .onChange(of: scenePhase) { phase in
            documentLibrary.setFilePresentationActive(phase == .active)
        }
        // 主题：进入即应用当前偏好、之后随设置变化实时更新（窗口级，覆盖所有 sheet）。
        .onAppear {
            InterfaceStyleController.apply(settings.theme)
        }
        .onChange(of: settings.theme) { newTheme in
            InterfaceStyleController.apply(newTheme)
        }
        // 语言无需在此处理：取词由 LocalizationController 的取词拦截统一负责，
        // 语言包在 SettingsStore 写入偏好时即同步就位（onChange 太晚，会慢一帧），
        // Locale 的环境注入则在 App 根部完成（见 MarkdownAppApp）。
    }
}

#Preview {
    ContentView()
        .environmentObject(SettingsStore())
}
