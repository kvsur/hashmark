//
//  PreviewHandle.swift
//  MarkdownApp
//
//  预览渲染层与分享逻辑之间的桥：持有当前 WKWebView 的弱引用，
//  让工具栏里的「分享 - 长截图」能取到底层 WebView 做整页快照。
//  预览视图轻量（只管渲染），截图这类命令式逻辑外移到这里。
//

import UIKit
import WebKit

final class PreviewHandle {
    /// 由 MarkdownPreviewView 在 WebView 创建时回填；弱引用避免越权持有 WebView 生命周期。
    weak var webView: WKWebView?

    /// 当前触点是否落在预览内「实际可横向滚动」的区域（宽代码块/表格）。
    /// 由页面 touchstart/touchend 经消息通道实时回填；滑动切换手势结束时读它做避让，
    /// 保证内部横滚优先于「预览 ↔ 编辑」切换。瞬时值、不驱动 UI，无需可观察。
    var isTouchingHorizontalScroller = false

    /// 导出宽度上限：整页扩展后的宽度不超过此值，防止极宽表格/代码块把产物撑得过大。
    /// 绝大多数内容自然宽都在此值以内，会被完整平铺；仅超此值的内容才会在边缘截断。
    private static let maxExportWidth = 1920

    /// 导出前注入的「导出模式」样式：把 body 与 #content 扩展到「刚好容纳最宽溢出块」的
    /// 固定宽度，等效于横屏视口变宽但无需真的转屏。
    /// 静态产物（长图/PDF）无法交互横滑，故导出前把原本需要横滑才能看全的内容整体铺开。
    ///
    /// 关键点（均经实测校准）：
    /// 1. 代码块要量内部 code 的 scrollWidth：hljs 把 code 设为 display:block，长代码行溢出
    ///    发生在 code 内部，pre.scrollWidth 与 pre 盒子宽都看不到它（真机验证的漏算根源）。
    /// 2. 表格受 max-width:100% 约束时列宽重排会低估，临时放开后量 max-content；宽度累加还要
    ///    计入各层（content + pre）左右 padding，否则最宽块会溢出 content-box 留白。
    /// 3. 用固定像素 width（非 max-content）撑开：max-content 会把正常段落也拉成不换行的超长单行；
    ///    固定宽度下正文仍正常换行，且布局不依赖视口宽，createPDF 在任何布局视口下结论一致。
    /// 4. body 与 #content 同撑到 target，让正文与最宽块同宽、右侧不留白（旧方案只撑 #content 的症结）。
    /// 5. 只撑 body、绝不给 html 设 width——给 html 设固定宽会破坏 documentElement 的滚动尺寸测量
    ///    （实测 scrollWidth 失真、scrollHeight 塌成视口高），而这两个值正是下方 createPDF 的 rect 依据。
    /// 普通文档（无超宽块）target 保持当前窄栏宽，不受影响。加宽后由根元素铺满背景色兜底，
    /// 保证整页（含深色模式）底色一致。返回重排后的真实内容宽高，供 createPDF 按此整体渲染。
    private static var enterExportModeJS: String {
        """
        (function () {
          var content = document.getElementById('content');
          if (!content) { return { w: 0, h: 0 }; }
          var cs = getComputedStyle(content);
          var bg = cs.backgroundColor || 'transparent';
          var padX = (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0);

          // 量出每个溢出块「完整平铺」需要的宽度（含各层左右内边距）。
          var need = content.clientWidth;
          // 代码块：hljs 把 code 设成 display:block，长代码行溢出发生在 code 内部，
          // pre.scrollWidth 与 pre 盒子宽都看不到它，故量内部 code/.hljs 的 scrollWidth，
          // 再补 pre 自身与 content 的左右内边距。
          content.querySelectorAll('pre').forEach(function (pre) {
            var ps = getComputedStyle(pre);
            var prePad = (parseFloat(ps.paddingLeft) || 0) + (parseFloat(ps.paddingRight) || 0);
            var inner = pre.scrollWidth;
            pre.querySelectorAll('code, .hljs').forEach(function (c) { inner = Math.max(inner, c.scrollWidth); });
            need = Math.max(need, inner + prePad + padX);
          });
          // 表格：受 max-width:100% 约束时列宽会重排而低估真实需求，临时放开后量 max-content。
          var probe = document.createElement('style');
          probe.textContent = '#content table{max-width:none !important;}';
          document.head.appendChild(probe);
          content.querySelectorAll('table').forEach(function (t) {
            need = Math.max(need, t.scrollWidth + padX);
          });
          probe.remove();

          // 目标宽度封顶 maxExportWidth。
          var target = Math.min(Math.ceil(need), \(maxExportWidth));
          var style = document.getElementById('__export_mode');
          if (!style) {
            style = document.createElement('style');
            style.id = '__export_mode';
            document.head.appendChild(style);
          }
          style.textContent =
            'html{background:' + bg + ' !important;}' +
            'body{width:' + target + 'px !important;}' +
            '#content{width:' + target + 'px !important;max-width:none !important;}' +
            '#content pre{overflow:visible !important;}' +
            '#content pre code,#content pre code.hljs{overflow:visible !important;}' +
            '#content table{overflow:visible !important;max-width:none !important;}';
          window.__exitExportMode = function () {
            var s = document.getElementById('__export_mode');
            if (s) { s.remove(); }
          };
          return {
            w: Math.ceil(document.documentElement.scrollWidth),
            h: Math.ceil(document.documentElement.scrollHeight)
          };
        })();
        """
    }

