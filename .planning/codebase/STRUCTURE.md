# 代码库结构

**分析日期:** 2026-04-16

## 目录布局

```text
[project-root]/
├── lib/                    # Flutter 运行时代码
│   ├── app/                # 应用壳、主题、全局 Provider
│   ├── core/               # 核心模型、规则解析、抽取、查询、存储、OCR
│   ├── features/           # 面向页面和业务流的功能模块
│   ├── shared/             # 跨 feature 复用的小型 UI 组件
│   └── main.dart           # 程序入口
├── test/                   # 单元测试、服务测试、Widget 测试、迁移测试
├── docs/                   # 计划、架构草案、代码审查文档
├── android/                # Android 宿主工程
├── ios/                    # iOS 宿主工程
├── linux/                  # Linux 宿主工程
├── .planning/codebase/     # 代码库地图输出目录
└── .worktrees/             # 本地并行工作树，当前不纳入 git 追踪
```

## 目录职责

**`lib/app`：**
- 目的：放应用壳、主题和全局 UI 约定。
- 包含：`MaterialApp`、全局 `BlocProvider`、设计 token、通用表面组件和响应式扩展。
- 关键文件：`lib/app/app.dart`、`lib/app/design_system.dart`

**`lib/core/config`：**
- 目的：放跨平台配置入口和密钥读取逻辑。
- 包含：编译期环境变量封装。
- 关键文件：`lib/core/config/app_secrets.dart`

**`lib/core/models`：**
- 目的：放基础领域模型，而不是页面临时状态。
- 包含：笔记、笔记本、旧版条目模型。
- 关键文件：`lib/core/models/note.dart`、`lib/core/models/note_entry.dart`、`lib/core/models/notebook.dart`

**`lib/core/parser`：**
- 目的：放规则解析器和文本规则，不与页面直接耦合。
- 包含：金额提取、时间词解析、规则分类、从 OCR 文本到 `NoteEntry` 的转换。
- 关键文件：`lib/core/parser/entry_parser.dart`、`lib/core/parser/entry_text_rules.dart`、`lib/core/parser/expense_extractor.dart`

**`lib/core/extraction`：**
- 目的：放 AI 结构化抽取相关 schema、抽象接口、DeepSeek 适配和合并逻辑。
- 包含：`ExtractedEntry` schema、AI 服务、schema parser、规则与 AI 结果合并器、OCR 文本校对器。
- 关键文件：`lib/core/extraction/extraction_models.dart`、`lib/core/extraction/ai_extraction_service.dart`、`lib/core/extraction/extraction_orchestrator.dart`、`lib/core/extraction/deepseek_text_understanding_engine.dart`

**`lib/core/ocr`：**
- 目的：放 OCR 抽象和平台实现。
- 包含：`OcrEngine` 接口、ML Kit 实现、iOS OCR 适配工厂。
- 关键文件：`lib/core/ocr/ocr_engine.dart`、`lib/core/ocr/mlkit_ocr.dart`、`lib/core/ocr/vision_ocr.dart`

**`lib/core/query`：**
- 目的：放结构化查询模型和面向 `entries` 的统计/时间线服务。
- 包含：查询对象、查询结果读模型、金额统计、时间线分组。
- 关键文件：`lib/core/query/entry_query.dart`、`lib/core/query/entry_record.dart`、`lib/core/query/analytics_service.dart`、`lib/core/query/timeline_service.dart`

**`lib/core/storage`：**
- 目的：放 SQLite 和文件存储基础设施。
- 包含：数据库单例、迁移、结构化仓储、图片存储。
- 关键文件：`lib/core/storage/database_helper.dart`、`lib/core/storage/database_migrations.dart`、`lib/core/storage/entry_repository.dart`、`lib/core/storage/image_storage.dart`

**`lib/features/notelist`：**
- 目的：放首页列表、首页卡片和列表状态管理。
- 包含：列表 Screen、列表 Item、`NoteListBloc`。
- 关键文件：`lib/features/notelist/note_list_screen.dart`、`lib/features/notelist/note_list_item.dart`、`lib/features/notelist/bloc/note_list_bloc.dart`

