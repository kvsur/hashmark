# Plan — AI 输入附件（图片 + 引用文档）

## Target architecture

新增/改动（按 CLAUDE.md feature 分层归位）：

```
Models/
├── AIAttachment.swift        # 新增：中立附件模型（image / documentReference）+ 图片压缩编码
├── AIMessage.swift           # 改：user 消息可携带 [AIAttachment]（多模态载体）
├── AIAction.swift            # 改：userContent 注入 <reference> 文档引用；messages() 透传附件
├── ChatGPTClient.swift       # 改：user 消息带附件时序列化成 content blocks（text + image_url）
├── ClaudeClient.swift        # 改：user 消息带附件时序列化成 content blocks（text + image source）
Features/AI/
├── AIAttachmentBar.swift     # 新增：附件条（缩略图/文档 chip、删除、加图/加文档按钮、计数）
├── DocumentReferencePicker.swift  # 新增：库内 .md 多选选择器（复用 FileStore.tree 树形）
├── AIWritingView.swift       # 改：promptInput 下方挂 AIAttachmentBar；附件随 start 带下去
├── AIWritingSession.swift    # 改：start 接收附件，附着到首个 user 消息；多轮不重复带图
├── AILaunch.swift            # （视需要）无需改：附件是 View 内部状态，不进 launch 载荷
```

设计要点：
- **`AIAttachment`（中立）**：`enum { case image(Data /*已压缩 JPEG*/) ; case documentReference(name: String, text: String) }`。
  图片在加入附件条时就地压缩降采样成 JPEG Data（S1 的编码器），入模型即「可直接发」的形态。
- **文档引用不是多模态**：它在 `AIAction.userContent` 里以 `<reference title="...">...</reference>` 注入文本，
  与 `<document>` 上下文并列。因此 documentReference 其实**不需要进图片块**——但为「附件条 UI 统一展示」
  仍作为一种 `AIAttachment` 存在，只是序列化时图片走块、文档在 userContent 阶段就已拼进文本。
  → 关键分工：**文档引用在 AIAction 层消费（拼进 user 文本）；图片在 client 层消费（拼成 image block）**。
- **向后兼容**：`AIMessage` 加 `attachments: [AIAttachment] = []`，默认空。两家 client `serialize` 里：
  user 消息 `attachments` 为空 → 走旧的 `"content": "<string>"`；非空 → 走 content blocks 数组。
  纯文本路径一行不改行为。

## Dependency graph

```
S1 ──> S2 ──> S3 ──> S6 ──> S7
        │              ^
        └──> S4 ──┐    │
                  ├──> S5 ──┘
        (S4 也依赖 S2 的附件模型)
```

- S1 图片压缩编码器（叶子工具，先行，S3 要用其产物）
- S2 消息层多模态载体（AIAttachment + AIMessage 扩展）
- S3 两家 client 图片序列化（依赖 S2 载体、S1 产物格式）
- S4 引用文档选择器 + 文本注入（依赖 S2 附件模型；与 S3 并行）
- S5 输入 UI 接线（依赖 S2 载体、S3 能发图、S4 能选文档）
- S6 异常处理收口（依赖 S3/S5 主链路可用）
- S7 验收 + TODO 注释审计（依赖全部）

## Phases / Steps

### S1 — 图片压缩降采样编码器
- Goal：给定相册项的原始 Data/`PhotosPickerItem`，产出 provider 安全尺寸的 JPEG Data（长边 ≤~1568px、质量可控），失败返回可区分的错误。
- Depends on: none
- Refs: C2 — 压缩参数与 media_type 约定
- Sub-steps:
  - S1.1 写 `ImageAttachmentEncoder`（或作为 `AIAttachment` 的静态方法）：`UIImage` 降采样（`ImageIO` 的 `CGImageSourceCreateThumbnailAtIndex`，避免整图解码进内存）→ JPEG 压缩。
  - S1.2 定义常量（maxLongEdge、jpegQuality、maxCount=4、单张体积上限）集中一处。
  - S1.3 失败路径：非图片/解码失败/压缩后仍超限，各返回明确错误。
