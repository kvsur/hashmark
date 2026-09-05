# App Store 分发签名导出验收

日期：2026-08-31

Xcode 登录 Account Holder 后，复用临时 Release archive 并以 automatic signing 执行 App Store Connect export，结果成功。

## 导出结果

- 证书类型：Cloud Managed Apple Distribution
- 导出签名 Authority：Apple Distribution
- Profile：`iOS Team Store Provisioning Profile: com.kvsur.MarkdownApp`
- Profile 到期日：2027-08-31
- Team：`Y3RP5W6ZXV`
- Application Identifier：`Y3RP5W6ZXV.com.kvsur.MarkdownApp`
- `get-task-allow`：`false`
- `beta-reports-active`：`true`
- iCloud 环境：Production
- iCloud 服务：CloudDocuments
- iCloud 容器：`iCloud.com.kvsur.MarkdownApp`
- 版本 / 构建：`1.0 (1)`
- 最低系统：iOS 16.0
- 设备族：iPhone、iPad
- 架构：arm64
- dSYM / symbols：存在

Cloud Managed Apple Distribution 由 Xcode/Apple 管理，因此本机通用钥匙串列表仍可能只显示 Apple Development；应以 export 成功、DistributionSummary、导出 App 的 codesign Authority 和 embedded profile 为最终判断依据。