**`lib/features/canvas`：**
- 目的：放画布编辑工作流，是当前最完整的 feature 模块。
- 包含：Screen、Toolbar、BLoC、服务、画布专用 widget、少量 feature 内模型。
- 关键文件：`lib/features/canvas/canvas_screen.dart`、`lib/features/canvas/canvas_toolbar.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`、`lib/features/canvas/services/canvas_save_service.dart`、`lib/features/canvas/widgets/canvas_painter.dart`

**`lib/features/notedetail`：**
- 目的：放笔记详情页和结构化结果展示逻辑。
- 包含：详情 Screen 和其内部私有展示组件。
- 关键文件：`lib/features/notedetail/note_detail_screen.dart`

**`lib/features/search`：**
- 目的：放全文搜索页。
- 包含：搜索 Screen 和建议/跳转卡片等页内私有组件。
- 关键文件：`lib/features/search/search_screen.dart`

**`lib/features/records`：**
- 目的：放结构化查询中心。
- 包含：财务、待办、健康三类聚合视图和页内指标卡。
- 关键文件：`lib/features/records/records_hub_screen.dart`

**`lib/shared/widgets`：**
- 目的：放跨 feature 可复用但又不足以上升到 design system 的小部件。
- 包含：旧版条目行、OCR 结果横幅。
- 关键文件：`lib/shared/widgets/entry_row.dart`、`lib/shared/widgets/ocr_result_banner.dart`

**`test`：**
- 目的：按“运行时代码类型”划分测试，而不是严格镜像 `lib/`。
- 包含：`test/bloc/`、`test/parser/`、`test/extraction/`、`test/query/`、`test/services/`、`test/widgets/`、`test/storage/`
- 关键文件：`test/services/canvas_flow_contract_test.dart`、`test/storage/database_migrations_test.dart`、`test/widgets/canvas_screen_test.dart`

**`docs`：**
- 目的：存放计划、设计草案、评审和历史文档，不参与运行时。
- 包含：计划文档、结构化数据架构草案、代码审查记录。
- 关键文件：`docs/plans/2026-03-20-structured-data-ai-query-architecture.md`、`docs/superpowers/plans/2026-04-14-ai-first-refactor-implementation.md`

**`android` / `ios` / `linux`：**
- 目的：Flutter 平台宿主工程与平台级配置。
- 包含：Flutter 生成文件、平台清单和启动器。
- 关键文件：`android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`、`linux/runner/main.cc`

## 关键文件位置

**入口文件：**
- `lib/main.dart`：程序启动入口，负责预热数据库。
- `lib/app/app.dart`：应用根部，提供全局 `NoteListBloc` 和首页。
- `lib/features/notelist/note_list_screen.dart`：默认首页入口。

**配置文件：**
- `pubspec.yaml`：Flutter 依赖、平台插件和 SDK 约束。
- `analysis_options.yaml`：静态检查配置。
- `lib/core/config/app_secrets.dart`：`DEEPSEEK_API_KEY` 的编译期读取入口。
- `android/app/src/main/AndroidManifest.xml`：Android 权限与宿主配置。
- `ios/Runner/Info.plist`：iOS 平台配置。

**核心逻辑：**
- `lib/features/canvas/canvas_screen.dart`：画布工作流总编排。
- `lib/features/canvas/services/canvas_save_service.dart`：保存、双写和结构化抽取编排。
- `lib/core/storage/entry_repository.dart`：结构化条目和 AI 审计的主要持久化入口。
- `lib/core/extraction/extraction_orchestrator.dart`：规则和 AI 结果合并入口。
- `lib/core/query/analytics_service.dart`：财务与计数统计。
- `lib/core/query/timeline_service.dart`：待办和健康时间线分组。

**测试：**
- `test/bloc/note_list_bloc_test.dart`：首页列表状态流。
- `test/services/canvas_save_service_test.dart`：保存服务行为。
- `test/services/canvas_flow_contract_test.dart`：画布保存与加载契约。
- `test/storage/database_migrations_test.dart`：数据库迁移与表结构。
- `test/widgets/note_detail_screen_test.dart`、`test/widgets/search_screen_test.dart`：关键页面 Widget 测试。

