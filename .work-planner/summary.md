# Plan Summary

## Goal

Hashmark 的功能开发、调试与真机验证已经完成；本计划把当前可发布构建转成一个可由熟人通过 TestFlight 安装、持续反馈的外部 Beta，同时保留以后增加收费功能并正式公开上架的空间。

## Scope

- In:
  - 等待并确认 Apple 身份复核通过，恢复 App Store Connect 完整访问。
  - 创建 Hashmark 的 App Store Connect iOS 条目并核对正式签名能力。
  - 补齐公开隐私政策、App 内隐私入口，以及向第三方 AI 发送数据前的明确授权机制。
  - 准备 TestFlight Beta 文案、联系信息、测试重点和审核说明。
  - 归档、验证、上传第一个构建，先完成本人内部冒烟，再提交外部 TestFlight Beta Review。
  - 通过邮件邀请熟人测试，记录构建 90 天有效期和反馈入口。
- Out:
  - 当前阶段不把 App 发布到正式 App Store，也不申请 Unlisted App。
  - 不在本计划实现收费、内购、订阅或广告；收费模型另行设计和开发。
  - 不制作正式 App Store 产品页的完整截图与七语言营销元数据；留到公开发布阶段。
  - 不在中国大陆正式发行；备案完成后再单独开启。

## Constraints / Coexistence

- Apple 身份复核是外部阻塞；等待期间先完成不依赖后台访问的 Beta 交接材料。
- Bundle ID 固定为 `com.kvsur.MarkdownApp`，Team 固定为 `Y3RP5W6ZXV`，iCloud 容器固定为 `iCloud.com.kvsur.MarkdownApp`，不得在发布途中漂移。
- TestFlight 外部测试的首个构建需要 Beta App Review；每个构建最长可测试 90 天。
- 隐私政策必须通过无需登录的公开 HTTPS URL 访问，并在 App 内易于找到。
- 向第三方 AI Provider 发送可能包含个人信息的提示词、文稿或附件前，必须明确说明接收方和用途并取得用户授权；不能用启动时笼统的“同意全部条款”替代。
- 熟人使用邮件邀请加入外部测试组，不把他们添加为 App Store Connect 内部用户。
- 当前发布基线使用 Xcode 26.6，满足 2026-04-28 起的 Xcode 26 / iOS 26 SDK 上传要求。

## Definition of Done

