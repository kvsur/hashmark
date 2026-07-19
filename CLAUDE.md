# CLAUDE.md — 项目工程约定

本文件是本仓库的长期工程约定，供 Claude Code 与协作者在写代码时共同遵循。
项目详细计划见 `.work-planner/`（`summary.md` 目标 / `plan.md` 蓝图 / `state.json` 进度）。

## 项目一句话

原生 SwiftUI 的 iOS/iPadOS Markdown 预览与编辑 App（最低 iOS 18，液态玻璃在 iOS 26+ 启用，计划上架 App Store）。

## 核心原则：独立拆分、可复用封装 🧩

> 语言/平台会变，但「关注点分离、可复用抽象、不写重复逻辑」的原则不变。

无论用什么技术栈，都坚持以下约定：

1. **单一职责，一个文件只做一件事**
   一个 `View` / 类型 / 文件聚焦一个清晰职责。文件过大（经验阈值约 **200–300 行**）或一个视图里塞了多种关注点，就该拆分。

2. **重复即抽象（DRY）**
   同样的逻辑/视图在 **2 处以上**出现，就抽成可复用单元：
   - 复用 UI → 独立 `View` 或 `ViewModifier`（如 `GlassBackground`）
   - 复用逻辑 → 函数、`extension`、或独立的服务类型（如 `FileStore`）
   - 复用常量 → 集中到设计常量/配置（如 `Theme`）

3. **按功能分层的目录结构（feature-based）**
   已确立的分层，新代码按此归位，不要一股脑堆在一个文件里：
   ```
   MarkdownApp/MarkdownApp/
   ├── App/            # 入口、生命周期、URL 接入
   ├── Models/         # 数据模型与存储服务（FileStore、DocumentNode…）
   ├── Features/       # 各功能模块：Browser / Preview / Editor / Import
   ├── DesignSystem/   # 可复用的视觉与设计基座（Theme、GlassBackground…）
   └── Resources/      # 本地 web 资源等静态资产
   ```

4. **视图轻量，逻辑外移**
   `View` 只负责「怎么显示」；数据加载、文件读写、转换等逻辑放到 Model / 服务层，别把业务逻辑写进 `body`。

5. **可用性判断收敛到一处**
   涉及系统版本差异（如 iOS 26 液态玻璃）的 `if #available` 只在封装层写一次（如 `GlassBackground`），业务代码直接调用统一 API，不散落各处。

6. **命名清晰、注释解释「为什么」**
   命名自解释；注释解释意图与权衡，而非复述代码。面向学习者可保留少量「SwiftUI ↔ 前端」类比注释。

## 文案与图标规范 🚫🙂

- **禁止在 App 文案中使用 emoji**（列表项、标题、按钮、提示、空状态等一律不用 emoji 当文字或图标）。
- 需要图标时：**优先使用系统 SF Symbols**（`Image(systemName:)` / `Label(_:systemImage:)`）。
- 若 SF Symbols 不满足、需要自定义图标：**先与作者沟通**，由作者提供素材或共同确定方案，不要擅自用 emoji 顶替。

## 国际化（i18n）规范 🌐

- **改动任何 UI 文案或 AI prompt，都必须同步考虑 i18n 多语言**：新增或修改的用户可见字符串不要硬编码，走本地化资源（`Localizable.xcstrings` / `InfoPlist.xcstrings`），并补齐已支持的各语言（简中/英/繁中/日/韩/德/俄）。
- AI prompt 若随语言/区域变化，同样需要按语言维护，不要只留一份中文或英文。
- 提交前自查：是否有新文案漏了翻译键？各语言是否都已补齐？

## 落地检查（每次写/改代码前后自问）

- [ ] 这段逻辑/视图是否已在别处出现？能否复用或抽象？
- [ ] 这个文件是否在做多件事？是否该拆？
- [ ] 新文件是否放进了正确的功能目录？
- [ ] `body` 里是否混入了本该外移的业务逻辑？
- [ ] 版本/平台差异是否收敛在了封装层？

## 提交约定

- 提交信息用中文、说明「做了什么 + 为什么」。
- 提交前确保工作区仅包含有意义的改动（`.gitignore` 已排除 `xcuserdata`、`DerivedData` 等）。
