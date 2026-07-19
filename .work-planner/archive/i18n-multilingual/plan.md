# Plan — 多语言 i18n 落地

## Target architecture

```
MarkdownApp/MarkdownApp/
├── Models/
│   ├── LanguagePreference.swift     # 新增：语言偏好枚举（.system + 7 种显式），照 ThemePreference 形状
│   ├── SettingsStore.swift          # 扩展：新增 language 属性，写入即落盘（其注释已预告此扩展）
│   └── AIAction.swift / AITool.swift # 改造：prompt 英文骨架化 + 语言指令注入
├── DesignSystem/
│   ├── LocalizationController.swift # 新增：locale 解析 + 取词拦截（Bundle.main 主体类替换）的唯一收敛点
│   │                                # （与 InterfaceStyleController 并列——同为「偏好 → 全局生效」的封装层）
│   └── LanguageRebuild.swift        # 新增：.rebuildsOnLanguageChange() —— 每个 NavigationStack 必加
├── Features/Settings/
│   └── LanguagePickerSheet.swift    # 新增：替换 SettingsView 里的 LanguagePlaceholderSheet
├── Models/AIPromptLocale.swift      # 新增：注入给模型的区域上下文（语言码 + 国家码 + 语言指令）
└── Resources/
    └── Localizable.xcstrings        # 新增：唯一 String Catalog，7 种语言
```

**关键收敛点**（对应 CLAUDE.md「可用性判断/差异收敛到一处」）：
- 「当前该用哪个语言」只有 `LocalizationController` 一个答案来源；取词经 `Bundle.main` 主体类拦截统一导向选定语言包。
- 「语言解析优先级链」（偏好 → 系统 → en）只实现一次，不散落。

**S1.2 实测确立的三条硬规则**（写 S3/S4 代码时必须遵守，来由见 summary.md 的 Assumptions）：
1. **取词分两条路，各有入口**：`Text("Key")` / `navigationTitle("Key")` 等 LocalizedStringKey 照最自然的写法写（Bundle 主体类拦截已在底层解决）；
   但**需要 `String` 的地方必须走 `LocalizationController.string("Key")`** —— Foundation 的 `String(localized:)` 不经过 `Bundle.localizedString(forKey:value:table:)`，
   绕开拦截、只认系统语言。**危险在于它在「系统语言 == 偏好语言」时表现正常**，只有 App 内切到不同语言才暴露（首页标题曾因此恒显中文）。
2. **绝不用 `String(localized:locale:)` 传 locale 来切语言**——该参数只影响复数与数字格式，不选语言包，实测无效。
3. **每个 `NavigationStack` 必须加 `.rebuildsOnLanguageChange()`**，否则其 `navigationTitle` 在切换语言后静默停留在旧语言（`Text` 会自己更新而它不会，最易漏检）。

## Dependency graph

```
S1 ──┬──> S2 ──────────────┐
     ├──> S3 ──┬──> S7 ──> S8
     ├──> S4 ──┘           │
     └──> S5 ──> S6 ───────┘
```

S2 / S3 / S4 / S5 之间无依赖路径，可并行推进。S3 与 S4 都必须完成后才开 S7（键齐了才好一次性翻译）。

## Phases / Steps

### S1 — 本地化基建与生效机制验证
- Goal: 有一个能跑通的最小闭环——两三个字符串走 `.xcstrings`，切换偏好后**免重启**变化；并且明确 Model 层字符串该怎么写。
- Depends on: none
- Refs: C1（优先级链）、C2/C3（要匹配的既有模式）、C5（免重启生效的既有范例）
- Resolves: 「SwiftUI Text 能否随 environment locale 即时重解析」「Model 层 String(localized:) 不读 environment」两个 open question
- Sub-steps:
  - S1.1 建 `Localizable.xcstrings`；`knownRegions` 加齐 7 种；确认 `developmentRegion = en` 保持不变
  - S1.2 **Spike（先做，它决定后面所有调用点的写法）**：验证 `.environment(\.locale, resolved)` 能否让 `Text` 即时切换语言。同时验证 Model 层 `String(localized:locale:)` 显式传 locale 的效果。若 environment 方案不成立 → 记录到 `failures`，改用 Bundle 主体类 swizzle 方案并**回来更新本步的架构描述**再往下走
  - S1.3 写 `LanguagePreference`（`.system` + 7 种；`label` 用可本地化类型而非 `String`——注意 `ThemePreference.label` 目前是硬编码中文，是 S4 的活）
  - S1.4 `SettingsStore` 加 `language` 属性（key `settings.language`，与 `settings.theme` 同风格），写入即落盘
  - S1.5 写 `LocalizationController`：实现优先级链（偏好 → 系统首个受支持 → en），暴露 resolved locale；在 `ContentView` 挂上 environment 注入（参照 ContentView.swift:64 主题的 `onChange(initial: true)` 写法）
