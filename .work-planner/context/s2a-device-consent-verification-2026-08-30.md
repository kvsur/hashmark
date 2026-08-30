# S2a 真机隐私授权交互验收

日期：2026-08-30

验收设备：已安装 `master` 合并版本的用户 iPhone。

用户报告以下五项结果：

- 拒绝授权后不发送：PASS
- 允许授权后可正常生成：PASS
- 更换 Endpoint 后重新询问：PASS
- 撤回授权后再次阻断：PASS
- App 内隐私政策链接可打开：PASS

结合已完成的自动回归、Release 真机构建、隐私清单及 entitlement 检查，S2a 的公开政策、App 内入口和第三方 AI 明确授权验收条件全部满足。
