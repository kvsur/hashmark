# 源码 / 文本文件「打开方式」与高亮预览方案

> 目标：让本 App 能作为其它 App「分享 / 打开方式」的目标，接收任意常见源码/文本文件（如 `a.py`、`main.rs`、`config.yaml`），
> 预览时**自动用 Markdown 代码围栏包装并语法高亮**，编辑与保存**保持源文件原扩展名与原始内容**（不落成 `.md`）。
>
> 本文是设计与实施蓝图。落地时按「分阶段实施计划」推进，可同步进 `.work-planner/`。

---

## 1. 背景与目标

当前 App 只认 `.md` / `plain-text`：

- `Info.plist` 只注册了 `net.daringfireball.markdown` 与 `public.plain-text`（`MarkdownApp/Info.plist:14-18`），所以「打开方式」里只对 Markdown/纯文本出现本 App。
- `FileStore.contents(of:)` 只列出文件夹与 `.md` 文件，其它扩展名一律忽略（`FileStore.swift:55-57`、`visibleChildCount` 同理 `:88`）。
- 预览链路把文本**当作 Markdown 原样渲染**：`MarkdownPreviewView(markdown:)` → `WebPreviewView` → `template.html` 的 `marked.parse`（`template.html:32-41`）。源码文件直接丢进去不会高亮，反而会被 Markdown 语法误伤。

用户的核心想法（原话概括）：

1. 其它 App 里的 `a.py`，用「打开方式」选本 App 也能打开；预览时包装成
   ```` ```python ...源码... ``` ````
   借已有的 highlight.js 高亮。
2. 保存仍写回 `a.py`（保持原扩展名与原内容），下次再预览时再临时包装一次。

**结论：这个思路完全可行，且与现有架构高度契合**——预览层已内置 `marked + highlight.js`，我们只需在「读入的源码」和「喂给 marked 的字符串」之间加一层**按扩展名决定的包装**，再把系统类型注册、文件列表、导入几处打通即可。渲染引擎无需改。

---

## 2. 现状关键事实（落地前必须知道的约束）

| 事实 | 位置 | 对本方案的影响 |
|---|---|---|
| 只注册 md / plain-text 两种 UTI | `Info.plist:5-20` | 需扩展 `CFBundleDocumentTypes` 接受源码类型 |
| 无系统 UTI 的扩展名（`.rs/.go/.kt/.toml/.vue`…）系统不知其为文本 | 系统行为 | 需 `UTImportedTypeDeclarations` 绑定扩展名 → 声明其 conforms `public.source-code` |
| 文件列表只放 md | `FileStore.swift:55-57` | 需放开为「受支持文本类型」 |
| 导入已保留原扩展名 | `FileStore.importFile` `:159` | ✅ 无需改（无扩展名才兜底 md） |
| 预览把字符串当 md 渲染 | `template.html:32` | 需在**外层**包装围栏，模板本身不动 |
| 分享打开走 `onOpenURL` → 只读预览，不直接落盘 | `ContentView.swift:42-58` | 包装点要覆盖这条路径 |
| `readExternalText` 非 UTF-8 返回 nil | `FileStore.swift:201-205` | 天然过滤二进制文件（图片/PDF 打不开就忽略） |
| highlight.js 为「common」构建，已内置 34 种语言 | `highlight.min.js`（已探测） | 决定「能高亮」的白名单，未内置的走降级 |
| 编辑器已是等宽 `Theme.mono()` | `EditorView.swift:18-20` | 源码编辑体验基本可用，仅需微调 |
| `DocumentNode.Kind` 仅 `folder/markdown` | `DocumentNode.swift:12-15` | 需扩展以表达「源码/文本」 |

### 2.1 highlight.js 当前已内置语言（白名单，直接可高亮）

```
bash  c  cpp  csharp  css  diff  go  graphql  ini  java  javascript  json
kotlin  less  lua  makefile  markdown  objectivec  perl  php  plaintext
python  r  ruby  rust  scss  shell  sql  swift  typescript  vbnet  wasm  xml  yaml
```

