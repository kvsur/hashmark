//
//  AIAttachmentBar.swift
//  MarkdownApp
//
//  AI 输入区的附件条：横向展示已加的图片缩略图与文档/PDF chip（可逐项删除），
//  下方三个入口——图片（拍照/相册，压缩、限张、受视觉门控）、引用库内文档、选外部文件（文本/PDF/图片）。
//  只负责「怎么显示与增删附件」，附件如何进请求由 AIAction/各 client 负责（视图轻、逻辑外移）。
//  仅生成类动作（续写/自由创作）使用它——由 AIWritingView 决定是否挂载。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AIAttachmentBar: View {
    @Binding var attachments: [AIAttachment]
    /// 当前接口是否自声明支持图片（视觉）。关闭时图片按钮不开相册、改为引导去配置页。
    let supportsImages: Bool
    /// 图片按钮在未开启「支持图片」时的动作：跳转 AI 配置页（由外层承接呈现）。
    let onNeedsConfig: () -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showReferencePicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var isProcessingPhotos = false
    /// 轻提示（到张数上限 / 加载失败 / 单图过大）。nil 表示无提示。
    @State private var notice: LocalizedStringKey?

    private var imageCount: Int { attachments.lazy.filter { $0.imageJPEG != nil }.count }
    private var remainingImageSlots: Int { max(0, AttachmentLimits.maxImageCount - imageCount) }
    private var referencedURLs: Set<URL> { Set(attachments.compactMap(\.referencedURL)) }
    /// 设备是否有可用相机（模拟器为 false，据此隐藏「拍照」项）。
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Attachments", systemImage: "paperclip")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if isProcessingPhotos {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            chip(for: attachment)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                // 图片入口常态展示。已声明支持图片才可选图；否则点击引导去配置页开启，
                // 而不是直接把图片发给可能不支持视觉的模型（那会得到「访问不了链接」之类的困惑回复）。
                // 开启后弹菜单：拍照（相机，模拟器无则不显）/ 从相册选择。
                if supportsImages {
                    Menu {
                        if cameraAvailable {
                            Button {
                                Haptics.light()
                                showCamera = true
                            } label: {
                                Label("Take Photo", systemImage: "camera")
                            }
                        }
                        Button {
                            Haptics.light()
                            showLibrary = true
                        } label: {
                            Label("Choose from Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        attachmentActionLabel("Photo", systemImage: "photo.on.rectangle")
                    }
                    .disabled(remainingImageSlots == 0)
                } else {
                    Button {
                        Haptics.light()
                        onNeedsConfig()
                    } label: {
                        attachmentActionLabel("Photo", systemImage: "photo.on.rectangle")
                    }
                }

                Button {
                    Haptics.light()
                    showReferencePicker = true
                } label: {
                    attachmentActionLabel("Document", systemImage: "doc.text")
                }

                // 外部文件：文本→注入、图片→图片块、PDF→文档块（图片/PDF 受视觉门控）。
                Button {
                    Haptics.light()
                    showFileImporter = true
                } label: {
                    attachmentActionLabel("File", systemImage: "folder")
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .tint(.primary)

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            Task { await processPhotos(items) }
        }
        .photosPicker(
            isPresented: $showLibrary,
            selection: $photoItems,
            maxSelectionCount: remainingImageSlots,
            matching: .images
        )
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in handleCapturedPhoto(data) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReferencePicker) {
            DocumentReferencePicker(alreadySelected: referencedURLs) { picked in
                // 替换全部文档引用（保留图片）：picker 已把用户保留的项一并回传，无需逐项去重。
                attachments.removeAll { $0.referencedURL != nil }
                attachments.append(contentsOf: picked)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            // 用 .data 兜底放行任意文件：很多代码文件（.go/.rs/.kt 无注册 UTI、.ts 被系统识别成视频）
            // 并不归属 public.text，仅列 .text 会把它们挡在选择器外。改为接受任意文件，
            // 再在 processFiles 里按「能否 UTF-8 读成文本」判定，读不出的二进制会被跳过。
            allowedContentTypes: [.image, .pdf, .text, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await processFiles(urls) }
            case .failure:
                notice = "Couldn't open the file."
            }
        }
    }

    private func attachmentActionLabel(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 附件 chip

    @ViewBuilder
    private func chip(for attachment: AIAttachment) -> some View {
        switch attachment.kind {
        case .image(let data):
            imageChip(data: data, id: attachment.id)
        case .documentReference(_, let name, _):
            documentChip(name: name, id: attachment.id, systemImage: "doc.text")
        case .pdf(_, let name):
            documentChip(name: name, id: attachment.id, systemImage: "doc.richtext")
        }
    }

    private func imageChip(data: Data, id: UUID) -> some View {
        thumbnail(for: data)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) { removeButton(id: id) }
    }

    @ViewBuilder
    private func thumbnail(for data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // 极端情况（数据已损坏）：给个占位图标而非空白。
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.secondarySystemBackground))
        }
    }

    private func documentChip(name: String, id: UUID, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(name)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 160)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { removeButton(id: id) }
    }

    private func removeButton(id: UUID) -> some View {
        Button {
            Haptics.light()
            attachments.removeAll { $0.id == id }
            notice = nil
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.body)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel("Remove attachment")
    }

    // MARK: - 图片处理（相册批量 + 相机单张共用压缩追加）

    private enum ImageAddOutcome { case added, tooLarge, failed }

    /// 压缩并追加一张图片；不检查上限（调用方先判）。相册与相机共用（DRY）。
    @MainActor
    private func encodeAndAppend(_ rawData: Data) -> ImageAddOutcome {
        do {
            let jpeg = try ImageAttachmentEncoder.encodeJPEG(from: rawData)
            attachments.append(.image(jpeg))
            return .added
        } catch ImageAttachmentError.tooLarge {
            return .tooLarge
        } catch {
            return .failed
        }
    }

    @MainActor
    private func processPhotos(_ items: [PhotosPickerItem]) async {
        isProcessingPhotos = true
        defer {
            isProcessingPhotos = false
            photoItems = []
        }
        var loadFailures = 0
        var tooLarge = 0
        for item in items {
            // 逐张兜住上限：即便系统给了超额选择，也不越过硬限。
            guard imageCount < AttachmentLimits.maxImageCount else { break }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    loadFailures += 1
                    continue
                }
                switch encodeAndAppend(data) {
                case .added: break
                case .tooLarge: tooLarge += 1
                case .failed: loadFailures += 1
                }
            } catch {
                loadFailures += 1
            }
        }
        notice = photoNotice(loadFailures: loadFailures, tooLarge: tooLarge)
    }

    /// 相机拍照回调：压缩追加单张，按结果给提示。
    @MainActor
    private func handleCapturedPhoto(_ data: Data) {
        guard imageCount < AttachmentLimits.maxImageCount else {
            notice = "Attachment limit reached."
            return
        }
        switch encodeAndAppend(data) {
        case .added: notice = nil
        case .tooLarge: notice = "Some images are too large to attach."
        case .failed: notice = "Some images couldn't be added."
        }
    }

    private func photoNotice(loadFailures: Int, tooLarge: Int) -> LocalizedStringKey? {
        if tooLarge > 0 { return "Some images are too large to attach." }
        if loadFailures > 0 { return "Some images couldn't be added." }
        return nil
    }

    // MARK: - 外部文件处理（文本 / PDF / 图片）

    /// 按类型路由选中的外部文件：文本→引用注入、图片→图片块、PDF→文档块。
    /// 图片与 PDF 受视觉门控——未开启时跳过并提示去配置；文本不受门控。
    @MainActor
    private func processFiles(_ urls: [URL]) async {
        var gatedOut = 0    // 图片/PDF 但未开启视觉支持，被拦下
        var tooLarge = 0
        var failed = 0
        for url in urls {
            // 外部文件受安全作用域保护，读前须 start/stop。
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            if let type, type.conforms(to: .image) {
                guard supportsImages else { gatedOut += 1; continue }
                guard imageCount < AttachmentLimits.maxImageCount else { continue }
                guard let data = try? Data(contentsOf: url) else { failed += 1; continue }
                switch encodeAndAppend(data) {
                case .added: break
                case .tooLarge: tooLarge += 1
                case .failed: failed += 1
                }
            } else if let type, type.conforms(to: .pdf) {
                guard supportsImages else { gatedOut += 1; continue }
                guard let data = try? Data(contentsOf: url) else { failed += 1; continue }
                guard data.count <= AttachmentLimits.maxPDFBytes else { tooLarge += 1; continue }
                attachments.append(.pdf(data: data, name: url.lastPathComponent))
            } else {
                // 其余一律尝试按文本读取（含 md/txt 与各种代码文件，无论系统是否给了 UTI）。
                // 先按体积挡掉大文件：既防上百 MB 的二进制被整个读进内存，也防超大文本撑爆 prompt。
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= AttachmentLimits.maxTextBytes else { tooLarge += 1; continue }
                // 读不出（二进制解不成 UTF-8）或空则跳过。
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    failed += 1
                    continue
                }
                attachments.append(.documentReference(url: url, name: url.lastPathComponent, text: text))
            }
        }
        notice = fileNotice(gatedOut: gatedOut, tooLarge: tooLarge, failed: failed)
    }

    private func fileNotice(gatedOut: Int, tooLarge: Int, failed: Int) -> LocalizedStringKey? {
        if gatedOut > 0 { return "Turn on image and PDF support in AI settings to attach them." }
        if tooLarge > 0 { return "Some files are too large to attach." }
        if failed > 0 { return "Some files couldn't be added." }
        return nil
    }
}
