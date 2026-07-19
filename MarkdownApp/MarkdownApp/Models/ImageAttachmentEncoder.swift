//
//  ImageAttachmentEncoder.swift
//  MarkdownApp
//
//  把相册选来的原始图片数据，降采样并压成「可直接发给模型」的 JPEG。
//  两家 API 对图片都有尺寸/体积上限，模型侧也只需要够用的分辨率，故上传前统一在本地压缩：
//  - 降采样用 ImageIO 的缩略图接口（不把整图解码进内存，省内存、避免大图 OOM）；
//  - 统一转 JPEG（HEIC/PNG 原图体积大、部分端点不认），media_type 固定 image/jpeg；
//  - 递减质量直至满足单张体积上限。
//  纯 ImageIO/CoreGraphics 实现（不依赖 UIKit）：职责单一、与 UI 解耦，也便于独立验证。
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// 附件相关的集中常量（限张、压缩参数）。散落各处易漂移，收敛到一处（DRY）。
enum AttachmentLimits {
    /// 单次请求最多携带的图片张数（前端硬限，避免请求体过大）。
    static let maxImageCount = 4
    /// 压缩后图片的长边上限（像素）。provider 建议控制在此量级内。
    static let maxImageLongEdge = 1568
    /// JPEG 起始压缩质量；体积超限时从此值递减。
    static let jpegQuality: CGFloat = 0.8
    /// 递减压缩质量的下限：到此仍超限则判定单张过大，不再降质。
    static let minJPEGQuality: CGFloat = 0.4
    /// 单张压缩后 JPEG 体积上限（字节）。base64 会再膨胀约 1/3，故留足余量。
    static let maxEncodedBytes = 4 * 1024 * 1024
    /// 单个 PDF 附件体积上限（字节）。PDF 原样 base64 发送（不压缩），膨胀约 1/3，
    /// 上游多有请求体大小限制，故设一个保守上限，超限拒收并提示。
    static let maxPDFBytes = 8 * 1024 * 1024
    /// 单个文本文件读取上限（字节）。文本会整篇注入 prompt，过大既撑爆上下文也拖慢请求；
    /// 且文件入口放宽到「接受任意文件、以 UTF-8 读取判定是否文本」，需先按体积挡掉大二进制文件，
    /// 避免把上百 MB 的文件整个读进内存再解码失败。
    static let maxTextBytes = 1 * 1024 * 1024
}

/// 图片附件编码期的失败原因（面向用户提示，需本地化）。
enum ImageAttachmentError: LocalizedError {
    case notAnImage            // 数据不是可识别的图片
    case decodingFailed        // 解码/缩放失败
    case tooLarge              // 压到最低质量仍超过体积上限

    var errorDescription: String? {
        switch self {
        case .notAnImage:
            LocalizationController.string("This file isn't a supported image.")
        case .decodingFailed:
            LocalizationController.string("Couldn't read this image.")
        case .tooLarge:
            LocalizationController.string("This image is too large to attach.")
        }
    }
}

enum ImageAttachmentEncoder {
    /// 把原始图片数据降采样并压成 JPEG，返回可直接入 `AIAttachment.image` 的数据。
    /// 失败以 `ImageAttachmentError` 抛出（调用方据此跳过该项并提示）。
    static func encodeJPEG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageAttachmentError.notAnImage
        }
        // 类型校验：确认源确为图片，挡掉误传的非图片数据。
        guard let uti = CGImageSourceGetType(source),
              UTType(uti as String)?.conforms(to: .image) == true else {
            throw ImageAttachmentError.notAnImage
        }

        // 缩略图接口降采样：FromImageAlways 强制以全图为源生成（否则可能取到嵌入的小缩略图），
        // WithTransform 应用 EXIF 方向（否则竖拍照片会横过来），MaxPixelSize 把长边压到上限。
        // 原图长边若已小于上限则不放大（缩略图不上采样），保持原尺寸。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: AttachmentLimits.maxImageLongEdge
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageAttachmentError.decodingFailed
        }

        // 递减质量直至满足体积上限；到最低质量仍超限则判定过大。
        var quality = AttachmentLimits.jpegQuality
        while true {
            guard let jpeg = jpegData(from: cgImage, quality: quality) else {
                throw ImageAttachmentError.decodingFailed
            }
            if jpeg.count <= AttachmentLimits.maxEncodedBytes {
                return jpeg
            }
            if quality <= AttachmentLimits.minJPEGQuality {
                throw ImageAttachmentError.tooLarge
            }
            quality -= 0.15
        }
    }

    /// 用 ImageIO 把 CGImage 编码成 JPEG Data（有损质量可控）。
    private static func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