1. Apple 身份复核通过，App Store Connect、Certificates/Identifiers/Profiles 和协议页面均可正常访问。
2. 隐私政策公开 URL 可访问，App 内“关于”页有易发现入口，第三方 AI 数据发送前有可撤回的明确授权。
3. App Store Connect 中存在与仓库 Bundle ID 一致的 Hashmark iOS 条目。
4. Release archive 通过 Xcode Validate/Upload，处理后构建状态可用于 TestFlight。
5. 本人通过 TestFlight 安装 App Store 签名构建并完成核心冒烟。
6. 首个外部构建通过 TestFlight Beta App Review；至少一名熟人通过邮件邀请成功安装并确认可用。
7. 已记录构建到期时间、反馈渠道、已知问题和下一构建的版本规则。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | App Store Connect iPhone App 不可用截图 | `context/app-store-connect-ios-unavailable-2026-08-29.jpg` | S1 身份复核前故障证据 |
| C2 | iCloud 发布就绪清单 | `docs/iCloud-Release-Readiness.md` | S3/S4 的 Team、容器、隐私与归档验收基线 |
| C3 | App Store 导出配置 | `MarkdownApp/AppStoreExportOptions.plist` | S4 正式导出与上传配置 |
| C4 | Xcode 工程发布设置 | `MarkdownApp/MarkdownApp.xcodeproj/project.pbxproj` | S3/S4 核对 Bundle ID、版本、Team、部署目标和设备族 |
| C5 | iCloud entitlement | `MarkdownApp/MarkdownApp/MarkdownApp.entitlements` | S3/S4 核对发布签名中的 iCloud 能力 |
| C6 | Privacy manifest | `MarkdownApp/MarkdownApp/PrivacyInfo.xcprivacy` | S4 上传验证与后续隐私回答基线 |
| C7 | 已完成的 iCloud/归档验收记录 | `.work-planner/archive/ios16-icloud-documents-sync/state.json` | S3/S4 复用既有真机、签名和归档证据 |
| C8 | Apple TestFlight 官方流程 | `https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview` | S2/S5/S6 外部测试要求与 90 天期限 |
| C9 | Apple Unlisted App 官方说明 | `https://developer.apple.com/support/unlisted-app-distribution` | 记录为何本阶段不用 Unlisted |
| C10 | Apple 账号访问问题说明 | `https://developer.apple.com/help/account/access/resolving-access-issues` | S1 核对身份、会员、协议与访问权限 |
| C11 | Apple 构建上传说明 | `https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds` | S4 Validate/Upload 与处理状态 |
| C12 | Apple App Review Guidelines 5.1.1/5.1.2 | `https://developer.apple.com/app-store/review/guidelines/` | S2a 隐私政策、App 内入口和第三方 AI 明确授权要求 |
| C13 | Apple App Privacy 配置说明 | `https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/` | S2a/S3 公开隐私 URL 与后台隐私回答 |
| C14 | 当前“关于”页 | `MarkdownApp/MarkdownApp/Features/Settings/AboutView.swift` | S2a 添加易访问隐私政策入口的位置 |
| C15 | Hashmark 数据流审计 | `.work-planner/context/s2a-data-flow-audit-2026-08-30.md` | S2a 政策内容、App Privacy 回答与 AI 授权边界的事实基线 |
| C16 | App Store Connect 账户未启用提示 | `.work-planner/context/app-store-connect-itunes-connect-not-enabled-2026-08-30.md` | S1 二次身份审核提交后仍未开通 App Store Connect 的最新证据 |
| C17 | S2a 真机隐私授权验收 | `.work-planner/context/s2a-device-consent-verification-2026-08-30.md` | S2a 拒绝、允许、更换 Endpoint、撤回及隐私链接的最终真机证据 |
| C18 | S2a 隐私政策七语言与路由验收 | `.work-planner/context/s2a-policy-language-routing-2026-08-30.md` | S2a 七语言正文、下拉选择、显式 App 语言参数与系统语言回退的实现及验证证据 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| Apple 身份复核何时完成 | open | 未通过前无法创建条目或上传 | S1.1 |
| `Hashmark` 商店名称是否可用 | open | 名称可用性只能在创建条目时确认 | S3.1；如占用再与作者确定备选名 |
| App Store Connect 主语言使用 English (U.S.) | assumed | 全球 Beta 的默认元数据语言；以后可增加本地化 | S3.1 |
| Beta 反馈邮箱使用 `hello1024lc@gmail.com` | assumed | 仓库 README 已公开该支持邮箱 | S2.2 |
| 隐私政策托管位置 | confirmed | 使用现有 `kvsur/hashmark` 仓库的 GitHub Pages | S2a.3 |
| 第三方 AI 授权按 Provider/Endpoint 记录并可撤回 | assumed | 接收方变化时旧授权不应被复用 | S2a.5 |
| 熟人均以外部测试者邮件地址加入 | assumed | 避免授予 App Store Connect 后台权限 | S6.2 |
| 未来收费采用付费下载、一次性内购或订阅 | open | 会改变 StoreKit 架构、协议和公开发布资料 | TestFlight 稳定后另开收费功能计划 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 当前分发方式 | TestFlight 外部测试 | 搜索不到、适合熟人 Beta、后续可沿用同一条目公开发布 |
| Unlisted App | 当前不申请 | Apple 不把它作为 Beta 渠道，且未来版本会继续保持 Unlisted |
| 正式 App Store 发布 | 收费功能准备完成后再做 | 避免把当前免费 Beta 误当成正式产品发布 |
| 未来公开发行地区 | 全球其他地区，暂不包含中国大陆 | 先避开 ICP 备案阻塞；以后可追加大陆区 |
| 当前代码范围 | 发布验证优先，不主动新增功能 | 用户确认开发、调试、验证已经 ready |
| 隐私合规补充 | 外部 TestFlight 前完成政策、入口与第三方 AI 授权 | Apple 审核规则的发布前置条件，不属于可延后的营销功能 |
| 隐私政策托管 | GitHub Pages | 免费 HTTPS，与现有公开仓库和支持渠道一致 |
