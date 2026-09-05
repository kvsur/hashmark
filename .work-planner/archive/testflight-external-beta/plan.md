# Plan

## Target release flow

```text
Apple 身份复核 ──┐
Beta 材料准备 ───┼─> App 条目与签名预检 -> Archive/Upload -> 内部冒烟 -> 外部 Beta Review -> 熟人测试运行
隐私政策与授权 ──┘
```

TestFlight 是本计划的终点。收费功能与正式公开 App Store 发布在 Beta 稳定后另开计划，复用同一个 Bundle ID 和 App Store Connect 条目。

## Dependency graph

```text
S1 ───┐
S2 ───┼──> S3 ──> S4 ──> S5 ──> S6 ──> S7
S2a ──┘
```

## Phases / Steps

### S1 — 恢复 Apple 发布后台访问

- Goal: 身份复核结束后，确认账号、会员、协议和发布后台全部可用。
- Depends on: none
- Refs: C1, C10, C16, C19, C20 — 账号故障证据、Apple 官方排障条件、激活确认与后台访问验收
- Sub-steps:
  - S1.1 等待 Apple 身份复核通过并保存通过通知。
  - S1.2 登录 `developer.apple.com/account` 与 App Store Connect，确认会员为 Active、角色为 Account Holder、双重认证正常。
  - S1.3 检查 Business/Agreements 与 Developer Program License Agreement，不留待接受协议。
  - S1.4 打开 Certificates, Identifiers & Profiles，确认 Team `Y3RP5W6ZXV` 和 App ID `com.kvsur.MarkdownApp` 可访问。
- Verify: 三个后台入口均可用，会员有效，无身份、协议或权限警告。

### S2 — 准备 TestFlight Beta 交接材料

- Goal: 在账号等待期间完成上传后会立即用到的测试文案和联系人资料。
- Depends on: none
- Refs: C8, C9 — TestFlight 必填信息和不使用 Unlisted 的边界
- Sub-steps:
  - S2.1 起草 English (U.S.) 与简体中文 Beta App Description。
  - S2.2 确认反馈邮箱、Beta Review 联系人姓名、国际格式电话和联系邮箱。
  - S2.3 起草 `What to Test`，覆盖本地文稿、导入/编辑/预览、iCloud 开关与 BYOK AI 的预期边界。
  - S2.4 起草 Beta Review Notes，说明 iCloud 默认关闭、AI 为可选 BYOK、核心功能无需账号或 API Key。
  - S2.5 建立一份熟人测试名单模板，只记录邀请邮箱与邀请/安装状态。
- Verify: 所有字段可直接粘贴进 App Store Connect，且不包含秘密、API Key 或测试者无权访问的数据。

### S2a — 补齐隐私政策与第三方 AI 明确授权

- Goal: 同时满足 Apple 对公开隐私政策、App 内入口和第三方 AI 数据分享授权的要求。
- Depends on: none
- Refs: C2, C6, C12, C13, C14, C15, C17, C18 — 现有数据声明、Apple 审核规则、当前入口位置、数据流审计、真机授权和七语言路由验收
- Resolves: 隐私政策托管位置；AI 授权粒度假设
- Sub-steps:
  - S2a.1 审计本地文稿、iCloud、API Key/配置、提示词、附件、相机/照片、联网搜索和第三方 Provider 的实际数据流与保留方式。
  - S2a.2 起草以英文为主、含简体中文版本的 Hashmark 隐私政策，覆盖收集/传输、用途、第三方、保留/删除、撤回和联系渠道。
  - S2a.3 将隐私政策发布到无需登录的公开 HTTPS URL，并验证移动端可访问。
  - S2a.4 在 App“关于”页增加 Privacy Policy 入口，新增 UI 文案补齐简中/英/繁中/日/韩/德/俄。
  - S2a.5 在第一次向指定 Provider/Endpoint 发送用户内容前展示明确披露并取得授权；接收方变化时重新授权，并在设置中提供撤回方式。
  - S2a.6 为授权状态与发送门禁增加回归测试，完成 Debug/Release 构建及真机交互验证。
  - S2a.7 将隐私政策扩展至 App 的七种语言，使用下拉切换，并让 App 通过 `lang` 参数传递当前生效语言；无有效参数时使用系统支持语言，最后回退英文。
- Verify: 政策 URL 公开可用，App 内可打开；七语言路由、下拉切换与回退规则可验证；未授权时任何提示词/文稿/附件均不会发往第三方 AI，授权与撤回路径可验证。

### S3 — 创建 App 条目并完成正式签名预检