- Verify：喂一张大图（如 4000px HEIC）产出 JPEG 且长边 ≤ 阈值、体积在限内；喂坏数据返回错误不崩。

### S2 — 消息层多模态载体
- Goal：`AIMessage` 能携带附件，且默认空时行为与现状完全一致。
- Depends on: S1
- Refs: C3 — AIMessage 现状
- Sub-steps:
  - S2.1 新增 `AIAttachment`（image(Data) / documentReference(name,text)），放 Models/。
  - S2.2 `AIMessage` 加 `attachments: [AIAttachment] = []`（仅 user 有意义），构造器与 Equatable 兼容。
  - S2.3 复核所有现有 `AIMessage(...)` 构造点默认空附件、不受影响（编译即证）。
- Verify：项目编译通过；现有纯文本消息构造不需改动。

### S3 — 两家 client 图片序列化
- Goal：user 消息带图片附件时，两家各自序列化成正确的 content blocks；无附件时逐字节保持旧形状。
- Depends on: S2
- Refs: C2, C4, C5 — 两家契约与序列化点
- Sub-steps:
  - S3.1 ChatGPTClient.serialize：user 有 image 附件 → content 数组 [text block, image_url(data URI) …]；否则原样字符串。
  - S3.2 ClaudeClient.serialize：user 有 image 附件 → content 数组 [text block, image(source base64) …]；否则原样字符串。
  - S3.3 抽出「把图片附件转 base64/data-uri」的共享小工具，避免两家各写一遍（DRY）。
  - S3.4 确认 documentReference 类附件在 client 层被忽略（它已在 S4 于 userContent 阶段拼进文本）。
- Verify：构造带 1 张图的 user 消息，两家 JSON 各含正确图片块；不带附件时 JSON 与改造前逐字节一致。

### S4 — 引用文档选择器 + 文本注入
- Goal：能从库内挑 .md（多选），其正文以 `<reference>` 注入 user 消息文本。
- Depends on: S2
- Refs: C6, C9, C10 — 注入点、文档来源、可复用树形
- Sub-steps:
  - S4.1 写 `DocumentReferencePicker`：复用 `FileStore.tree` 的折叠树，多选 .md（排除文件夹/Inbox），确认后回传 [(name,text)]。读文本用 `FileStore.readText`。
  - S4.2 `AIAction.userContent`：把 documentReference 附件按 `<reference title="…">…</reference>` 注入，位置在 `<document>` 之后、用户 note 之前，边界清晰、防 prompt 注入。
  - S4.3 空文档 / 读取失败的引用项跳过并记录；超大文档给软提示（假设项，按 summary 处理）。
- Verify：引用一篇非空 .md 跑自由创作，user 消息文本含 `<reference>` 包裹的该文正文；多选顺序稳定。

### S5 — 输入 UI 接线（附件条）
- Goal：续写 + 自由创作的输入区能加/删附件并发送；其它动作无附件入口。
- Depends on: S3, S4
- Refs: C7, C8, C11 — UI 挂载、会话入口、两个 AI 入口与动作门控
- Sub-steps:
  - S5.1 写 `AIAttachmentBar`：横向缩略图（图片）+ 文档 chip（SF Symbol doc.text + 文件名），每项可删；「加图片」(PhotosPicker) 与「引用文档」两个按钮；到上限禁用加图并提示。文案禁 emoji、图标用 SF Symbols。
  - S5.2 `AIWritingView`：仅当 `action` ∈ {continueWriting, custom} 时在 promptInput 下方渲染 AIAttachmentBar；附件存为 `@State`。选图经 S1 压缩后入附件条。
  - S5.3 附件随 `start()` 下传：`AIAction.messages` 接收 attachments，附到首个 user 消息；`AIWritingSession.start` 透传。多轮（refine/regenerate）不重复带图（假设项）。
  - S5.4 附件条仅 idle 阶段可编辑，进入流式/完成后只读或隐藏。
- Verify：自由创作加 1 图 + 引 1 文档，发起后模型收到图与文档参考；润色动作无附件入口；上限提示生效。

