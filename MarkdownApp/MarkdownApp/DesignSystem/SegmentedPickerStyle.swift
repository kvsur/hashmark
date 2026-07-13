//
//  SegmentedPickerStyle.swift
//  MarkdownApp
//
//  加高的分段选择器样式：设置页「主题」「AI 响应格式」共用。
//  默认 .segmented 在 Form 里偏扁，这里统一放大控件尺寸并加纵向留白（DRY，收敛一处）。
//

import SwiftUI

extension View {
    /// 更饱满的分段选择器：放大控件尺寸 + 纵向留白，避免默认样式过扁。
    func tallSegmentedPicker() -> some View {
        self
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.vertical, 6)
    }
}
