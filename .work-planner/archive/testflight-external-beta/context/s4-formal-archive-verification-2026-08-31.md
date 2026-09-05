# S4 正式 Release archive 验收

日期：2026-08-31

- 配置：Release
- 目标：generic iOS device
- 版本 / 构建：`1.0 (1)`
- Bundle ID：`com.kvsur.MarkdownApp`
- Team：`Y3RP5W6ZXV`
- 架构：arm64
- iCloud 服务：CloudDocuments
- iCloud 容器：`iCloud.com.kvsur.MarkdownApp`
- `PrivacyInfo.xcprivacy`：存在且 plist 校验通过
- App Icon：iPhone/iPad 图标和 Assets.car 存在
- dSYM：`MarkdownApp.app.dSYM` 存在
- Archive：成功

Archive 内部使用 Apple Development 与 `get-task-allow=true`，这是 Xcode automatic signing 的中间 archive 状态；App Store 导出/上传时必须由 Cloud Managed Apple Distribution 重新签名并变为 `get-task-allow=false`。判断上传资格时应检查导出/上传签名，不应把中间 archive 的开发签名误判为最终分发签名。
