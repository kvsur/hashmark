# Plan — 设置页（主题 / 语言 / AI 配置 / 关于）

## Target architecture

按 CLAUDE.md 的 feature-based 分层，新增：

```
MarkdownApp/MarkdownApp/
├── Models/
│   ├── ThemePreference.swift      # enum system/light/dark → ColorScheme? 映射
│   ├── SettingsStore.swift        # @Observable，UserDefaults 封装（theme/language）
│   ├── AIConfig.swift             # Codable：baseURL/model/apiKey/responseFormat
│   └── AIConfigStore.swift        # 读写 Application Support/AIConfig.json
└── Features/Settings/
    ├── SettingsView.swift         # 设置页主体（Form 分区：主题/语言/AI/关于）
    ├── AIConfigEditorView.swift   # AI API 配置 modal（取消/保存）
    └── AboutView.swift            # 关于弹层（开发者 email，mailto 可点）
```

- 主题应用点：App 入口 / 根视图注入 `SettingsStore` 到 environment，并在根视图挂 `.preferredColorScheme(store.colorScheme)`。可用性判断（若有）收敛此处。
- 设置入口：根 `FileBrowserView`（isRoot）工具栏 `topBarLeading` 加齿轮按钮（SF Symbol `gearshape`），以 sheet 形式弹出 `SettingsView`（独立 NavigationStack），与文件节点的 navigationDestination 互不干扰。
- 复用：AI 配置的「响应格式」用 enum + Picker；SettingsView 用 Form/Section；沿用既有 `NameInputSheet` 之类不涉及。

## 存储契约

- `SettingsStore`（UserDefaults，suite=standard）
  - key `theme` → ThemePreference.rawValue（缺省 → system）
  - key `language` → 占位（本期不真正切换）
  - `@Observable`，供根视图 `.preferredColorScheme` 响应式更新。
- `AIConfigStore`
  - 路径：`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask)` 下 `AIConfig.json`。
  - 目录不存在则 `createDirectory(withIntermediateDirectories: true)`。
  - `load() -> AIConfig`（文件缺失/损坏 → 返回空默认值），`save(_:) throws`（Codable → JSON 落盘）。

## Phases / Steps

### S1 — 本地存储基座（模型 + Store）
- Goal: 主题/语言偏好与 AI 配置的读写能力就绪，数据落在正确目录。
- Sub-steps:
  - S1.1 `ThemePreference` enum（system/light/dark）+ `var colorScheme: ColorScheme?`（system→nil）
  - S1.2 `SettingsStore`（@Observable，UserDefaults 封装 theme/language；默认 system，有存储优先）
  - S1.3 `AIConfig`（Codable：baseURL/model/apiKey/responseFormat enum chatgpt|claude）
  - S1.4 `AIConfigStore`（读写 Application Support/AIConfig.json，缺目录先建、缺文件返回默认）
- Verify: 能存取；写入后文件出现在 Application Support 而非 Documents。

### S2 — 主题应用到全局
- Goal: 三种主题即时全局生效并持久化。
- Sub-steps:
  - S2.1 App 入口/根视图创建并注入 `SettingsStore`（@State + environment）
  - S2.2 根视图 `.preferredColorScheme(store.colorScheme)`
- Verify: 切 Light/Dark/System 立刻全局变化；重启后保持；未设置时跟随系统。

### S3 — 设置入口 + 设置页骨架 + 主题选择
- Goal: 主页可进入设置页，看到分区并能选主题。
- Sub-steps:
  - S3.1 根 FileBrowserView 工具栏 `topBarLeading` 齿轮按钮（gearshape）→ sheet 打开 SettingsView（独立 NavigationStack + 完成按钮关闭）
  - S3.2 `SettingsView`：Form 四个 Section（主题 / 语言 / AI 配置 / 关于）
  - S3.3 主题 Section：Picker(System/Light/Dark) 绑定 SettingsStore
- Verify: 主页左上有设置按钮；设置页四区块齐全；选主题生效。

### S4 — 语言占位 + 关于
- Goal: 语言占位入口与关于弹层。
- Sub-steps:
  - S4.1 语言 Section：一个「切换语言」按钮，点击给「多语言即将支持」占位反馈（alert 或 sheet，无 emoji）
  - S4.2 关于 Section：点击弹出 `AboutView`，显示开发者 email hello1024lc@gmail.com（`Link`/mailto 可点）
- Verify: 语言按钮有占位反馈不崩；关于弹出显示 email 且可点发邮件。

### S5 — AI API 配置编辑器（modal）
- Goal: 独立 modal 编辑并本地保存 AI 配置，关闭不保存。
- Sub-steps:
  - S5.1 `AIConfigEditorView`：BaseURL(TextField)、Model(TextField)、APIKey(SecureField)、Response Format(Picker ChatGPT|Claude)
  - S5.2 打开时以草稿副本载入现有配置；工具栏「取消」丢弃关闭、「保存」写 AIConfigStore 后关闭
  - S5.3 SettingsView 的 AI Section 行 → 弹出此 modal
- Verify: 编辑→取消不落盘；编辑→保存重开仍在；数据在 Application Support/AIConfig.json。

## Milestones
- M1 = S1–S3（存储基座 + 主题全局生效 + 设置页可用）
- M2 = S4–S5（语言占位 + 关于 + AI 配置编辑落盘）