### S6 — 异常处理收口
- Goal：把附件相关的失败都变成可读、不崩、不误导的体验。
- Depends on: S3, S5
- Refs: C2, C12 — 异常来源、降级重试路径
- Sub-steps:
  - S6.1 图片加载/压缩失败：单项跳过 + 附件条内可读提示，不影响其余附件与发送。
  - S6.2 模型不支持视觉（多为 4xx）：在带图请求失败时补语义提示「所选模型可能不支持图片」，与现有 AIError.http 截断协作，不裸抛。
  - S6.3 确认 `streamWithToolFallback` 降级重试时请求体仍带图片块（makeRequest 闭包重建消息应保持附件）。
  - S6.4 空附件、超大单图、超限张数的边界提示文案（走本地化 catalog，禁 emoji）。
- Verify：故意用无视觉模型发图 → 得到可读提示而非乱码；坏图被跳过其余仍发；降级重试仍带图。

### S7 — 验收 + TODO 注释审计
- Goal：DoD 七项逐条过；未做范围留明确 TODO。
- Depends on: S1, S2, S3, S4, S5, S6
- Refs: C1 — 范围边界
- Sub-steps:
  - S7.1 抓包：无附件路径两家逐字节回归；带图两家块格式正确（需用户 API Key，属凭据，卡则记 blocked）。
  - S7.2 UI 走查：两个入口 × 生成类动作，附件条、缩略图、删除、上限、只读态。
  - S7.3 新增文案全部进 catalog 7 语言、无 emoji、无 stale（沿用归档 i18n 计划的校验手法）。
  - S7.4 拍照、外部文件引用两处留 TODO 注释，指向后续迭代。
  - S7.5 逐条对照 summary 的 DoD 七项。
- Verify：DoD 七项全部通过（S7.1 的带图抓包若无 Key 可留待用户自验）。

### S8 — 图片能力门控（用户自声明开关）
- 缘起：本 App 支持用户自定义任意 provider/model（ChatGPT/Claude/DeepSeek/BigModel/MiniMax…），App 无法可靠判断某 provider+model 是否支持视觉；文本模型收到内联图片常返回 200 文字拒绝（如 MiniMax 文本模型答「访问不了链接」），事后也难检测。故不由 App 猜测，改由用户在配置里自声明——与现有「响应格式手动选」同一哲学。
- Goal：图片附件是否可用，由用户在 AI 配置里的开关决定；文档引用不受影响（纯文本、任意模型可读）。
- Depends on: S5
- Refs: C1
- 决策（用户确认）：图片选择按钮**常态展示**；开关关闭时点它**跳转 AI 配置页**（而非隐藏）；开关下方小字 tip 提示用户自行确认 provider/model 是否支持附件。
- Sub-steps:
  - S8.1 AIConfig 加 supportsImages: Bool（默认 false）；自定义 Decodable 迁移，旧配置缺键回退 false（synthesized Decodable 不认默认值）。
  - S8.2 AIConfigEditorView 加开关 + footer tip；文案本地化。
  - S8.3 AIAttachmentBar 加 supportsImages + onNeedsConfig：图片按钮常显，开→PhotosPicker、关→onNeedsConfig()。
  - S8.4 AIWritingView 呈现 AIConfigEditorView sheet，onDismiss 重载 config 刷新门控；session 仍用初始 config（切图能力不改端点）。
- Verify：开关关时点图片按钮进配置页；开后返回可选图；文档引用与开关无关始终可用；旧配置能正常读取不崩。

### S9 — 图片入口合并「拍照 + 相册」
- 缘起：原计划 out-of-scope 的「拍照」现补齐。PhotosPicker 只含相册，拍照需 UIImagePickerController。
- Goal：一个「图片」入口，点击弹「拍照 / 从相册选择」；拍照走相机、相册走 PhotosPicker；仍受 supportsImages 门控（关→跳配置）。
- Depends on: S5
- Refs: C7
- Sub-steps:
  - S9.1 写 CameraPicker（UIViewControllerRepresentable 包 UIImagePickerController sourceType=.camera），产出图片 Data。
  - S9.2 Info.plist 加 NSCameraUsageDescription（本地化）。
  - S9.3 AIAttachmentBar 图片入口改 Menu：拍照（isSourceTypeAvailable(.camera) 才显，模拟器无相机）+ 从相册选择（.photosPicker(isPresented:) 命令式）；supportsImages 关时整入口→onNeedsConfig。
  - S9.4 拍照结果同样经 ImageAttachmentEncoder 压缩入附件。