- Goal: 创建与仓库标识一致的 iOS 条目，并确认自动签名可以生成发布所需资产。
- Depends on: S1, S2, S2a
- Refs: C2, C4, C5, C7, C21, C22, C23, C24, C25, C26 — 固定配置、后台验收、分发签名与独立发布留痕要求
- Resolves: `Hashmark` 名称可用性；主语言假设
- Sub-steps:
  - S3.1 在 App Store Connect 新建 iOS App：商店名称 `Hashmark: AI Markdown Editor`、主语言 English (U.S.)、Bundle ID `com.kvsur.MarkdownApp`、内部 SKU `hashmark-ios`，并填写 S2a 的隐私政策 URL。
  - S3.2 在 Developer 后台确认 Explicit App ID 已启用 iCloud Documents，容器为 `iCloud.com.kvsur.MarkdownApp`。
  - S3.3 在 Xcode Accounts 刷新账号，让 Automatic Signing 获取/创建 Apple Distribution 证书与 App Store provisioning profile。
  - S3.4 核对版本 `1.0`、构建号 `1`、最低 iOS 16、iPhone+iPad；若已有同号上传记录，仅递增构建号。
- Verify: App 条目存在，Xcode Release 签名无错误，所有发布标识和 iCloud 容器与仓库基线一致。

### S4 — 归档、验证并上传首个构建

- Goal: 生成真正由 App Store 分发链处理的 Release 构建。
- Depends on: S3
- Refs: C2, C3, C4, C5, C6, C7, C11, C24, C27, C28, C29 — 归档验收、导出配置、隐私、上传、处理完成和独立操作留痕要求
- Sub-steps:
  - S4.1 选择 Any iOS Device (arm64) / generic iOS device，以 Release 执行 Archive。
  - S4.2 在 Organizer 中检查 archive 的版本、签名、entitlement、PrivacyInfo、App Icon 和 dSYM。
  - S4.3 执行 Validate App，解决所有 error；对 warning 逐项记录结论。
  - S4.4 选择 App Store Connect / Upload，使用 automatic signing 上传。
  - S4.5 等待构建处理完成，处理 Export Compliance 提示，并检查生成的隐私报告与构建状态。
- Verify: App Store Connect/TestFlight 可看到 `1.0` 的可测试构建，无 Invalid Binary、Missing Compliance 或签名/隐私阻断。

### S5 — 本人内部 TestFlight 冒烟

- Goal: 在邀请熟人前验证“Apple 实际分发的构建”，而不是 Xcode 安装包。
- Depends on: S4
- Refs: C2, C8, C24, C30 — 发布阻断条件、内部测试流程、Owner Smoke 验收与独立操作留痕要求
- Sub-steps:
  - S5.1 创建内部测试组 `Owner Smoke` 并添加当前 Account Holder。
  - S5.2 从 TestFlight 安装上传构建，确认首次启动、创建/编辑/预览/分享/导入正常。
  - S5.3 验证 iCloud 默认关闭，并做一次开启、同步、关闭路径的非破坏性冒烟。
  - S5.4 在未配置 API Key 时确认核心功能可用；如有真实 Key，仅做一次可选 BYOK 冒烟且不记录密钥。
  - S5.5 记录崩溃、阻断问题和可接受的已知问题；阻断问题必须上传新构建重测。
- Verify: TestFlight 安装包在目标 iPhone/iPad 上通过核心冒烟，无数据丢失、启动失败或发布阻断问题。

### S6 — 外部 Beta Review 与熟人分发

- Goal: 让有限的熟人通过正式外部 TestFlight 邀请安装。
- Depends on: S5
- Refs: C8, C24 — 外部组、首构建 Beta Review、邀请规则与独立操作留痕要求
- Sub-steps:
  - S6.1 创建外部测试组 `Friends Beta`，填入 Beta 描述、What to Test、反馈和审核联系信息。
  - S6.2 先用邮件逐一邀请熟人，不启用公开邀请链接。
  - S6.3 将通过内部冒烟的构建加入外部组并提交 TestFlight Beta App Review。
  - S6.4 处理 Beta Review 的问询或拒绝；需要二进制修复时递增构建号并重新上传。
  - S6.5 获批后通知测试者，确认至少一人完成接受邀请、安装、启动和基础操作。
- Verify: 首个外部构建获批，至少一名非 App Store Connect 用户通过邮件安装并确认可用。

### S7 — 建立 Beta 运行与后续收费阶段交接

- Goal: 避免首个 TestFlight 构建发出后无人维护，并为收费版规划留下清晰输入。
- Depends on: S6
- Refs: C8, C24 — 构建 90 天有效期、反馈指标与独立发布交接要求
- Sub-steps:
  - S7.1 记录构建上传日、到期日和下一次最晚上传时间。
  - S7.2 固定版本规则：公开版本号保持产品语义，任何再次上传都递增 build number。
  - S7.3 汇总 TestFlight crashes、screenshots、文字反馈和已知问题，区分阻断、收费前必修和可延后。
  - S7.4 定义进入收费功能计划的条件，并保留“未来公开全球但暂不含中国大陆”的决定。
  - S7.5 Beta 稳定后新建收费功能计划，届时再确定付费下载、一次性内购或订阅。
  - S7.6 完成并演练 `docs/App-Store-Release-Runbook.md`，确保作者可独立完成下一次版本/构建升级、Archive、Validate、Upload 和 TestFlight 分发。
- Verify: 到期与更新责任明确，反馈可追踪，收费/公开发布边界清晰，作者可按发布手册独立完成下一次迭代。