覆盖了绝大多数主流语言（含 Swift/Rust/Kotlin/Go/TS）。**未内置**的常见语言：`dart`、`scala`、`toml`（可退化到 `ini`）、`html`（用 `xml`）、`dockerfile`、`powershell`、`elixir`、`haskell`、`zig`、`solidity` 等——这些走「降级策略」（见 4.1）。

---

## 3. 核心思路（一句话）

> **在「文件的原始文本」与「marked 渲染」之间，插入一个由扩展名决定的纯函数包装层。**
> 磁盘上永远是原文件；预览是临时视图。识别、包装、类型注册三件事各自收敛到一处，业务层只调用统一 API。

数据流：

```
其它 App 分享 a.py
      │  onOpenURL / 文件浏览打开
      ▼
读入原始文本 (FileStore, 不改)
      │
      ▼
SourceLanguage.of(url)  ──► 得到语言(python / 未知)
      │
      ▼
SourcePreviewWrapper.wrap(text, language)   ← 唯一包装点(DRY)
      │  产出 "```python\n{text}\n```" 或原样(md/txt)
      ▼
MarkdownPreviewView(markdown:) → 现有 marked+hljs 渲染 (不改)
```

保存：`EditorView` 编辑的始终是**原始文本**，`FileStore.writeText` 写回**原 URL**（原扩展名），与包装完全解耦。

---

## 4. 详细设计

### 4.1 语言识别与映射（新增 `Models/SourceLanguage.swift`）

一个纯数据模型 + 注册表，负责「扩展名 → 高亮语言标识 / 显示名 / 图标 / 是否可高亮」。这是本方案的**单一事实源**，Info.plist 想支持哪些扩展名、预览用什么围栏语言，都以它为准。

```swift
/// 一种可被本 App 识别为“源码/文本”的文件类型。
/// 单一职责：把“扩展名”映射到“高亮语言标识 + 展示信息”。
struct SourceLanguage: Hashable {
    let displayName: String        // 展示名，如 "Python"
    let hljsId: String             // 交给 highlight.js 的围栏语言标识，如 "python"
    let extensions: [String]       // 关联扩展名（小写，不含点），如 ["py", "pyi"]
    let systemImage: String        // 列表图标（SF Symbol）

    /// highlight.js 当前构建是否内置该语言（决定能否真正上色）。
    var isHighlightable: Bool { SourceLanguage.bundledHLJS.contains(hljsId) }
}

extension SourceLanguage {
    /// 与 Resources/WebPreview/highlight.min.js 的 common 构建保持同步。
    static let bundledHLJS: Set<String> = [
        "bash","c","cpp","csharp","css","diff","go","graphql","ini","java",
        "javascript","json","kotlin","less","lua","makefile","markdown",
        "objectivec","perl","php","plaintext","python","r","ruby","rust",
        "scss","shell","sql","swift","typescript","vbnet","xml","yaml"
    ]

    /// 全部登记的语言（映射表见附录 A）。
    static let all: [SourceLanguage] = [ /* … 见附录 A … */ ]

    /// 扩展名 → 语言（O(1) 查表，小写归一）。
    private static let byExtension: [String: SourceLanguage] = {
        var map: [String: SourceLanguage] = [:]
        for lang in all { for ext in lang.extensions { map[ext] = lang } }
        return map
    }()

    /// 依 URL 扩展名识别；识别不到返回 nil（交给上层按“纯文本/未知”处理）。
    static func of(_ url: URL) -> SourceLanguage? {
        byExtension[url.pathExtension.lowercased()]
    }
}
```

**降级策略（关键）**：

