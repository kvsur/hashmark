# iCloud 发布就绪清单

本文记录 Hashmark iCloud 文稿能力的归档配置、隐私声明与 App Store Connect 交接项。每次修改 Bundle ID、Team、容器、部署目标、文件访问或 AI 附件行为后，都要重新执行本清单。

## 已固化的产品配置

| 项目 | 当前值 |
| --- | --- |
| Bundle ID | `com.kvsur.MarkdownApp` |
| Development Team | `Y3RP5W6ZXV` |
| 最低系统 | iOS / iPadOS 16.0 |
| 设备 | iPhone、iPad |
| iCloud 容器 | `iCloud.com.kvsur.MarkdownApp` |
| iCloud 服务 | `CloudDocuments` |
| 公开文稿容器名称 | Hashmark |
| 文件夹层级 | Any |
| 默认存储模式 | 本地；仅用户确认后启用 iCloud |

`MarkdownApp.entitlements`、`Info.plist` 和 Xcode target 必须保持这组值一致。系统“文件”App 已在签名真机上确认能看到 Hashmark 容器和测试文稿。

## 隐私与备份

- `PrivacyInfo.xcprivacy` 明确声明不跟踪用户，也没有跟踪域名。
- AI 是用户主动发起、使用自有密钥直连 Provider 的功能。发送的提示词、文档/文件内容归类为 Other User Content，用户选择的图片归类为 Photos or Videos；用途仅为 App Functionality，不用于跟踪。由于 Provider 可通过用户自己的账号识别请求，两类数据按 linked 声明。
- AI 数据分享授权按 Provider 与规范化 Endpoint 隔离；首次发送前必须明确授权，接收方变化时重新授权，用户可在对应 AI 配置中撤回。底层 `AIClientFactory` 同时执行未授权拒绝，避免 UI 路径遗漏后直接联网。
- 文件修改时间用于展示最近活动时间和排序，iCloud 与本地之间迁移时必须保留原修改时间；声明 Required Reason `DDA9.1`，且该时间及其派生信息不得发送到设备外。
- `UserDefaults` 仅保存本 App 的主题、语言、存储模式和 AI 目录状态，声明 Required Reason `CA92.1`。
- iCloud Drive 文稿由 Apple 的系统服务同步；Hashmark 自己没有中转服务器。
- 迁移恢复副本保留在 Application Support，并设置 `isExcludedFromBackup`，避免同一文稿再次进入设备备份。排除备份不会删除本机恢复副本。
- 相机和照片写入权限文案已覆盖英文、德文、日文、韩文、俄文、简体中文和繁体中文。
- App 仅使用系统 TLS 和不可逆 SHA-256 完整性校验，`ITSAppUsesNonExemptEncryption` 为 `NO`。

## 归档验收

归档必须使用 Release、generic iOS device 和自动签名。归档完成后至少核对：

1. App 签名 entitlement 同时包含 `CloudDocuments`、`com.apple.developer.icloud-container-identifiers` 和 `com.apple.developer.ubiquity-container-identifiers`。
2. 三处容器值都为 `iCloud.com.kvsur.MarkdownApp`，不存在开发/发布容器漂移。
3. `MinimumOSVersion` 为 `16.0`，`UIDeviceFamily` 同时包含 iPhone 和 iPad。
4. App bundle 包含可解析的 `PrivacyInfo.xcprivacy`。
5. Embedded provisioning profile 的 Application Identifier、Team Identifier 和 iCloud 容器与最终签名一致。
6. Archive validation 没有 entitlement、privacy manifest、usage description 或 required-reason 警告。
7. 关闭 iCloud 同步后抽查不同修改时间的文稿，本地列表仍按原活动时间从新到旧排列。

App Store Connect 导出使用仓库中的 `MarkdownApp/AppStoreExportOptions.plist`。最终 `.ipa` 必须由 Apple Distribution 签名且 `get-task-allow` 为 `false`；开发签名 archive 只能用于工程验证，不能作为发布通过证据。

## App Store Connect 外部交接

以下项目不能只靠仓库完成，提交人需要在 App Store Connect / Certificates, Identifiers & Profiles 最终确认：

- Distribution App ID 已启用 iCloud Documents，生产 provisioning profile 包含同一容器。
- App Privacy 回答与本清单及 `PrivacyInfo.xcprivacy` 一致；若增加 Provider、分析 SDK、崩溃上报或自有服务，必须重新审计。
- 将 `https://kvsur.github.io/hashmark/privacy/` 配置为隐私政策 URL；上传前确认其无需登录且可在移动网络访问。政策需与 `docs/privacy/index.html`、实际数据流及 App 内入口一致。
- 上传归档后通过 App Store Connect 的自动校验，并检查生成的 privacy report。
- 提交 iPhone/iPad 截图、年龄分级、出口合规答案和审核说明；审核说明应注明 iCloud 默认关闭以及 AI 采用 BYOK。

## 发布阻断条件

出现下列任一情况不得发布：容器或签名不一致、隐私清单缺失/无效、公开隐私政策不可访问、App 内无隐私政策入口、AI 可在未授权时发送用户数据、iOS 16 或当前系统运行时失败、迁移故障会改变旧模式或丢失唯一副本、关闭同步会删除云端内容、两台同账户物理设备的最终同步验收未通过。
