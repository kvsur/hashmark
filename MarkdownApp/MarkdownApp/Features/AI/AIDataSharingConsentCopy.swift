//
//  AIDataSharingConsentCopy.swift
//  MarkdownApp
//
//  写作页与设置页共用同一份授权披露，避免接收方或数据类型描述不一致。
//

import Foundation

enum AIDataSharingConsentCopy {
    static func message(for config: AIConfig) -> String {
        let recipient = AIDataSharingRecipient(config: config)
        let disclosure = LocalizationController.string(
            "Hashmark sends your API key, prompts, document context, selected attachments, and search queries directly to the AI provider and endpoint shown below. The provider processes this data under its own terms and privacy policy."
        )
        let control = LocalizationController.string(
            "No data is sent until you allow it. You can withdraw permission later in AI Settings."
        )
        return "\(disclosure)\n\n\(recipient.provider.displayName)\n\(recipient.displayEndpoint)\n\n\(control)"
    }
}