- 扩展名在表内且 `isHighlightable == true` → 用 `hljsId` 围栏，正常高亮。
- 扩展名在表内但**未内置**（如 `dart`）→ 两个选择，二选一（推荐 A）：
  - **A（推荐，零风险）**：围栏用该 `hljsId`，highlight.js 认不出时**自动退化为无高亮的等宽代码块**（hljs 对未知语言不报错，只是不上色）。文本仍以代码块正确呈现（保留缩进/换行）。
  - **B（更好看，成本高）**：把这些语言补进 highlight.js 构建（换用含更多语言的 build 或 `registerLanguage`），体积增加。可作为二期优化。
- 扩展名不在表内（陌生扩展）但内容是文本 → 用 `plaintext` 围栏（等宽、无高亮），仍比当 Markdown 渲染安全。
- `.md` / `.markdown` / `.txt` → **不包装**，按现有 Markdown 渲染（见 4.2 的分流）。

> 备注：`toml → ini`、`html → xml`、`yml → yaml`、`sh/zsh/bash → bash` 之类「近似映射」直接在附录 A 的表里用对应 `hljsId` 表达，业务层无感。

### 4.2 预览包装器（新增 `Models/SourcePreview.swift`）

唯一的包装函数。DocumentView、ReadOnlyPreviewView、（未来）分享等全部调它，绝不各写一遍。

```swift
enum SourcePreview {
    /// 把“某个文件的原始文本”转换为“可交给 MarkdownPreviewView 渲染的字符串”。
    /// - md/markdown/txt：原样返回（继续走 Markdown 渲染）。
    /// - 其它：包装成带语言标识的代码围栏，交给 highlight.js。
    static func markdown(for text: String, url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        // Markdown / 纯文本：保持既有行为，直接渲染。
        if ext == "md" || ext == "markdown" || ext == "txt" || ext.isEmpty {
            return text
        }
        let hljsId = SourceLanguage.of(url)?.hljsId ?? "plaintext"
        let fence = String(repeating: "`", count: fenceLength(for: text))
        // 语言标识紧跟开栏；结尾换行后闭栏，避免最后一行与闭栏粘连。
        return "\(fence)\(hljsId)\n\(text)\n\(fence)"
    }

    /// 动态围栏长度：至少 3 个反引号，且必须比正文中最长的连续反引号串更长，
    /// 否则文件内出现的 ``` 会提前闭合我们的代码块（健壮性关键）。
    private static func fenceLength(for text: String) -> Int {
        var longest = 0, run = 0
        for ch in text {
            if ch == "`" { run += 1; longest = max(longest, run) }
            else { run = 0 }
        }
        return max(3, longest + 1)
    }
}
```

要点：

- **动态围栏长度**避免源码内含 ``` （如 Python docstring、shell heredoc 里写文档）时提前闭合。
- 模板 `template.html` **完全不改**——它已经会对 `pre code.language-xxx` 调 `hljs.highlightElement`（`template.html:36-38`）。
- `.txt` 归为「按 Markdown 渲染」是延续现状；若日后希望 `.txt` 保留原始空白，可改为 `plaintext` 围栏，此处是唯一开关。

### 4.3 系统类型注册（改 `MarkdownApp/Info.plist`）

目标：让本 App 出现在源码/文本文件的「打开方式 / 分享」里，但**不要贪心接收二进制**（图片/PDF 等），以免 UX 混乱与审核风险。

分两块：

**(a) `CFBundleDocumentTypes` 增加一个「源码/文本」文档类型**（角色 Editor，Rank 用 `Alternate`——我们不是这些类型的属主）：

```xml
<dict>
    <key>CFBundleTypeName</key>
    <string>Source or Text File</string>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>LSHandlerRank</key>
    <string>Alternate</string>
    <key>LSItemContentTypes</key>
    <array>
        <string>public.source-code</string>   <!-- 覆盖系统已知的各种源码：.c/.swift/.py/.js/.json/.sh… -->
        <string>public.text</string>          <!-- 覆盖纯文本上位类型 -->
        <string>com.hashmark.source</string>  <!-- 我们导入声明的“通配源码类型”，覆盖系统不认识的扩展名 -->
    </array>
</dict>
```