- Verify: 临时把设置页某两个字符串接入 catalog，代码里切换 `settings.language` 到 de，**不重启**即变德语；清空偏好 + 设备系统语言设为法语时显示英文。

### S2 — 语言切换 UI
- Goal: 设置页「切换语言」点开是真实可用的选择器，不再是占位。
- Depends on: S1
- Refs: C4（要替换的 `LanguagePlaceholderSheet`，SettingsView.swift:96–116）
- Sub-steps:
  - S2.1 写 `LanguagePickerSheet`：列出「跟随系统」+ 7 种语言，**每种语言用其自身语言书写**（Deutsch 而非「德语」——用户看不懂当前语言时才需要切换，这是切换器的存在意义），当前项打勾
  - S2.2 接进 `SettingsView.sheetContent` 的 `.language` 分支，删除 `LanguagePlaceholderSheet`
  - S2.3 确认与系统 per-app 语言设置的关系：App 内偏好优先，且不打架
- Verify: 设置页切换任一语言，sheet 内与其后的整个 App 立即变为该语言；重启 App 后偏好仍在。

### S3 — Features 层文案迁移
- Goal: `Features/` 下全部面向用户文案进入 catalog（英文为基准值）。
- Depends on: S1
- Refs: C1
- Sub-steps:
  - S3.1 Browser + Switcher（`FileBrowserView` 22 处——最大单点、`NameInputSheet`、`DocumentSwitcherSheet`）
  - S3.2 AI 相关视图（`AIWritingView` 13 处、`AIClarifyCard`、`AIConfigGate`、`AIRefineBar`、`HomeAIButton`、`AIActionPopover`）
  - S3.3 Settings（`SettingsView` 12 处、`AIConfigEditorView` 9 处、`AboutView`）
  - S3.4 Import + Preview + Document + Editor（`DirectoryPicker`、`ImportPreviewButton`、`ImportTargetPicker`、`ReadOnlyPreviewView`、`PreviewShareButton`、`DocumentView`）
  - S3.5 复查带插值/复数的字符串（如「已导入 N 个文件」）——复数在 catalog 里配 plural variation，不要手拼字符串；ru 有 one/few/many 三型，是这里最容易翻车的点
  - S3.6 给 10 个 `NavigationStack` 逐个补 `.rebuildsOnLanguageChange()`（ContentView 与 SettingsView 已在 S1 加好，余 8 个：AIConfigEditorView、AboutView、NameInputSheet、DocumentSwitcherSheet、DirectoryPicker、AIWritingView、ReadOnlyPreviewView、SettingsView 内的语言占位层）
  - S3.7 清理 catalog 中被替换掉的旧中文 key（Xcode 会标为 stale）
- Verify: `grep -rE '"[^"]*[一-龥]' --include='*.swift' Features/` 只余注释命中；且切换语言后各页 `navigationTitle` 均跟随变化（不只是 Text）。

### S4 — Models 层文案迁移
- Goal: 模型/服务层持有的面向用户文案同样本地化，且**切换语言后立即生效**。
- 注意：S1.2 已证伪原方案（`String(localized:locale:)` 显式传 locale）。模型层一律走 `LocalizationController.string(_:)`——
  **不是** Foundation 的 `String(localized:)`（它绕过取词拦截，只认系统语言；详见上方硬规则 1）。
- Depends on: S1
- Refs: C2（`ThemePreference.label` 是硬编码中文的典型）、C1
- Sub-steps:
  - S4.1 `ThemePreference.label`（跟随系统/浅色/深色）改为可本地化
  - S4.2 `AIError` 的 `errorDescription`（6 处）——注意它会流到 `AIWritingSession.phase = .error(...)` 直接展示给用户
  - S4.3 `AIAction.label` / `systemImage` 旁的文案、`validationError` 的两条提示（含插值「当前文档没有内容，无法\(label)。」——插值 + 本地化的组合要当心语序，德语/日语语序与中文不同，别拼字符串，用带参数的 catalog 键）
  - S4.4 `DocumentNode`、`FileStore`、`AIWritingSession`（「AI 返回了无法识别的内容…」）、`ChatGPTClient` 的零散文案
