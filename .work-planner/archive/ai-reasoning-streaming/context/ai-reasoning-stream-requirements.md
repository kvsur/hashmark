# 用户原始需求

> AI generating 的过程中，如果有 thinking/reasoning，则渲染展示 thinking/reasoning 过程，UI 使用 frontend-design 设计，API 请求层可能需要适配一下。

补充约束来自仓库 `AGENTS.md`：

- 原生 SwiftUI，最低 iOS/iPadOS 18，iOS 26+ Liquid Glass 通过现有封装启用。
- UI 与业务逻辑分离，重复逻辑抽象，新文件按 feature-based 目录归位。
- 用户可见文案不得使用 emoji；图标优先 SF Symbols。
- 新增或修改 UI 文案必须补齐简中、英、繁中、日、韩、德、俄。
