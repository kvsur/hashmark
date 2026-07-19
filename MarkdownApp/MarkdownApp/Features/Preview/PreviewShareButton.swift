//
//  PreviewShareButton.swift
//  MarkdownApp
//
//  「分享」按钮：按传入的动作集合展示选项，调用方按场景决定给哪些。
//  预览态：长截图 / 纯文本 / PDF（都依赖已渲染的 WebView）；
//  编辑态：源文件(.md) / 源内容(Markdown)（只依赖文本与磁盘文件）。
//  DocumentView 两态与 ReadOnlyPreviewView 共用同一按钮（DRY）。
//

import SwiftUI
import UIKit

struct PreviewShareButton: View {
    /// 当前文档的 Markdown 源文本，用于「源内容」分享。
    let markdown: String
    /// 源文件 URL；「源文件」选项与 PDF 文件名依赖它，为 nil 时不显示「源文件」。
    var sourceURL: URL? = nil
    /// 取底层 WebView 做长截图/纯文本/PDF 的桥。
    let handle: PreviewHandle
    /// 要展示的分享动作（按此顺序渲染）。
    let actions: [ShareAction]

    /// 分享动作种类。无关联值，天然可 Hashable，供 ForEach 用。
    enum ShareAction {
        case longScreenshot
        case plainText
        case pdf
        case sourceFile
        case sourceContent
    }

    @State private var showDialog = false
    @State private var shareItems: ShareItems?
    /// 长截图/PDF 生成可能耗时，期间以转圈替代图标并禁用按钮。
    @State private var isBusy = false

    /// 竖屏下点长截图/PDF 时，先提醒「内容可能被遮挡、可横屏重试」；确认后再生成。
    /// 长图/PDF 是「所见即所得」——宽代码块/表格若在竖屏需横滑才看全，产物里同样会截断。
    @State private var showLandscapeHint = false
    /// 记住用户在弹窗前选的是长截图还是 PDF，确认后据此继续。
    @State private var pendingCapture: CaptureKind?

    /// 需要「先量宽高再整页渲染」的两种产物；纯文本/源文件不涉及遮挡，无需此提醒。
    private enum CaptureKind {
        case longScreenshot
        case pdf
    }

    /// 当前是否横屏：横屏视口更宽，宽内容更可能完整落入产物，故此时跳过提醒直接生成。
    /// iPad 两个方向的 sizeClass 都是 regular，无法据此判断，故读窗口的界面朝向。
    private var isLandscape: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation.isLandscape ?? false
    }

    var body: some View {
        Button {
            showDialog = true
        } label: {
            if isBusy {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isBusy)
        .confirmationDialog("Share", isPresented: $showDialog, titleVisibility: .visible) {
            ForEach(actions, id: \.self) { action in
                button(for: action)
            }
        }
        .sheet(item: $shareItems) { payload in
            ShareSheet(items: payload.items)
        }
        .alert("Content May Be Cut Off", isPresented: $showLandscapeHint) {
            Button("Continue") {
                if let kind = pendingCapture { performCapture(kind) }
                pendingCapture = nil
            }
        } message: {
            Text("If part of the shared content is cut off, try switching to landscape orientation and sharing again.")
        }
    }

    @ViewBuilder
    private func button(for action: ShareAction) -> some View {
        switch action {
        case .longScreenshot:
            Button("Long Screenshot") { requestCapture(.longScreenshot) }
        case .plainText:
            Button("Plain Text") { sharePlainText() }
        case .pdf:
            Button("PDF") { requestCapture(.pdf) }
        case .sourceFile:
            if let sourceURL {
                Button("Source File (.md)") { Haptics.success(); shareItems = ShareItems(items: [sourceURL]) }
            }
        case .sourceContent:
            Button("Source Content (Markdown)") { Haptics.success(); shareItems = ShareItems(items: [markdown]) }
        }
    }

    /// 长截图/PDF 入口：竖屏先弹提醒（内容可能被遮挡、可横屏重试），横屏则直接生成。
    private func requestCapture(_ kind: CaptureKind) {
        if isLandscape {
            performCapture(kind)
        } else {
            pendingCapture = kind
            showLandscapeHint = true
        }
    }

    private func performCapture(_ kind: CaptureKind) {
        switch kind {
        case .longScreenshot: shareLongScreenshot()
        case .pdf: sharePDF()
        }
    }

    private func shareLongScreenshot() {
        isBusy = true
        handle.captureLongScreenshot { image in
            isBusy = false
            guard let image else { return }
            Haptics.success()   // 长截图已就绪，给一下「内容取到」反馈
            shareItems = ShareItems(items: [image])
        }
    }

    /// 纯文本：分享去掉 Markdown 语法标记后的渲染可见文字；取不到时退回源内容。
    private func sharePlainText() {
        handle.extractPlainText { text in
            Haptics.success()   // 纯文本已就绪，给一下「内容取到」反馈
            shareItems = ShareItems(items: [text ?? markdown])
        }
    }

    /// PDF：把整篇渲染内容导出为 PDF，写入临时文件后分享（文件名取源文件名）。
    private func sharePDF() {
        isBusy = true
        handle.exportPDF { data in
            isBusy = false
            guard let data else { return }
            // 无源文件时的兜底 PDF 文件名：用户会看到它，故按当前界面语言取词。
            let base = sourceURL?.deletingPathExtension().lastPathComponent ?? LocalizationController.string("Document")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(base).appendingPathExtension("pdf")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return }
            Haptics.success()   // PDF 已导出，给一下「内容取到」反馈
            shareItems = ShareItems(items: [url])
        }
    }
}