> `public.source-code` 是系统源码类型的上位 UTI（`.c/.swift/.py/.js/.json/.php/.rb/.pl/.sh` 等系统已知类型都 conform 它），一条就吃下一大片。

**(b) `UTImportedTypeDeclarations` 为「系统不认识的扩展名」补声明**，让 OS 知道它们是源码文本，从而把本 App 列进「打开方式」。用一个自定义通配类型 `com.hashmark.source` 承载这些扩展名：

```xml
<dict>
    <key>UTTypeIdentifier</key>
    <string>com.hashmark.source</string>
    <key>UTTypeDescription</key>
    <string>Source Code</string>
    <key>UTTypeConformsTo</key>
    <array>
        <string>public.source-code</string>   <!-- 从而也 conform public.plain-text / public.text -->
    </array>
    <key>UTTypeTagSpecification</key>
    <dict>
        <key>public.filename-extension</key>
        <array>
            <!-- 只列“系统通常不认识、但我们想支持”的扩展名，避免与系统类型抢注 -->
            <string>rs</string><string>go</string><string>kt</string><string>kts</string>
            <string>ts</string><string>tsx</string><string>jsx</string>
            <string>toml</string><string>yaml</string><string>yml</string>
            <string>dart</string><string>scala</string><string>vue</string><string>svelte</string>
            <string>zig</string><string>sol</string><string>ex</string><string>exs</string>
            <string>lua</string><string>ini</string><string>gradle</string>
        </array>
    </dict>
</dict>
```

**取舍说明**：

- **不接收 `public.data`**（会把所有文件——含图片/视频——都拉进「打开方式」），刻意只到 `public.text`/`public.source-code`，UX 干净、审核稳妥。
- `com.hashmark.source` 用「导入声明（Imported）」而非「导出声明（Exported）」，因为我们不是这些类型的定义者，只是声明本 App 能识别；不与系统/他人的 UTI 冲突。
- 该扩展名清单应与附录 A 的 `SourceLanguage.all` **保持一致**（同一份事实的两处投影）。落地时在 PR 描述里点明「改表要同时改 Info.plist」，或后续做个脚本从表生成。

### 4.4 `FileStore` 与 `DocumentNode` 改造

**DocumentNode（`DocumentNode.swift`）**：`Kind` 增加一档，图标随语言走。

```swift
enum Kind { case folder, markdown, source }   // 新增 source

// systemImage：源码用代码类图标（SF Symbol，禁 emoji，遵 CLAUDE.md）
var systemImage: String {
    switch kind {
    case .folder:   return "folder.fill"
    case .markdown: return "doc.text"
    case .source:   return "chevron.left.forwardslash.chevron.right"  // 或按语言细化
    }
}

// displayName：源码文件“保留扩展名”更利于辨识（a.py 显示 a.py，而非 a）
var displayName: String {
    switch kind {
    case .folder:   return name
    case .markdown: return url.deletingPathExtension().lastPathComponent
    case .source:   return name   // 源码保留 .py 后缀，避免同名歧义
    }
}
```

**FileStore（`FileStore.swift`）**：把「只放 md」放宽为「放 md + 受支持的文本/源码类型」。收敛出一个判定函数，`contents(of:)` 与 `visibleChildCount(of:)` 共用（DRY）。

```swift
/// 某文件是否应在浏览器中展示：md、txt，或已登记的源码语言。
func isSupportedDocument(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    if ext == markdownExtension || ext == "markdown" || ext == "txt" { return true }
    return SourceLanguage.of(url) != nil
}

/// 据扩展名给出节点类型。
private func kind(for url: URL, isDirectory: Bool) -> DocumentNode.Kind {
    if isDirectory { return .folder }
    let ext = url.pathExtension.lowercased()
    return (ext == markdownExtension || ext == "markdown" || ext == "txt") ? .markdown : .source
}
```

