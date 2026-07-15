# Plan Summary — 多语言 i18n 落地

## Goal

**From**：App 无任何本地化资源（无 `.lproj` / `.strings` / `.xcstrings`，`developmentRegion = en` 但代码里 26 个文件共约 141 处中文硬编码字面量）；设置页「切换语言」是一个 `LanguagePlaceholderSheet` 占位，点开只说「后续版本提供」；AI prompt 全是中文长文本；system prompt 不含用户区域信息。

**To**：App 支持 7 种语言（zh-Hans / en / zh-Hant / ja / ko / de / ru）完整 UI 本地化；设置页可真正切换语言且**免重启即时生效**；语言解析遵循「用户存储偏好 → 系统语言 → 英文兜底」；AI prompt 改为英文骨架 + 按 locale 注入的语言指令；system prompt 携带用户的国家代码与语言代码。

**Why**：计划上架 App Store 面向多地区发行，中文硬编码是发行的硬阻塞；同时 AI 输出质量依赖模型知道用户所处区域与语言。

## Scope

- **In**：
  - String Catalog（`.xcstrings`）基建 + 7 种语言的 `knownRegions` 配置
  - `LanguagePreference` 模型 + `LocalizationStore` 服务（偏好持久化 + locale 解析 + 免重启生效）
  - 设置页语言切换真实 UI（替换占位 sheet）
  - Features 层与 Models 层全部面向用户文案的迁移与翻译
  - `AIAction` / `AITool` 的 prompt 英文骨架化 + 语言指令注入
  - system prompt 注入国家代码 + 语言代码
- **Out**：
  - `Resources/WebPreview/template.html`——已核查，其中文全是代码注释，无面向用户文案，**不动**
  - 代码注释与 `.work-planner/` 文档本身保持中文（工程约定，非产品文案）
  - App Store 商店页元数据（截图/描述）的多语言——属发行工作，不在本计划
  - 用户文档内容的翻译功能（这是产品功能，不是 i18n）
  - RTL 语言（本期 7 种均为 LTR，不做镜像布局）

## Constraints / Coexistence

- 最低 iOS 18，String Catalog（Xcode 15+）可用，无历史 `.strings` 包袱——一步到位用 `.xcstrings`。
- **免重启切换是硬要求**：需求写明「优先匹配用户切换存储的多语言」，若需重启才生效则该偏好形同虚设。这约束了整套 API 形态（见 S1 与 Open Questions）。
- 遵守 `CLAUDE.md`：单文件 200–300 行阈值、重复即抽象、版本差异收敛在封装层、**App 文案禁用 emoji**（翻译时同样适用，7 种语言的译文都不得引入 emoji）。
- 现有 `ThemePreference` 是「模型持有 UI 文案（`label`）」的既有模式，`LanguagePreference` 照此形状写以保持一致，但 `label` 需改为可本地化类型。
- 非中英的 5 种译文（ja/ko/de/ru）无母语者校对——这是已知质量风险，记录在 Assumptions。

## Definition of Done

1. 设置页切换 7 种语言中任意一种，**无需重启**，UI 文案立即整体切换（含已弹出的 sheet）。
2. 清空偏好后，设备系统语言为 7 种之一时跟随之；为第 8 种（如法语）时显示英文。
2b. **系统语言 ≠ App 内偏好时全屏一致**（如系统中文 + 偏好德语 → 界面全德语，无一处残留中文）。
    这一条是 S8 事后补的：原 DoD 的每一项在「系统语言 == 偏好语言」下都能通过，于是 `String(localized:)`
    绕过取词拦截的 bug 一路漏检到用户手上。多语言验收**必须**包含这个交叉组合，
    否则「App 内切语言」这条核心路径实际上从未被真正测试过。