- Verify: 切换语言后，主题 Picker 选项、AI 动作名、一条人为触发的 AI 错误提示均随之变化（而非停在旧语言）。

### S5 — AI prompt 英文骨架化 + 语言指令
- Goal: prompt 主体改为英文单份，末尾按 locale 注入语言指令。
- Depends on: S1（需要 resolved locale）
- Refs: C6（`AIAction` 全量 prompt）、C7（`ClarifyTool`）、C1（决策出处）
- Sub-steps:
  - S5.1 写 `AIPromptLocale`：由 `LocalizationController` 的 resolved locale 产出语言码，生成语言指令文本
  - S5.2 `outputContract` 译为英文。**注意保留其现有语义**：「与原文、用户输入保持同一种语言」这条不是要删，它正是「输出跟随文档语言」决策的载体，要译过去而非译掉。同样保留「不滥用 emoji」「避免 AI 腔」两条——它们呼应 CLAUDE.md 的文案约定
  - S5.3 四个 `role`（续写/润色/整理/自由创作）译为英文，保持现有角色设定的具体度，别译成空泛套话
  - S5.4 `refineMessages` 的 system + user 模板英文化
  - S5.5 `ClarifyTool.description` 与 schema 内各 `description` 英文化；**并在其中明确要求：提问用 UI 语言**（对应锁定决策里的双语义拆分——问题是界面文本，正文是内容）
  - S5.6 语言指令拼装进 `AIAction.messages()` 与 `refineMessages()` 的 system
- Verify: 德语 UI + 中文文档跑一次「自由创作」触发反问——**反问问题是德语，生成正文是中文**。四个动作 + refine 各跑一次不退化。

### S6 — system prompt 注入国家码与语言码
- Goal: 模型知道用户的语言与所处国家。
- Depends on: S5
- Refs: C8（`ClaudeClient` 的 system 装配点）、C1
- Sub-steps:
  - S6.1 `AIPromptLocale` 补出国家码——**取自 `Locale.current.region`（设备区域）而非语言偏好**（用户可能「UI 英文但人在德国」；从语言反推区域会推错）。区域缺失时优雅省略，不要注入空值或猜测
  - S6.2 注入进 system prompt，格式对模型明确（如 `User locale: language=de, region=DE`），并说明用途（日期/数字/单位/文化惯例的本地约定）
  - S6.3 确认 `ClaudeClient`（system 抽顶层字段）与 `ChatGPTClient`（system 留在 messages）**两条路径都带上**——两家装配方式不同，这是最容易只改一半的地方
- Verify: 抓一次实际请求体，Claude 与 ChatGPT 两个客户端的 system 内容里都能看到正确的语言码与国家码。

### S7 — 7 种语言翻译落地
- Goal: catalog 中 7 种语言全部译满，无缺译。
- Depends on: S3, S4
- Refs: C1（语言清单）
- Sub-steps:
  - S7.1 zh-Hans（从原中文回填——原文案是母语打磨过的，优先复用原句而非从英文回译）
  - S7.2 zh-Hant（由 zh-Hans 转换，但**过一遍用词差异**：软件/軟體、文件/檔案、设置/設定——直接简转繁会露馅）
  - S7.3 ja / ko
  - S7.4 de / ru（ru 注意复数三型；de 注意长词导致的按钮文字溢出）
  - S7.5 全语言复查：**无 emoji**（CLAUDE.md 硬约束，翻译同样适用）、占位符数量与顺序正确、术语一致（Markdown / AI 等专名不译）
- Verify: Xcode 中 catalog 7 种语言均无 stale / needs-review；无空值。

### S8 — 全语言验收
- Goal: 确认 DoD 全部达成。
- Depends on: S2, S6, S7
- Refs: C1
- Sub-steps:
  - S8.1 逐语言过一遍主要界面（首页/文档/编辑/AI/设置/关于），检查截断、换行、按钮溢出（德语与俄语最容易撑破）
  - S8.2 验证优先级链三条路径：有偏好 → 跟随系统 → 系统为法语时兜底英文
  - S8.3 AI 全动作 × 代表性语言组合抽测，重点是「UI 语言 ≠ 文档语言」的交叉场景
  - S8.4 逐条对照 summary.md 的 Definition of Done 六项
- Verify: DoD 六项全部通过。
