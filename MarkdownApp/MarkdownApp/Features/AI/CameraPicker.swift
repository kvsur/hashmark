//
//  CameraPicker.swift
//  MarkdownApp
//
//  相机拍照选择器：SwiftUI 的 PhotosPicker 只能取相册，拍照需包一层 UIImagePickerController。
//  产出拍到的原始图片 Data，交由上层用 ImageAttachmentEncoder 压缩降采样（与相册选图同一处理）。
//  需要 Info.plist 的 NSCameraUsageDescription，否则调起相机会崩。
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// 拍照完成回调，交出图片 Data（未压缩，由上层统一压缩）。
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // 取原图；转成 JPEG Data 交回（上层还会再压一道，这里给全质量即可）。
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 1.0) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