- `contents(of:)` 里 `:55-57` 的 `!= markdownExtension` 过滤，改为 `!isSupportedDocument(url)`；`kind:` 改用上面的 `kind(for:)`。
- `visibleChildCount(of:)` `:88` 同步改判定。
- `importFile` **无需改**：已保留原扩展名（`:159`），无扩展名才兜底 md——正合需求。

### 4.5 预览链路集成（三处包装点）

只有**一个**函数（`SourcePreview.markdown(for:url:)`）被调用，覆盖三条入口：

1. **应用内打开源码文件预览** —— `DocumentView.content`（`DocumentView.swift:154-162`）：
   ```swift
   case .preview:
       MarkdownPreviewView(markdown: SourcePreview.markdown(for: text, url: node.url),
                           handle: previewHandle)
   ```
   编辑态 `EditorView(text: $text)` 不变——编辑的仍是原始源码。切回预览再包装（正合「下次预览再包一次」的诉求）。

2. **其它 App 分享/打开方式传入** —— `ContentView.onOpenURL`（`ContentView.swift:42-49`）保持读原始文本，包装点下沉到 `ReadOnlyPreviewView`（保证 `ImportedDocument.markdown` 里存的是**原始内容**，导入时写回的也是原始内容）：
   ```swift
   // ReadOnlyPreviewView.body（ReadOnlyPreviewView.swift:34）
   MarkdownPreviewView(markdown: SourcePreview.markdown(for: markdown, url: sourceURL),
                       handle: previewHandle)
   ```
   `ReadOnlyPreviewView` 的属性名 `markdown` 语义已变（现在是「原始文本」），建议顺手改名为 `rawText` 以免误解（小重构）。

3. **导入落库后再从浏览器打开** —— 走的是路径 1（`DocumentView`），自动覆盖。

> 关键不变量：**「存原始、包装只发生在渲染前一刻」**。分享菜单里的「源文件 / 源内容」（`PreviewShareButton` 的 `.sourceFile/.sourceContent`）继续拿到 `text`（原始源码），符合预期——分享出去的 `a.py` 还是 `a.py`。

### 4.6 编辑器与保存

- `EditorView` 已用等宽字体、关自动纠错/大写（`EditorView.swift:18-24`），源码编辑基本可用。可选微调：源码文件禁用 smart quotes（避免把 `"` 变成 `"`）。若要更进一步（行号、缩进保持），属二期，接口不变（该文件注释已预留 UITextView 替换点 `:6-8`）。
- 保存：`DocumentView.save()` → `FileStore.writeText(text, to: node.url)`（`FileStore.swift:207`）写回**原 URL、原扩展名**，天然满足「保存仍是 a.py」。无需改动。

### 4.7 图标与文案（遵 CLAUDE.md：禁 emoji、优先 SF Symbols）

- 源码文件列表图标：`chevron.left.forwardslash.chevron.right`（或 `curlybraces`）。可选按语言细化（如 `.json` 用 `curlybraces`，`.sh` 用 `terminal`），但**先统一一个**，细化列二期。
- 空状态/提示文案不含 emoji；如需新增文案（如「不支持的文件类型」）用纯文字 + SF Symbol。

---

## 5. 边界与健壮性清单

