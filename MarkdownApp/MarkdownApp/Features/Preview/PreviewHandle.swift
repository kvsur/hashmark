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

    /// 量出当前渲染内容的真实宽高（不做任何重排/加宽，所见即所得）。
    /// 供 createPDF 按此整体渲染——宽代码块/表格若在屏上需要横滑才能看全，
    /// 导出的静态产物里同样会按当前列宽截断，与用户在预览里看到的一致。
    private static let measureContentSizeJS = """
        (function () {
          return {
            w: Math.ceil(document.documentElement.scrollWidth),
            h: Math.ceil(document.documentElement.scrollHeight)
          };
        })();
        """

    /// 把整篇渲染内容拍平成一份 PDF：按当前真实内容宽高整体渲染，不做任何重排。
    /// createPDF 走打印/矢量路径（非 GPU 快照），可无视 GPU 纹理尺寸上限承载超长内容，
    /// 故长截图与 PDF 都以它为唯一来源（DRY），彻底避开原「逐屏快照」的空白问题。
    /// 注：显式 rect 会生成单页 PDF；极长文档单页可能超出部分阅读器的页高上限，属可接受的边缘取舍。
    @MainActor
    private func renderFlattenedPDF(completion: @escaping (Data?) -> Void) {
        guard let webView else { completion(nil); return }
        webView.evaluateJavaScript(Self.measureContentSizeJS) { result, _ in
            let config = WKPDFConfiguration()
            if let size = result as? [String: Any],
               let width = size["w"] as? Double, let height = size["h"] as? Double,
               width > 0, height > 0 {
                config.rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            }
            webView.createPDF(configuration: config) { pdfResult in
                completion(try? pdfResult.get())
            }
        }
    }

    /// 把整篇渲染内容导出为 PDF 数据（所见即所得，横向溢出内容按当前列宽截断）。
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

    /// 把整篇渲染内容截成一张长图（含超出屏幕、需纵向滚动才可见的部分）。
    /// 复用「拍平 PDF」拿到整页矢量内容，再把首页栅格化成位图——一套逻辑贯穿长图与 PDF。
    /// 相比逐屏快照：不受 GPU 纹理上限约束（CoreGraphics 路径）、无需在屏上滚一遍。
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
    /// 页面根元素自带背景色，PDF 已含底色，故 opaque=false 直接绘制即可。
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