- Verify：真机点「图片」弹菜单，拍照/相册各得一张压缩图入附件条；模拟器无「拍照」项；开关关→跳配置。

### S10 — 文件选择入口（文本 + PDF + 图片）
- 决策（用户确认）：文件入口接受文本/PDF/图片；文本→注入(documentReference)、图片→图片块、PDF→原生文档块（受门控、依赖模型支持，兼容性风险已知）。
- Goal：新增「文件」入口，用 fileImporter 选外部文件，按类型路由。
- Depends on: S5（复用 S2 载体 / S3 序列化模式 / S4 注入）
- Refs: C2, C4, C5, C6
- Sub-steps:
  - S10.1 AIAttachment 加 .pdf(data,name)；PDF 体积上限常量（base64 膨胀，留余量）。
  - S10.2 AIMessage 广义 rich 附件（image + pdf）；两家 serialize 加 PDF 块——**两路同改**（ChatGPT content part type:"file"+file_data data URI；Claude block type:"document"+source.base64 application/pdf）。
  - S10.3 fileImporter：allowedContentTypes = [.plainText/.text/源码, .pdf, .image]；按 UTType 路由——文本读文本→documentReference、图片经编码→image、PDF→pdf。
  - S10.4 门控广义化：supportsImages 现覆盖图片与 PDF；文件入口常显（文本不受限），门控关时选到图片/PDF 丢弃并提示去配置；文本正常入。
  - S10.5 更新 supportsImages 的 label/tip 文案为「图片与 PDF」。
- Verify：文件入口选 txt→注入、选图→图片块、选 PDF（开关开）→PDF 块两家格式正确；开关关时图片/PDF 被拦、文本仍入；扫描件 PDF 提不出可发（原生块不依赖文本层）。

### S11 — 入口提示文案 + 收尾
- Goal：入口上方加引导文案；清理 stale；文案全量本地化；TODO 收口；DoD 复核。
- Depends on: S9, S10
- Refs: C1
- Sub-steps:
  - S11.1 Photo/Document/File 入口上方加提示文案「添加合适的附件，让 AI 帮你生成更好的内容」（禁 emoji）。
  - S11.2 移除已 stale 的 "Tell me what you want first." catalog key。
  - S11.3 本轮新增文案（相机权限说明、文件/拍照入口、提示、PDF 相关提示等）全量进 catalog 6 语言、无 emoji、无 stale。
  - S11.4 更新 AIAttachmentBar 里「拍照」「外部文件」TODO 注释为已实现。
  - S11.5 DoD 复核（含新增能力）。
- Verify：入口上方提示常显；catalog 无 stale/缺译/emoji；TODO 已更新。

## Notes
- S9/S10 相互独立，均依赖 S5，可并行；S11 收尾依赖二者。
- PDF 原生块跨 provider 兼容性风险（用户已知选定）：多数 OpenAI 兼容代理对 file part 支持不一，失败时走现有 AIError.http 提示；文本类文件是万能兜底。
- 门控语义：supportsImages 广义为「图片/PDF 等富附件」总开关；文本（文档引用/文本文件）永不门控。
- 复用优先：引用文档选择器复用 DocumentSwitcherSheet 的树形；图片→base64 工具两家共享；不重复造轮子。
- 最大陷阱（归档 i18n 计划 S6 教训重演）：ClaudeClient 与 ChatGPTClient 是两条独立序列化路径，改图片块极易只改一半 → S3 必须两家同时改、同时抓包验。
- 文档引用与图片是**两个消费层**：文档在 AIAction（文本），图片在 client（块）。别把文档也塞进图片块。