| 场景 | 处理 |
|---|---|
| 源码里含 ``` 反引号串 | 动态围栏长度（4.2 `fenceLength`），比正文最长反引号串更长 |
| 二进制文件（图片/PDF）被「打开方式」传入 | `readExternalText` 非 UTF-8 返回 nil → `onOpenURL` 直接忽略（现状 `:43` 已如此），不弹空预览 |
| 非 UTF-8 文本编码（GBK/Latin1 等） | 现状只试 UTF-8。可选增强：失败后回退尝试 `.isoLatin1` / 系统猜测编码；否则忽略。列为可选项 |
| 无扩展名文件 | 归 `plaintext` 围栏（或 md 渲染）；导入时兜底 `.md`（现状 `:159`） |
| 扩展名大小写（`.PY` / `.Md`） | 全程 `.lowercased()` 归一（识别、判定、包装均已如此） |
| 未内置高亮的语言（dart/scala…） | 退化为无色等宽代码块（4.1 策略 A），不报错 |
| 陌生扩展但内容是文本 | `plaintext` 围栏，安全呈现 |
| 超大文件 | 与现有 Markdown 大文件同风险；预览为一次性 `innerHTML`。列为已知项，必要时二期限流/懒渲染 |
| 分享出去 | 「源文件/源内容」拿原始 `text`，导出仍是原扩展名内容 |

---

## 6. 分阶段实施计划

建议开一期 work-planner 计划，阶段划分：

**P1 · 语言模型与包装器（无 UI 变更，纯逻辑，可单测）**
- 新增 `Models/SourceLanguage.swift`（附录 A 映射表 + `bundledHLJS`）。
- 新增 `Models/SourcePreview.swift`（`markdown(for:url:)` + 动态围栏）。
- 单测：动态围栏、md 直通、未知扩展降级、含 ``` 的用例。

**P2 · 系统类型注册（可独立验证「打开方式」出现）**
- 改 `Info.plist`：`CFBundleDocumentTypes` 增源码/文本类型；`UTImportedTypeDeclarations` 增 `com.hashmark.source` + 扩展名清单。
- 真机/模拟器验证：从「文件」App / 其它 App 对 `.py/.rs/.yaml` 选「打开方式」，本 App 出现。

**P3 · 存储层放行（浏览器能看见、能导入源码文件）**
- `DocumentNode.Kind` 增 `source` + 图标/displayName。
- `FileStore`：`isSupportedDocument` + `kind(for:)`，改 `contents`/`visibleChildCount`。
- 验证：导入的 `a.py` 出现在浏览器，副标题/图标正确。

**P4 · 预览集成（真正高亮起来）**
- `DocumentView.content` 预览分支接 `SourcePreview`。
- `ReadOnlyPreviewView` 接 `SourcePreview`（并把 `markdown` 参数更名 `rawText`）。
- 验证：分享 `a.py` → 只读预览高亮；导入后从浏览器打开预览高亮；编辑改动保存回 `.py`。

**P5 · 打磨（可选）**
- 编辑器 smart quotes 关闭；源码图标按语言细化；`.txt` 渲染策略确认。
- 未内置语言的高亮补全（换 highlight.js 构建或 `registerLanguage`）——二期。

**P6 · 回归与验收**
- 跑第 7 节 QA 矩阵；确认对既有 md 流程零回归。

依赖顺序：P1 → (P2 ∥ P3) → P4 → P5/P6。P2 与 P3 可并行。

---

## 7. QA / 验收矩阵

