# Plan Summary

## Goal

把“先填文件名、再得到空文件”的新建流程改为低摩擦写作流程：用户在根目录或任意子目录点击“新建文稿”后，App 先用现有空名称兜底规则创建真实 Markdown 文件，再直接打开编辑态；文档页持续显示可编辑的文件名，留空时仍使用本地化 `Untitled`/“未命名”及自动编号规则。新文稿保存时若仍使用系统兜底名，且第一物理行是 H1–H3 ATX 标题，则自动以该标题文本命名。

## Scope

- In:
  - 根目录和任意子目录的新建 Markdown 文稿改为直接创建并进入编辑态。
  - 文档页在预览与编辑两态都显示可编辑的文件名，不显示 `.md` 扩展名。
  - 新建文稿仍使用兜底名时，从保存内容的第一物理行 H1–H3 ATX 标题推导名称。
  - 文件名留空、非法路径分隔符、同名冲突和原名未变化时统一由存储层处理。
  - 重命名后同步更新编辑草稿 URL、分享源文件、iCloud `NSFilePresenter` 与目录 revision。
  - 补齐七语言本地化检查、模型回归、构建和真机/模拟器交互验收。
- Out:
  - 文件夹新建流程不变，仍使用名称弹层。
  - 目录列表原有侧滑重命名保留。
  - AI 写作生成文稿、外部导入和普通点击既有文稿仍保持当前进入预览态的行为。
  - 不改变 Markdown 扩展名、目录结构、存储模式或 iCloud 迁移策略。

## Constraints / Coexistence

- 所有创建、写入和重命名继续只经过根级 `DocumentLibraryController` / `DocumentLibraryService`；iCloud 模式继续使用 `NSFileCoordinator`。
- 新文稿在导航发生前真实落盘；创建失败时留在目录页并显示现有错误提示，不进入伪编辑器。
- 新文稿名称输入初始为空，以已经落盘的实际兜底名作为 placeholder；不输入或清空后提交时保留/生成现有兜底名。
- 自动命名只依赖“本次手动新建且仍使用自动兜底名”的状态，不比较某一种语言的字面文件名；`Untitled 2`/“未命名 2”等冲突结果同样属于兜底名。
- 标题提取复用当前 ATX 解析语义，只检查第一物理行并只接受 H1、H2、H3；空首行、普通正文、H4–H6、Setext 标题或空标题均不触发。
- 保存顺序固定为先持久化正文、再尝试自动重命名；自动重命名失败时正文保留在原兜底文件中，并可在后续保存重试。
- 只有“新建文稿”自动进入编辑态并聚焦正文；既有文稿和 AI 生成文稿保持当前默认预览入口。
- 重命名不得覆盖同名文件，也不得因提交未变化的名称而错误追加编号。
- 改动任何用户可见文案时同步补齐简中、英文、繁中、日、韩、德、俄七种语言；优先复用现有本地化键。

## Definition of Done

1. 根目录与多级子目录点击“新建文稿”均无需名称弹层，成功创建后直接显示编辑器并聚焦正文。
2. 未输入名称时实际文件使用当前语言的 `Untitled`/“未命名”；发生冲突时按现有规则生成 ` 2`、` 3`，且不会空名或覆盖。
3. 文档页在 Preview/Edit 两态均能看到和编辑不含 `.md` 的文件名；回车或失焦提交，空名走兜底。
4. 新文稿仍为兜底名时，保存以 `#`、`##` 或 `###` 开头的第一物理行会自动取标题文本命名；不符合条件、已有显式名称或既有文稿均不自动改名。
5. 自动或手动重命名成功后正文继续保存到新 URL，分享、快速切换、外部移动通知和返回目录均指向新文件；失败时不丢正文或文件。
6. 文件夹新建、列表重命名、AI 生成、外部导入和既有文稿默认预览行为无回归。
7. 存储/草稿回归测试、Debug 构建以及 iPhone/iPad 关键交互验收通过，七语言无缺失键。

## Context & References

