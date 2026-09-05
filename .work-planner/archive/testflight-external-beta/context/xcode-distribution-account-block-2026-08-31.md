# Xcode 分发签名预检与账户阻塞

日期：2026-08-31

## 已通过

- Release / generic iOS device 自动签名构建成功。
- 临时 Release archive 成功。
- Team、Bundle ID、CloudDocuments、iCloud container、iOS 16、arm64 和 dSYM 均进入 archive。
- 开发签名使用现有 Apple Development 证书和团队开发描述文件。

## 阻塞

使用 `MarkdownApp/AppStoreExportOptions.plist` 执行 App Store Connect export 时失败：

- `No Accounts`
- `No profiles for 'com.kvsur.MarkdownApp' were found`

本机钥匙串当前只有 Apple Development identity；Xcode 没有可用于 App Store 分发的已登录账户，因此不能自动取得 Apple Distribution 证书与 App Store provisioning profile。

## 恢复方法

1. 打开 Xcode → Settings → Accounts。
2. 点左下角 `+`，选择 Apple Account，登录当前 Account Holder 的 Apple 账户并完成双重认证。
3. 选中 Team `Y3RP5W6ZXV`，确认账号状态正常。
4. 回到本计划重新执行临时 archive export；Automatic Signing 应创建或获取 Apple Distribution 与 App Store profile。

不要把密码、验证码、证书私钥或导出的 `.p12` 保存到仓库。