    /// 把整篇渲染内容拍平成一份 PDF：进入导出模式 → 按真实内容宽高整体渲染 → 退出导出模式。
    /// createPDF 走打印/矢量路径（非 GPU 快照），可无视 GPU 纹理尺寸上限承载超长/超宽内容，
    /// 故长截图与 PDF 都以它为唯一来源（DRY），彻底避开原「逐屏快照」的空白与横向裁切问题。
    /// 注：显式 rect 会生成单页 PDF；极长文档单页可能超出部分阅读器的页高上限，属可接受的边缘取舍。
    @MainActor
    private func renderFlattenedPDF(completion: @escaping (Data?) -> Void) {
        guard let webView else { completion(nil); return }
        webView.evaluateJavaScript(Self.enterExportModeJS) { result, _ in
            let config = WKPDFConfiguration()
            if let size = result as? [String: Any],
               let width = size["w"] as? Double, let height = size["h"] as? Double,
               width > 0, height > 0 {
                let clampedWidth = min(CGFloat(width), CGFloat(Self.maxExportWidth))
                config.rect = CGRect(x: 0, y: 0, width: clampedWidth, height: CGFloat(height))
            }
            webView.createPDF(configuration: config) { pdfResult in
                // 无论成败都退出导出模式，别把加宽样式留在屏上。
                webView.evaluateJavaScript("window.__exitExportMode && window.__exitExportMode()")
                completion(try? pdfResult.get())
            }
        }
    }

    /// 把整篇渲染内容导出为 PDF 数据（完整平铺，含横向溢出内容）。
    @MainActor
    func exportPDF(completion: @escaping (Data?) -> Void) {
        renderFlattenedPDF(completion: completion)
    }

    /// 取「纯文本」：渲染后 DOM 的可见文字（marked.js 已解析，去掉了 #、* 等语法标记）。
    /// 直接读渲染容器的 innerText，比在 Swift 侧重造 Markdown 去标记更准确。
    @MainActor
    func extractPlainText(completion: @escaping (String?) -> Void) {
        guard let webView else { completion(nil); return }
        webView.evaluateJavaScript("document.getElementById('content').innerText") { result, _ in
            completion(result as? String)
        }
    }

    /// 把整篇渲染内容截成一张长图（含超出屏幕、需纵向滚动或横向滚动才可见的部分）。
    /// 复用「拍平 PDF」拿到完整平铺的矢量内容，再把首页栅格化成位图——一套逻辑贯穿长图与 PDF。
    /// 相比逐屏快照：不受 GPU 纹理上限约束（CoreGraphics 路径）、无需在屏上滚一遍、且能完整含横向内容。
    @MainActor
    func captureLongScreenshot(completion: @escaping (UIImage?) -> Void) {
        let displayScale = webView?.traitCollection.displayScale ?? 0
        let scale = displayScale > 0 ? displayScale : UIScreen.main.scale
        renderFlattenedPDF { data in
            guard let data else { completion(nil); return }
            completion(Self.rasterize(pdf: data, scale: scale))
        }
    }

    /// 把（拍平后单页的）PDF 栅格化成 UIImage。CoreGraphics 路径，不受 GPU 纹理尺寸上限约束。
    /// 导出模式已给根元素铺满整页背景，PDF 自带底色，故 opaque=false 直接绘制即可。
    private static func rasterize(pdf data: Data, scale: CGFloat) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // PDF 坐标系原点在左下，翻转到 UIKit 的左上原点后再绘制。
            cg.translateBy(x: -bounds.origin.x, y: bounds.size.height + bounds.origin.y)
            cg.scaleBy(x: 1, y: -1)
            cg.drawPDFPage(page)
        }
    }
}