| id | Source | Location | What it's for |
|---|---|---|---|
| C1 | 用户的新建与文件名交互要求、创建时机决定 | `context/document-creation-editor-title-requirement-2026-09-05.md` | 全计划产品目标与验收依据 |
| C2 | 当前目录浏览与新建流程 | `MarkdownApp/MarkdownApp/Features/Browser/FileBrowserView.swift` | S2 移除文稿名称弹层并接入直达编辑器 |
| C3 | 当前应用导航栈 | `MarkdownApp/MarkdownApp/ContentView.swift` | S2 区分新文稿编辑入口与普通预览入口 |
| C4 | 当前文档容器与草稿状态 | `MarkdownApp/MarkdownApp/Features/Document/DocumentView.swift`、`MarkdownApp/MarkdownApp/Models/DocumentDraft.swift` | S2/S3 初始模式、标题编辑、保存和 URL 身份切换 |
| C5 | 文稿存储与 iCloud 协调入口 | `MarkdownApp/MarkdownApp/Models/FileStore.swift`、`MarkdownApp/MarkdownApp/Models/DocumentLibraryController.swift` | S1/S3 空名兜底、唯一命名、协调重命名与 revision |
| C6 | 打开文稿的 iCloud presenter | `MarkdownApp/MarkdownApp/Models/OpenDocumentPresenter.swift` | S3 重命名后的 presenter 生命周期与外部移动兼容 |
| C7 | 现有本地化资源 | `MarkdownApp/MarkdownApp/Resources/Localizable.xcstrings` | S3/S4 复用名称、错误和兜底文案并核对七语言 |
| C8 | 文稿存储与草稿回归套件 | `MarkdownApp/FileBrowserTests/FileStoreRegressionTests.swift`、`MarkdownApp/FileBrowserTests/DocumentBehaviorRegressionTests.swift` | S1/S4 锁定命名与 URL 切换行为 |
| C9 | 新文稿首行 H1–H3 自动命名要求与 ATX 复用决定 | `context/new-document-first-heading-auto-title-2026-09-05.md` | S1/S3/S4 的标题提取、触发边界与验收依据 |
| C10 | 文稿标题流程真实 iCloud smoke 阻断证据 | `context/document-title-icloud-smoke-block-2026-09-05.md` | S4.5 的已执行环境、失败原因与解锁条件 |
| C11 | Xcode 误选 build-only destination 的用户截图 | `context/image.png` | S4.5 真机连接诊断与解锁依据 |
| C12 | 真机已构建安装但因锁屏拒绝启动的日志 | `context/iphone-launch-locked-2026-09-05.md` | S4.5 当前阻断与下一次 smoke 启动条件 |

## Assumptions and Open Questions

| Item | Status | Why it matters | Resolution point |
|---|---|---|---|
| 新建文稿进入前立即落盘 | confirmed | 避免返回、闪退或导航状态造成未保存草稿丢失 | 用户已确认 |
| 文件名输入框位于文档内容顶部并在两种模式常驻 | assumed | 保留现有顶栏 Preview/Edit 分段控件，又让名称持续可见 | S3 真机布局验收 |
| 新建后正文自动聚焦，名称框不抢焦点 | assumed | 直接解决“先命名再写作”的摩擦 | S2 真机交互验收 |
| 名称以回车或失焦提交，不随每个字符改磁盘文件 | assumed | 避免 iCloud 上产生高频移动和竞态 | S3 回归与真机验收 |

## Key Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| 创建时机 | 导航前调用 `createMarkdown(named: "", in:)` | 复用现有兜底与协调写入，保证编辑器始终绑定真实 URL |
| 新建入口 | 只有手动“新建文稿”携带 `.edit` 初始模式 | 不改变普通打开与 AI 生成的预览体验 |
| 名称显示 | 编辑 basename，隐藏并保留 `.md` | 与目录列表的 `displayName` 语义一致 |
| 重命名真相源 | 存储层决定清理、兜底、冲突编号和 no-op | 浏览器与编辑器共享同一行为，避免 UI 重复规则 |
| 自动标题解析 | 抽取并复用现有 ATX 单行解析语义，自动命名仅接受第一物理行 H1–H3 | 防止大纲与自动命名形成两套 Markdown 规则 |
| 自动命名资格 | 仅本次手动新建、尚未提交非空名称且仍持有兜底名的文稿；留空不取消资格 | 避免误改既有文件，同时让未填写名称时可按首行标题命名 |
| 自动命名时序 | 正文写入成功后再重命名，成功一次后关闭自动命名资格 | 确保失败不丢内容，也不随标题修改反复移动文件 |
