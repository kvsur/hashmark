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

    /// 取「纯文本」：渲染后 DOM 的可见文字（marked.js 已解析，去掉了 #、* 等语法标记）。
    /// 直接读渲染容器的 innerText，比在 Swift 侧重造 Markdown 去标记更准确。
    @MainActor
    func extractPlainText(completion: @escaping (String?) -> Void) {
        guard let webView else { completion(nil); return }
        webView.evaluateJavaScript("document.getElementById('content').innerText") { result, _ in
            completion(result as? String)
        }
    }

    /// 把整篇渲染内容截成一张长图（含超出屏幕、需滚动才可见的部分）。
    ///
    /// 关键：不能对超长内容做「一次性整页快照」——渲染目标一旦超过 GPU 纹理尺寸上限
    /// 就会返回空白图。改为「逐屏滚动、每屏一张、最后拼接」：每次快照只有一个视口高，
    /// 稳定可靠；代价是截图期间屏上预览会快速滚动一遍，并有一定耗时。
    @MainActor
    func captureLongScreenshot(completion: @escaping (UIImage?) -> Void) {
        guard let webView else { completion(nil); return }
        let width = webView.scrollView.contentSize.width
        let totalHeight = webView.scrollView.contentSize.height
        let viewportHeight = webView.bounds.height
        guard width > 0, totalHeight > 0, viewportHeight > 0 else { completion(nil); return }

        let originalOffset = webView.scrollView.contentOffset
        let maxOffset = max(totalHeight - viewportHeight, 0)

        // 合成用的画布：按屏幕缩放比，尺寸为整页内容大小。
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = webView.traitCollection.displayScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: totalHeight),
            format: format
        )

        // 逐片截好先收集，最后在 renderer 闭包里一次性绘制（闭包内不能做异步等待）。
        var tiles: [(image: UIImage, y: CGFloat)] = []

        func captureTile(at y: CGFloat) {
            guard y < totalHeight else {
                let composite = renderer.image { _ in
                    for tile in tiles { tile.image.draw(at: CGPoint(x: 0, y: tile.y)) }
                }
                webView.scrollView.setContentOffset(originalOffset, animated: false)
                completion(composite)
                return
            }
            // 滚动到目标行；接近底部时会被系统夹到 maxOffset，故用 rectY 修正截取起点。
            let targetOffset = min(y, maxOffset)
            webView.scrollView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)

            // 给 WebKit 一点时间把刚进入视口的内容画出来，否则远处分片可能空白。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                let rectY = y - targetOffset
                let sliceHeight = min(viewportHeight - rectY, totalHeight - y)
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(x: 0, y: rectY, width: width, height: sliceHeight)
                config.afterScreenUpdates = true
                webView.takeSnapshot(with: config) { image, _ in
                    if let image { tiles.append((image, y)) }
                    captureTile(at: y + viewportHeight)
                }
            }
        }
        captureTile(at: 0)
    }
}
