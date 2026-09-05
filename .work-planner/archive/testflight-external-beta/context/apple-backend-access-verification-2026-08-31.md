# Apple 发布后台访问核对

日期：2026-08-31

本记录仅保留发布所需状态，不保存 Apple 账户邮箱、电话或地址等个人信息。

## App Store Connect

- App 页面可访问并可新建 App。
- 用户和访问页面确认当前账号为 Account Holder，并具有管理所有 App 的权限。
- 免费 App 协议状态为有效，有效期至 2027-07-23。
- 付费 App 协议状态为“新”；按当前 TestFlight 免费 Beta 与“收费另开计划”的既定范围，暂不签署。
- 欧盟 DSA 交易商状态和法律实体信息尚未完成；这不阻塞当前 TestFlight，但必须在后续面向欧盟的 App Store 正式分发前处理。

## Apple Developer

- Apple Developer Program 账户页可访问，会员续订日期为 2027-07-24。
- 登录流程成功，未出现身份复核、双重认证或权限错误。
- Team `Y3RP5W6ZXV` 可访问。
- App ID `com.kvsur.MarkdownApp` 与 `com.kvsur.MarkdownApp.HashmarkShareExtension` 均存在。
- Certificates 页面可访问，当前可见开发证书；发布证书与描述文件在 S3 正式签名预检中继续核对或由 Xcode 管理。

结论：S1 对当前 TestFlight 范围的访问、会员、角色、协议与后台入口验收通过。付费协议及欧盟 DSA 合规转为正式收费/公开发布前置事项。
