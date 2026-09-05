# Hashmark TestFlight Beta 交接材料

本文档对应 Hashmark `1.0 (1)` 的首轮熟人 TestFlight 测试。审核联系人姓名与国际格式电话从 App Store Connect 的 Account Holder 档案直接填写，不保存到本公开仓库；API Key、测试者邮箱和其他个人信息同样不得提交。

## Test Information

### English (U.S.) — Beta App Description

Hashmark is a native Markdown reader, editor, and optional AI writing assistant for iPhone and iPad. Create and organize Markdown documents, edit with a touch-friendly toolbar, preview GitHub-flavored Markdown, code highlighting, math, and Mermaid diagrams, and export or share your work.

Documents stay on the device by default. Testers can optionally enable iCloud document sync. AI writing is optional and uses the tester's own API key to connect directly to a supported provider. No Hashmark account is required.

This beta is intended for a small invited group to validate document reliability, editing and preview behavior, iCloud opt-in flows, and overall usability before monetization and public App Store availability are introduced.

### 简体中文 — Beta App Description

Hashmark 是一款适用于 iPhone 和 iPad 的原生 Markdown 阅读、编辑与可选 AI 写作 App。你可以创建和整理 Markdown 文稿，使用适合触屏的工具栏编辑，预览 GitHub 风格 Markdown、代码高亮、数学公式和 Mermaid 图表，并导出或分享内容。

文稿默认保存在设备本地，也可以由测试者主动开启 iCloud 文稿同步。AI 写作不是必需功能，使用测试者自己的 API Key 直接连接受支持的服务商。使用 Hashmark 无需注册账号。

本次 Beta 仅面向受邀的小范围测试者，用于验证文稿可靠性、编辑与预览、iCloud 主动开启流程和整体易用性；收费功能及正式公开上架将在后续阶段处理。

### Feedback Email

`hello1024lc@gmail.com`

### English (U.S.) — What to Test

Please focus on the following:

1. Create folders and Markdown documents, then rename, move, edit, delete, and reopen them.
2. Import a Markdown or text file from Files and confirm the destination before importing.
3. Check preview rendering for headings, lists, tables, code blocks, math, Mermaid diagrams, links, and light/dark appearance.
4. Switch between editing and preview, try the formatting toolbar and outline, and confirm changes are saved.
5. Export or share a document as Markdown, plain text, PDF, or a long screenshot.
6. Confirm iCloud sync is off by default. If you choose to test it, keep a separate backup, enable sync, confirm documents appear in Files/iCloud Drive, then disable sync and confirm the local copy remains available. Disabling sync should not delete the cloud copy.
7. Confirm the core document experience works without an account or AI API key.
8. Optional AI test: configure your own supported provider and key. Before the first request, verify that Hashmark identifies the provider and endpoint and asks for data-sharing permission. Denying must prevent the request; allowing must permit it; changing the endpoint must ask again; withdrawing permission in Settings must block future requests.

Please report the device model, OS version, Hashmark build, exact steps, expected result, actual result, and whether the issue is reproducible. Do not include API keys or private document contents in feedback.

### 简体中文 — What to Test

请重点验证以下内容：

1. 创建文件夹和 Markdown 文稿，然后执行重命名、移动、编辑、删除与重新打开。
2. 从“文件”App 导入 Markdown 或文本文件，并确认导入前可以选择目标目录。
3. 检查标题、列表、表格、代码块、数学公式、Mermaid 图表、链接以及深浅色外观的预览效果。
4. 在编辑与预览之间切换，尝试格式工具栏与大纲，并确认修改已保存。
5. 将文稿导出或分享为 Markdown、纯文本、PDF 或长截图。
6. 确认 iCloud 同步默认关闭。如需测试，请先自行保留备份，再开启同步，确认文稿出现在“文件”App 的 iCloud Drive 中；随后关闭同步，确认本地副本仍可用，且云端副本没有被删除。
7. 确认不登录账号、不配置 AI API Key 时，核心文稿功能仍然可用。
8. 可选 AI 测试：配置你自己的受支持服务商和 API Key。首次请求前，确认 Hashmark 会显示服务商和端点并请求数据共享授权；拒绝后不得发送，允许后可以请求；更换端点后必须重新询问；在设置中撤回授权后，后续请求必须再次被阻止。

反馈时请提供设备型号、系统版本、Hashmark 构建号、完整复现步骤、预期结果、实际结果及复现概率。请勿在反馈中包含 API Key 或私人文稿内容。

## TestFlight App Review Information

### Contact

- First name: `Use the verified Account Holder profile; do not commit personal data`
- Last name: `Use the verified Account Holder profile; do not commit personal data`
- Phone, including country code: `Use the verified Account Holder profile in international format; do not commit personal data`
- Email: `hello1024lc@gmail.com`

### Sign-in Information

- Sign-in required: No
- Demo account: Not applicable

### Beta Review Notes

Hashmark does not require an account, subscription, or external hardware. The core Markdown workflow can be reviewed without entering credentials: create a document, edit it, switch to preview, import a local file, and export or share the result.

iCloud document sync is optional and off by default. If enabled, Hashmark uses the public iCloud Documents container `iCloud.com.kvsur.MarkdownApp`. Disabling sync first creates and verifies a local recovery copy and does not delete the cloud copy.

AI writing is an optional BYOK feature. Reviewers do not need to configure it to evaluate the core app. A user who enables AI supplies their own API key and selects OpenAI, Anthropic, Google Gemini, Moonshot Kimi, or Zhipu GLM. Requests travel directly from the device to the selected provider or configured endpoint; Hashmark operates no proxy server. Before the first request to each provider and endpoint, the app discloses the data recipient and requests explicit permission. Permission can be withdrawn in Settings.

The app does not contain advertising, third-party analytics, or a developer-operated account system. Privacy policy: https://kvsur.github.io/hashmark/privacy/

Export compliance: the app uses only operating-system TLS and one-way SHA-256 integrity checks and does not implement proprietary or non-exempt encryption.

## Friends Beta 邀请名单模板

不要在本仓库填写真实邮箱。复制下表到私人表格或本地未跟踪文件中维护。

| Tester | Invitation email | Invited at | Accepted | Installed build | Device / OS | Smoke result | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Tester 01 | private | YYYY-MM-DD | No | — | — | Pending | — |
| Tester 02 | private | YYYY-MM-DD | No | — | — | Pending | — |
| Tester 03 | private | YYYY-MM-DD | No | — | — | Pending | — |

## 提交前检查

- [x] 已确认从 Account Holder 档案直接填写审核联系人姓名和国际格式电话，不写入仓库。
- [ ] 在 App Store Connect 的 Test Information 中添加 English (U.S.) 和简体中文本地化。
- [ ] Feedback Email 使用 `hello1024lc@gmail.com`，并确认可以正常收信。
- [ ] 隐私政策 URL 使用 `https://kvsur.github.io/hashmark/privacy/`。
- [ ] 不填写登录账号，因为 Hashmark 无账号系统。
- [ ] 不向 Apple 或测试者提供 AI API Key。
- [ ] 仅通过邮件邀请熟人，不启用 Public Link。
- [ ] 上传新构建时递增 build number；TestFlight 构建最长可测试 90 天。

## 官方参考

- [TestFlight Overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)
- [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information)
- [App Review information](https://developer.apple.com/help/app-store-connect/reference/app-review-information)