| 用例 | 期望 |
|---|---|
| 其它 App 分享 `a.py` → 选本 App | 弹只读预览，`python` 高亮，代码保留缩进 |
| 只读预览点「导入」到某目录 | 落库为 `a.py`（非 .md），浏览器可见、图标为源码图标 |
| 浏览器打开已导入 `a.py` → 预览 | 高亮正确；切「编辑」看到原始源码；改一行切回预览仍高亮；退出后磁盘是改后的 `.py` |
| 打开 `main.rs` / `app.kt` / `config.yaml` | 分别按 rust/kotlin/yaml 高亮 |
| 打开 `x.dart`（未内置） | 呈现为无色等宽代码块，不崩、不误当 Markdown |
| 打开含 ``` 的脚本 | 代码块不被提前闭合 |
| 分享/打开一张图片给本 App | 被忽略（不弹空预览） |
| 打开既有 `.md` | 行为与现在完全一致（无回归） |
| 分享菜单「源文件 / 源内容」 | 得到原始源码 / 原扩展名文件 |
| `.PY`（大写扩展名） | 与 `.py` 同等识别 |

---

## 8. 风险与取舍

- **审核/UX 面**：刻意不接 `public.data`，只到 `public.text`/`public.source-code`，避免抢注二进制类型。风险低。
- **两处清单同步**：`SourceLanguage.all` 与 Info.plist 扩展名列表是「同一事实的两处投影」，易漂移。缓解：PR 检查项写明「改一处必改另一处」，或后续用脚本从模型生成 plist 片段。
- **未内置语言高亮**：策略 A 下体验是「有代码块无颜色」，可接受；追求满配色再上策略 B（体积/构建成本）。
- **编码**：仅 UTF-8。非 UTF-8 源码会被忽略，属已知限制，视反馈再补回退编码。
- **大文件**：与既有 Markdown 预览同风险，不因本方案变差；不在本期解决。

---

## 附录 A：扩展名 → 语言映射表（`SourceLanguage.all` 数据）

> `hljsId` 一栏标 `*` 者为 highlight.js 当前构建**未内置**，走降级（无色代码块）；其余可正常高亮。
> 近似映射：`toml→ini`、`html→xml`、`yml→yaml`、`sh/zsh→bash`。

| 显示名 | hljsId | 扩展名 |
|---|---|---|
| Python | python | py, pyi, pyw |
| JavaScript | javascript | js, mjs, cjs |
| TypeScript | typescript | ts, tsx |
| JSX | javascript | jsx |
| Swift | swift | swift |
| Java | java | java |
| Kotlin | kotlin | kt, kts |
| C | c | c, h |
| C++ | cpp | cpp, cc, cxx, hpp, hh |
| C# | csharp | cs |
| Objective-C | objectivec | m, mm |
| Go | go | go |
| Rust | rust | rs |
| Ruby | ruby | rb |
| PHP | php | php |
| Perl | perl | pl, pm |
| Lua | lua | lua |
| R | r | r |
| Shell | bash | sh, bash, zsh |
| SQL | sql | sql |
| JSON | json | json |
| YAML | yaml | yaml, yml |
| TOML | ini | toml |
| INI | ini | ini, cfg, conf |
| XML | xml | xml, plist |
| HTML | xml | html, htm |
| CSS | css | css |
| SCSS/Sass | scss | scss, sass |
| Less | less | less |
| Markdown | markdown | md, markdown |
| Diff/Patch | diff | diff, patch |
| Makefile | makefile | mk |
| GraphQL | graphql | graphql, gql |
| VB.NET | vbnet | vb |
| Dart | dart* | dart |
| Scala | scala* | scala |
| Vue | xml* | vue |
| Svelte | xml* | svelte |
| Zig | zig* | zig |
| Solidity | solidity* | sol |
| Elixir | elixir* | ex, exs |
| Gradle | groovy* | gradle |

> 表可按需增删；每次改动**同步更新 Info.plist 的扩展名清单**（见 4.3(b)）。

---

## 附录 B：涉及改动的文件一览

| 文件 | 动作 |
|---|---|
| `Models/SourceLanguage.swift` | 新增（映射表 + 内置语言集） |
| `Models/SourcePreview.swift` | 新增（包装器 + 动态围栏） |
| `MarkdownApp/Info.plist` | 改（文档类型 + 导入类型声明） |
| `Models/DocumentNode.swift` | 改（Kind 增 source、图标、displayName） |
| `Models/FileStore.swift` | 改（isSupportedDocument / kind(for:)、放行列表） |
| `Features/Document/DocumentView.swift` | 改（预览分支接 SourcePreview） |
| `Features/Import/ReadOnlyPreviewView.swift` | 改（接 SourcePreview，参数更名 rawText） |
| `Features/Editor/EditorView.swift` | 可选微调（smart quotes） |
| `Resources/WebPreview/template.html` | **不改**（渲染引擎复用） |
| `Features/Preview/*` | **不改**（复用 MarkdownPreviewView） |