3. `grep -rE '"[^"]*[一-龥]' --include='*.swift'` 在 Features/ 与 Models/ 下**不再命中任何面向用户的字面量**（仅余代码注释）。
4. `.xcstrings` 中 7 种语言均无 stale / needs-review 状态的键，无缺译。
5. AI 四个动作（续写/润色/整理/自由创作）+ refine 在中文文档 + 德语 UI 组合下：反问问题为德语，生成正文为中文。
6. 抓取一次实际请求体，确认 system prompt 含当前国家代码与语言代码。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 用户原始需求 + 澄清记录（聊天原文） | context/i18n-requirements.md | 需求判据；语言清单、优先级链、prompt 方案的出处 |
| C2 | 现有主题偏好模型 | MarkdownApp/MarkdownApp/Models/ThemePreference.swift | `LanguagePreference` 要匹配的既有模式（S1） |
| C3 | 现有偏好存储服务 | MarkdownApp/MarkdownApp/Models/SettingsStore.swift | 语言偏好持久化的落点；其注释已预告「待真正做多语言时在此扩展」（S1） |
| C4 | 设置页 + 语言占位 sheet | MarkdownApp/MarkdownApp/Features/Settings/SettingsView.swift | S2 要替换的占位实现（`LanguagePlaceholderSheet`，第 96–116 行） |
| C5 | 主题的免重启生效范例 | MarkdownApp/MarkdownApp/DesignSystem/InterfaceStyleController.swift + ContentView.swift:64 | 「偏好变更 → 窗口级即时生效」的既有做法，语言切换的参照（S1） |
| C6 | AI prompt 全量 | MarkdownApp/MarkdownApp/Models/AIAction.swift | 待英文骨架化的 role ×4 + outputContract + refineMessages（S5） |
| C7 | 反问工具定义 | MarkdownApp/MarkdownApp/Models/AITool.swift | ClarifyTool 的 description 与 schema 描述，同样是 prompt（S5） |
| C8 | system 字段装配点 | MarkdownApp/MarkdownApp/Models/ClaudeClient.swift:42–53 | system 被抽为顶层字段的位置；注入区域信息需在此之前完成（S6） |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| SwiftUI `Text` 能随 `.environment(\.locale)` 变更即时重解析 `.xcstrings` 中的 LocalizedStringKey | **confirmed（S1.2 实测）— 但只覆盖 Text 家族** | `Text`/`Section`/`Button` 成立；`navigationTitle` 不成立（走 UIKit 桥接，只认 `Locale.current`）。故 environment 单独不足以支撑 DoD #1，已改用取词拦截方案，见 Key Decisions | 已解决于 S1.2 |
| Model 层（`AIError`、`FileStore`、`AIAction.validationError`）的 `String(localized:)` 读 `Locale.current`，**不**读 SwiftUI environment | **confirmed，且原设想的解法已被证伪（S1.2 实测）** | 原计划「Model 层显式传 `String(localized:locale:)`」**行不通**：该 `locale` 参数只影响复数规则与数字格式，**不选择语言包**，实测传 de 仍返回系统语言的译文。改由取词拦截统一解决，模型层无需传参 | 已解决于 S1.2；S4 按新结论落实 |
| `navigationTitle` 换语言后不自动更新 | **confirmed（S1.2 实测）** | 它只在 body 重算时取一次词；`Text` 会自己重渲染而它不会，导致「按钮变了、标题卡在旧语言」。解法：每个 `NavigationStack` 加 `.rebuildsOnLanguageChange()` | 已解决于 S1.2；S3 需逐个补齐（10 个 NavigationStack） |
| `zh-Hant` 单一变体即可覆盖繁中用户 | assumed | 若需区分台湾/香港用词（软体 vs 軟件），语言数从 7 变 8 | S7 翻译时若分歧明显再提，本期先单变体 |
| ja/ko/de/ru 译文由模型产出、无母语者校对 | assumed | 上架后可能有文案质量投诉 | 记录为已知风险；S8 至少做长度溢出与占位符正确性检查 |
| 国家代码取自设备区域（`Locale.current.region`）而非语言偏好 | assumed | 用户可以「UI 用英文但人在德国」；取语言推区域会推错 | S6 实现时确认 |
| App 一旦有多个 `.lproj`，iOS 会自动在系统设置里给出 per-app「首选语言」 | assumed | 它与 App 内切换器是两个入口，需明确 App 内偏好优先，避免两者打架 | S2 实现时确认交互 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 语言清单 | zh-Hans、en、zh-Hant、ja、ko、de、ru（7 种） | 用户确认；原文「日德语」为「日语」笔误（C1） |
| 开发语言 / 兜底语言 | 源码字面量与 `.xcstrings` 基准为 **en**；兜底 en | 与既有 `developmentRegion = en` 一致；需求明确「系统语言不支持时兜底英文」 |
| 语言解析优先级 | 用户存储偏好 → 系统语言（取首个受支持项）→ en | 用户需求原文（C1） |
| 本地化载体 | String Catalog（`.xcstrings`），单一 catalog | iOS 18 起点无历史包袱；Xcode 可视化管理缺译状态，直接支撑 DoD #4 |
| 切换生效方式 | **免重启**，不用 `AppleLanguages` + 重启 | `AppleLanguages` 写入需重启才生效，与「App 内切换」体验相悖 |
| **取词机制**（S1.2 确定，S8 修正） | **替换 `Bundle.main` 主体类拦截取词** + 每个 `NavigationStack` 加 `.rebuildsOnLanguageChange()`；`.environment(\.locale)` 保留但仅作格式化与重渲染信号 | 实测三选一：① environment 单独用 → 只有 Text 家族生效，navigationTitle 与模型层静默停留旧语言；② `String(localized:locale:)` 显式传 locale → **无效**，该参数不选语言包；③ 取词拦截 → 覆盖全部 LocalizedStringKey 路径，业务代码照最自然的写法写。符合 CLAUDE.md「差异收敛到一处」 |
| **取词的两条路**（S8 用户实测后补充，**S1.2 原结论有误**） | ① LocalizedStringKey / `Text` / `navigationTitle` → 拦截自动覆盖；② 需要 `String` 的地方 → **必须** `LocalizationController.string(_:)` | S1.2 原判「拦截覆盖所有路径」是错的：Foundation 的 `String(localized:)` **不经过** `Bundle.localizedString(forKey:value:table:)`，绕开拦截、按系统语言取词。**此 bug 只在「系统语言 ≠ App 内偏好」时暴露**，而 S3 之后的验证全部用改系统语言的方式做，故一路漏检，直到用户发现首页标题恒为「文档」。14 处调用点已全部改为 `LocalizationController.string(_:)`（内部 `String(localized:bundle:)` 显式传语言包） |
| 重渲染粒度 | `.id(language)` 加在**每个 NavigationStack**，而非 App 根部 | 根部重建会把已弹出的 sheet 一并掀掉——而用户正是在设置页 sheet 里切语言的。加在 NavigationStack 上，实测 sheet 原地换语言、留在原处（DoD #1 的「含已弹出的 sheet」） |
| AI 输出语言 | **跟随文档 / 用户输入语言**，非 UI 语言 | 用户确认（C1）；写作类 App 中「UI 德语 → 中文文档被续写成德语」是明显错误行为 |
| AI prompt 组织 | **英文骨架 1 份 + 按 locale 注入语言指令**，非 7 套手写 | 用户确认（C1）；模型对英文指令遵循度高、token 省，改一句 outputContract 只需改 1 处 |
| 语言指令的**双语义**拆分 | 反问澄清问题 → **UI 语言**；生成正文 → **文档语言** | 「输出跟随文档语言」+「英文骨架 + 语言指令」两个决策叠加后的必然推论：ClarifyTool 的问题是说给用户听的界面文本，正文是内容。二者语言可不同（UI 德语 + 中文文档 = 德语提问、中文正文）。**已向用户点明，待其确认或纠正** |
| template.html | 不纳入本计划 | 已核查：其中文全为代码注释，无面向用户文案 |