## 命名约定

**文件：**
- 页面文件使用 `*_screen.dart`，例如 `lib/features/canvas/canvas_screen.dart`、`lib/features/records/records_hub_screen.dart`
- BLoC 文件使用 `*_bloc.dart`，并把 event/state 同放一文件，例如 `lib/features/notelist/bloc/note_list_bloc.dart`
- 服务文件使用 `*_service.dart`，例如 `lib/features/canvas/services/canvas_save_service.dart`
- 模型文件通常是单个名词或 `*_state.dart`，例如 `lib/core/models/note.dart`、`lib/features/canvas/models/canvas_editor_state.dart`
- 共享小部件使用语义化名词而不是抽象容器名，例如 `lib/shared/widgets/entry_row.dart`、`lib/shared/widgets/ocr_result_banner.dart`
- 测试文件统一使用 `*_test.dart`，并按运行时代码职责放到对应目录

**目录：**
- 页面功能遵循 feature-first，例如 `lib/features/canvas/`、`lib/features/notelist/`
- 核心能力遵循 layer-first，例如 `lib/core/storage/`、`lib/core/query/`、`lib/core/extraction/`
- feature 内部再细分为 `bloc/`、`services/`、`widgets/`、`models/`；当前最完整示例是 `lib/features/canvas/`

## 新代码放置规则

**新增功能页面：**
- 主代码：放到 `lib/features/<feature>/`
- 页面入口：使用 `lib/features/<feature>/<feature>_screen.dart`
- 页面私有组件：优先放到 `lib/features/<feature>/widgets/`
- 页面测试：放到 `test/widgets/`；如果是 feature 内服务，则放到 `test/services/` 或更窄的 `test/features/<feature>/services/`

**新增 BLoC 或页面状态：**
- 实现：放到 `lib/features/<feature>/bloc/<feature>_bloc.dart`
- 约定：沿用 `lib/features/notelist/bloc/note_list_bloc.dart` 的写法，把 event、state、bloc 收敛在同一个文件

**新增 feature 专属服务：**
- 实现：放到 `lib/features/<feature>/services/`
- 适用范围：只被单个 feature 使用的编排逻辑，沿用 `lib/features/canvas/services/canvas_save_service.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`

**新增核心领域能力：**
- 规则解析：放到 `lib/core/parser/`
- 结构化抽取或 AI adapter：放到 `lib/core/extraction/`
- OCR adapter：放到 `lib/core/ocr/`
- 查询模型与统计：放到 `lib/core/query/`
- 存储与仓储：放到 `lib/core/storage/`

**新增共享 UI：**
- 跨页面复用的小部件：放到 `lib/shared/widgets/`
- 全局主题、颜色、间距、表面组件：继续放到 `lib/app/design_system.dart`

**新增结构化查询能力：**
- 查询参数或读模型：放到 `lib/core/query/entry_query.dart` 同层的新文件
- 查询 SQL 与关系表访问：优先放到 `lib/core/storage/entry_repository.dart`，或在 `lib/core/storage/` 新增同类仓储文件
- 记录中心展示：放到 `lib/features/records/records_hub_screen.dart` 同层，除非已经形成新的独立 feature

## 特殊目录

**`.planning/codebase`：**
- 目的：存放 GSD 生成的代码库地图文档。
- 生成：是
- 提交：否（当前 `git ls-files` 未追踪此目录下文件）

**`.worktrees`：**
- 目的：存放本地并行工作树，例如 `.worktrees/ai-first-refactor/`
- 生成：否
- 提交：否（已在 `.gitignore` 忽略）

**`ios/Flutter`：**
- 目的：存放 Flutter iOS 侧生成配置，例如 `ios/Flutter/Generated.xcconfig`
- 生成：是
- 提交：是

**`linux/flutter`：**
- 目的：存放 Linux 桌面端生成的 Flutter glue code，例如 `linux/flutter/generated_plugin_registrant.cc`
- 生成：是
- 提交：是

---

*结构分析：2026-04-16*
