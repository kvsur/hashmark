# Hashmark 发布与升级手册

本文用于在没有自动化助手的情况下，独立完成 Hashmark 的构建、TestFlight 分发和后续版本迭代。每完成一次发布，都应按本手册留下结果记录。

## 安全边界

不要把以下内容提交到仓库：Apple 账户电话和地址、证书私钥、登录密码、验证码、API Key、测试者真实邮箱。审核联系人资料从 App Store Connect 的 Account Holder 档案直接填写。

## 固定发布身份

| 项目 | 固定值 |
| --- | --- |
| App Store 名称 | `Hashmark: AI Markdown Editor` |
| 设备内名称 | `Hashmark` |
| Apple ID | `6806923011` |
| Bundle ID | `com.kvsur.MarkdownApp` |
| Team ID | `Y3RP5W6ZXV` |
| iCloud 容器 | `iCloud.com.kvsur.MarkdownApp` |
| SKU | `hashmark-ios` |
| 主要语言 | English (U.S.) |
| 隐私政策 | `https://kvsur.github.io/hashmark/privacy/` |
| 最低系统 | iOS / iPadOS 16.0 |
| 设备族 | iPhone、iPad |

发布过程中不要临时更换 Bundle ID、Team 或 iCloud 容器。

## 已完成的一次性设置

1. Apple Developer Program 会员、Account Holder 和后台访问已核对。
2. App Store Connect 已创建 iOS App，初始版本为 1.0。
3. 主 App ID 为 explicit，已启用 iCloud，唯一容器为 `iCloud.com.kvsur.MarkdownApp`。
4. App Privacy 已填写公开隐私政策 URL。
5. 免费 App 协议有效。付费 App 协议和欧盟 DSA 交易商资料留到收费或正式公开分发前处理。

## 每次上传新构建

1. 确认 Git 工作区只包含本次有意义的更改，并完成测试与 Release 构建。
2. 保持公开版本号不变，只递增 build number。例如同为 1.0 时，依次使用 1、2、3。
3. 在 Xcode 选择 Hashmark scheme、Release 和 Any iOS Device，执行 Product → Archive。
4. 在 Organizer 检查版本、构建号、App Icon、PrivacyInfo、dSYM、Team 和 iCloud entitlement。
5. 先执行 Validate App，逐项处理 error；warning 必须记录结论，不能直接忽略。
6. 选择 Distribute App → App Store Connect → Upload，并使用 automatic signing。
7. 在 App Store Connect → Hashmark → TestFlight 等待构建完成处理，回答出口合规问题并检查隐私报告。
8. 上传后记录上传时间、构建号、处理结果和 90 天到期日。

命令行上传的成功终点会依次显示 `Uploaded package is processing`、`Upload succeeded` 和 `EXPORT SUCCEEDED`。看到这些信息后仍需回到 TestFlight 等待 processing 完成；不要把 100% 传输进度误认为构建已经可测试。

首次上传后，App Store Connect 的 App 列表可能暂时显示灰色网格占位图，同时 TestFlight 显示“无构建版本”。这是 Apple 尚未完成构建处理和图标提取时的正常过渡状态。先确认上传日志已经出现上述三个成功信号，再等待 TestFlight 出现对应版本；只有构建已经可测试而图标仍未出现时，才回头检查 App Icon 资源和归档内容。本项目 1.0（1）已确认 `AppIcon-1024.png` 为 1024×1024、RGB、无 Alpha，归档中包含 iPhone/iPad 图标和 `Assets.car`。

成功导出时应核对：证书类型为 Cloud Managed Apple Distribution 或 Apple Distribution，profile 名称包含 `iOS Team Store Provisioning Profile: com.kvsur.MarkdownApp`，`get-task-allow=false`，iCloud 环境为 Production，容器为固定值。Cloud Managed 证书不一定出现在普通钥匙串 identity 列表中，不能仅凭钥匙串列表误判为缺少分发证书。

Automatic Signing 生成的 `.xcarchive` 本身可能仍显示 Apple Development 和 `get-task-allow=true`，这是正常中间状态；最终导出/上传产物必须变为 Apple Distribution 和 `get-task-allow=false`。本项目的 archive 还应同时包含 `PrivacyInfo.xcprivacy`、iPhone/iPad App Icon、`Assets.car` 和 `MarkdownApp.app.dSYM`。

### Xcode 报 “No Accounts / No profiles”

1. 打开 Xcode → Settings → Accounts。
2. 添加并登录当前 Account Holder 的 Apple 账户，完成双重认证。
3. 选中 Team `Y3RP5W6ZXV`；必要时点 Manage Certificates，确认 Xcode 可以管理 Apple Distribution，但不要删除现有证书。
4. 重新执行 Archive / Validate / Upload。Automatic Signing 会获取 App Store provisioning profile。
5. 若仍失败，先检查 Bundle ID 是否为 `com.kvsur.MarkdownApp`、App ID 是否启用 iCloud，以及 iCloud 容器是否仍为固定值；不要通过更换 Bundle ID 绕过问题。

本项目在 2026-08-31 登录 Xcode 后重试成功；生成了 Cloud Managed Apple Distribution 签名和有效至 2027-08-31 的 App Store profile。

## 每次发布新版本

1. 根据产品语义递增公开版本号，例如 1.0 → 1.1；build number 重新从合适的递增值开始，但不得与已上传记录重复。
2. 更新 App Store Connect 中对应版本的 What to Test、审核说明和已知问题。
3. 数据流、AI Provider、权限或第三方 SDK 有变化时，重新审计隐私政策、App Privacy 和 `PrivacyInfo.xcprivacy`。
4. Bundle ID、iCloud entitlement、容器或文件迁移行为有变化时，重新执行 `docs/iCloud-Release-Readiness.md`。
5. 先由 Owner Smoke 内部组完成冒烟，再把同一构建提交给 Friends Beta 外部组。

### Owner Smoke 内部测试

`Owner Smoke` 是仅供作者本人使用的内部测试组，已启用“自动分发”。从 Xcode 上传的新构建在 Apple 处理完成后会自动加入该组，不需要每次手动选构建。不要把熟人添加为 App Store Connect 内部用户；熟人统一放入后续的 `Friends Beta` 外部组。

首次加入时：在 App Store Connect → App → Hashmark → TestFlight → Owner Smoke 点击“添加测试员”，选择现有 Account Holder 并添加。页面显示“1 个测试员、1 个构建版本”且测试员状态为“已邀请”后，在 iPhone 上使用同一 Apple Account 打开邀请邮件或 TestFlight，接受邀请并安装对应构建。

## 当前首个 Beta 的下一步

- 1.0（1）已完成后台处理：二进制“已验证”、非豁免加密“否”，没有 Missing Compliance。
- `Owner Smoke` 已创建，1.0（1）已自动加入，Account Holder 状态为“已邀请”。
- 在 iPhone 上接受 TestFlight 邀请并安装 1.0（1）。
- 完成本人设备冒烟后，再创建 `Friends Beta` 外部组并提交 Beta App Review。

## 每次发布记录模板

| 项目 | 结果 |
| --- | --- |
| 版本 / 构建 | 例如 `1.0 (1)` |
| Git commit |  |
| Archive 时间 |  |
| Validate | PASS / 说明 |
| Upload | PASS / 说明 |
| TestFlight 处理完成 | 时间 |
| 90 天到期日 |  |
| 内部冒烟 | PASS / 问题链接 |
| 外部 Beta Review | 状态 / 日期 |
| 已知问题 |  |

本手册会在本轮 S3–S7 执行过程中继续补充实际页面入口、上传结果和恢复方法。
