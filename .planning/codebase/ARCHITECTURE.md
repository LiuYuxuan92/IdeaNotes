# 架构

**分析日期:** 2026-04-16

## 模式概览

**整体：** 这是一个以 `lib/features/` 页面模块为外层、以局部 BLoC 和页面状态为协调层、以 `lib/core/` 领域服务为核心、以 `sqflite` 和本地文件系统为底座的 Flutter 本地优先架构；OCR、手写识别、语音转写和 DeepSeek 结构化抽取作为增强链路接入保存与预览流程。

**关键特征：**
- `lib/main.dart` 在 `runApp` 之前先初始化 `DatabaseHelper`，应用启动强依赖本地 SQLite。
- `lib/app/app.dart` 只注入全局 `NoteListBloc` 和主题，功能页之间通过 `Navigator.push` + `MaterialPageRoute` 直接跳转，没有集中式路由层。
- `lib/features/notelist/bloc/note_list_bloc.dart` 管理首页列表与全文搜索；`lib/features/canvas/bloc/canvas_bloc.dart` 只管理当前画布笔迹状态，状态边界按页面拆分。
- `lib/features/canvas/canvas_screen.dart` 是最重的业务编排点，直接协调 OCR、AI 预览、语音输入、保存、列表刷新和返回逻辑。
- 数据访问采用混合模式：`lib/core/storage/database_helper.dart` 直接负责 `notes`、`notebooks`、`note_entries`，`lib/core/storage/entry_repository.dart` 负责结构化 `entries`、关系表和 `ai_extractions`。
- 同一份识别文本在保存时会“双写”到旧表 `note_entries` 和新表 `entries`：旧表兼容旧 UI，`entries` 支撑 `lib/features/records/records_hub_screen.dart` 的结构化查询。
- 依赖注入方式以单例和显式构造参数为主，例如 `DatabaseHelper.instance`、`EntryRepository(databaseHelper: DatabaseHelper.instance)`、`CanvasSaveService(...)`；当前不存在统一 IoC 容器。

## 分层

**启动与应用壳层：**
- 目的：初始化数据库、挂载全局 Provider、统一 MaterialApp 与设计系统。
- 位置：`lib/main.dart`、`lib/app/app.dart`、`lib/app/design_system.dart`
- 包含：程序入口、全局 `NoteListBloc`、`MaterialApp`、主题 token、通用表面组件与响应式扩展。
- 依赖：`lib/core/storage/database_helper.dart`、`lib/features/notelist/bloc/note_list_bloc.dart`
- 被使用方：所有 `lib/features/` 页面和 `lib/shared/widgets/` 组件

**功能页面层：**
- 目的：承接用户交互、页面布局、导航和页面级异步控制。
- 位置：`lib/features/notelist/note_list_screen.dart`、`lib/features/notedetail/note_detail_screen.dart`、`lib/features/canvas/canvas_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/records/records_hub_screen.dart`
- 包含：Screen、页面内部私有组件、`FutureBuilder`、`SnackBar`、弹窗与底部抽屉。
- 依赖：`lib/app/design_system.dart`、对应 feature 的 bloc/service、`lib/core/models/`、`lib/core/query/`、`lib/core/storage/`
- 被使用方：由 `lib/app/app.dart` 作为首页挂载，或由其它页面通过 `Navigator.push` 进入

**局部状态层：**
- 目的：把页面内的可变状态与事件转换逻辑收敛到独立对象，避免 UI 直接改写模型。
- 位置：`lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`
- 包含：Event、State、状态转换、过滤逻辑、撤销/重做逻辑。
- 依赖：`flutter_bloc`、`equatable`，以及 `lib/core/storage/database_helper.dart`（仅 `NoteListBloc`）
- 被使用方：`lib/app/app.dart`、`lib/features/notelist/note_list_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/canvas/canvas_screen.dart`、`lib/features/canvas/canvas_toolbar.dart`

**功能服务层：**
- 目的：把重业务流程从页面中拆出为 feature 内服务，尤其是保存、预览、语音和 OCR 相关流程。
- 位置：`lib/features/canvas/services/canvas_save_service.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/features/canvas/services/canvas_load_service.dart`、`lib/features/canvas/services/canvas_ocr_service.dart`、`lib/features/canvas/services/handwriting_recognition_service.dart`、`lib/features/canvas/services/voice_recognition_service.dart`
- 包含：保存编排、AI 预览、测试友好的加载/OCR 封装、手写识别、语音识别适配。
- 依赖：`lib/core/extraction/`、`lib/core/parser/`、`lib/core/ocr/`、`lib/core/storage/`、`lib/core/models/`
- 被使用方：主要由 `lib/features/canvas/canvas_screen.dart` 调用；其中 `CanvasLoadService`、`CanvasOcrService` 目前更多出现在测试与契约流中，例如 `test/services/canvas_flow_contract_test.dart`

**核心领域与规则层：**
- 目的：定义笔记、条目、规则解析、结构化抽取 schema，以及与 OCR/AI 引擎对接的抽象接口。
- 位置：`lib/core/models/note.dart`、`lib/core/models/note_entry.dart`、`lib/core/parser/entry_parser.dart`、`lib/core/parser/entry_text_rules.dart`、`lib/core/extraction/extraction_models.dart`、`lib/core/extraction/extraction_orchestrator.dart`、`lib/core/extraction/ai_extraction_service.dart`、`lib/core/ocr/ocr_engine.dart`
- 包含：`Note`、`NoteEntry`、`EntryRecord` 对应的领域模型；规则解析；结构化文档 schema；OCR 和 AI 抽象接口。
- 依赖：标准 Dart/Flutter、`decimal`、`equatable`
- 被使用方：页面层、功能服务层、存储层与查询层

**查询与分析层：**
- 目的：围绕结构化 `entries` 提供过滤、时间线和统计视图。
- 位置：`lib/core/query/entry_query.dart`、`lib/core/query/entry_record.dart`、`lib/core/query/analytics_service.dart`、`lib/core/query/timeline_service.dart`
- 包含：不可变查询对象、查询结果读模型、金额聚合、按天时间线分组。
- 依赖：`lib/core/storage/entry_repository.dart`
- 被使用方：`lib/features/records/records_hub_screen.dart`、`lib/features/notedetail/note_detail_screen.dart`

**存储与基础设施层：**
- 目的：封装 SQLite 表结构、迁移、图片持久化和结构化数据写入策略。
- 位置：`lib/core/storage/database_helper.dart`、`lib/core/storage/database_migrations.dart`、`lib/core/storage/entry_repository.dart`、`lib/core/storage/image_storage.dart`
- 包含：数据库单例、迁移脚本、结构化仓储、快照/缩略图文件存储。
- 依赖：`sqflite`、`path_provider`、`image`
- 被使用方：`lib/main.dart`、BLoC、页面层、功能服务层、查询层

**外部能力适配层：**
- 目的：把平台 OCR、手写识别和 DeepSeek API 隔离在明确接口之后。
- 位置：`lib/core/ocr/mlkit_ocr.dart`、`lib/core/ocr/vision_ocr.dart`、`lib/core/extraction/deepseek_text_understanding_engine.dart`、`lib/core/extraction/deepseek_ocr_text_correction_engine.dart`、`lib/core/config/app_secrets.dart`
- 包含：平台 OCR 实现、DeepSeek 结构化理解引擎、OCR 文本校对引擎、编译期 API Key 解析。
- 依赖：平台插件、HTTP、`DEEPSEEK_API_KEY`
- 被使用方：`lib/features/canvas/canvas_screen.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/features/canvas/services/canvas_save_service.dart`

## 数据流

**新建/编辑笔记并保存：**

1. `lib/features/notelist/note_list_screen.dart` 通过 `_createNewNote()` 或 `_createVoiceNote()` 打开 `lib/features/canvas/canvas_screen.dart`。
2. `lib/features/canvas/canvas_screen.dart` 内部创建 `CanvasBloc`，手写笔迹由 `lib/features/canvas/bloc/canvas_bloc.dart` 管理；语音输入通过 `lib/features/canvas/widgets/voice_capture_sheet.dart` 和 `lib/features/canvas/services/voice_recognition_service.dart` 写回 `_ocrResult`。
3. 用户点击识别时，`CanvasScreen._runOcr()` 先调用 `lib/features/canvas/services/handwriting_recognition_service.dart`，失败时回退到 `lib/core/ocr/ocr_engine.dart` 的平台实现。
4. 用户点击保存时，`CanvasScreen._saveNote()` 把当前画布和识别文本交给 `lib/features/canvas/services/canvas_save_service.dart`。
5. `CanvasSaveService` 先通过 `lib/core/storage/image_storage.dart` 保存快照与缩略图，再通过 `lib/core/storage/database_helper.dart` 插入或更新 `notes`。
6. `CanvasSaveService` 使用 `lib/core/parser/entry_parser.dart` 生成旧版 `NoteEntry`，回写 `note_entries` 表。
7. 同一保存流程继续调用 `lib/core/extraction/extraction_orchestrator.dart`，把规则结果与 DeepSeek 结果合并，再通过 `lib/core/storage/entry_repository.dart` 写入 `entries`、`entry_subjects`、`entry_tags`、`entry_links`、`ai_extractions`。
8. 保存成功后，`CanvasScreen` 触发全局 `NoteListBloc` 重新 `LoadNotes`，返回列表页后首页数据即刷新。

**笔记详情展示：**

1. `lib/features/notelist/note_list_screen.dart` 或 `lib/features/search/search_screen.dart` 打开 `lib/features/notedetail/note_detail_screen.dart`。
2. `NoteDetailScreen._loadNoteDetail()` 先从 `lib/core/storage/database_helper.dart` 读取最新 `notes` 记录，再通过 `lib/core/storage/image_storage.dart` 加载快照图片。
3. 如果存在识别文本，页面优先调用 `lib/core/storage/entry_repository.dart` 的 `queryEntriesForNote()` 获取结构化 `EntryRecord`。
4. 如果结构化表为空，则回退到 `note_entries` 或 `lib/core/parser/entry_parser.dart` 的即时解析结果。
5. 详情页因此同时兼容“旧版 `NoteEntry` 视图”和“新版 `EntryRecord` 视图”。

**记录中心结构化查询：**

1. `lib/features/records/records_hub_screen.dart` 根据当前标签页和时间范围构造 `lib/core/query/entry_query.dart`。
2. 财务页通过 `lib/core/query/analytics_service.dart` 聚合金额、分类和月份趋势。
3. 待办和健康页通过 `lib/core/query/timeline_service.dart` 按 `occurred_date` 分组成时间线。
4. 这条链路只依赖 `entries` 体系，不再读取旧版 `note_entries`。

**全文搜索：**

1. `lib/features/search/search_screen.dart` 不直接查结构化表，而是复用 `lib/features/notelist/bloc/note_list_bloc.dart` 的 `notes` 和 `filteredNotes`。
2. 搜索命中范围来自 `lib/core/models/note.dart` 的 `searchableText`，即识别文本和日期组合后的全文字段。

**状态管理：**
- 全局共享状态只有 `NoteListBloc`，由 `lib/app/app.dart` 放在应用根部，对列表页和搜索页生效。
- `CanvasBloc` 是 `CanvasScreen` 私有状态，只负责笔迹、工具、颜色、撤销/重做，不负责持久化。
- `lib/features/notedetail/note_detail_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/records/records_hub_screen.dart` 主要依赖 `StatefulWidget` 本地状态、`setState` 和 `FutureBuilder`。

## 关键抽象

**`Note`：**
- 目的：表示单页笔记聚合根，承载画布二进制、快照路径、缩略图路径、OCR 文本和展示字段。
- 示例：`lib/core/models/note.dart`
- 模式：Map 与模型双向转换 + 只读计算属性（如 `displayTitle`、`searchableText`）

**`NoteEntry`：**
- 目的：表示旧版规则解析出的轻量条目，兼容费用、事件、健康记录和备忘。
- 示例：`lib/core/models/note_entry.dart`、`lib/shared/widgets/entry_row.dart`
- 模式：规则解析结果 DTO，直接映射 `note_entries` 表

**`ExtractedEntry` / `NormalizedExtractionDocument`：**
- 目的：表示新结构化抽取 schema，支撑 AI 与规则合并后的统一写库格式。
- 示例：`lib/core/extraction/extraction_models.dart`、`lib/core/extraction/extraction_schema_parser.dart`
- 模式：schema-first 文档模型，既可被 AI 返回，也可由规则层构造

**`EntryRecord` / `EntryQuery`：**
- 目的：分别承担结构化查询的读模型和过滤条件。
- 示例：`lib/core/query/entry_record.dart`、`lib/core/query/entry_query.dart`
- 模式：不可变查询对象 + 面向查询结果的只读模型

**`DatabaseHelper` 与 `EntryRepository`：**
- 目的：拆分“基础笔记表访问”和“结构化查询表访问”。
- 示例：`lib/core/storage/database_helper.dart`、`lib/core/storage/entry_repository.dart`
- 模式：单例 helper + 专用 repository 的混合持久化模式

**`OcrEngine` / `TextUnderstandingEngine` / `OcrTextCorrectionEngine`：**
- 目的：隔离平台 OCR、AI 结构化理解和 OCR 文本校对的具体实现。
- 示例：`lib/core/ocr/ocr_engine.dart`、`lib/core/extraction/text_understanding_engine.dart`、`lib/core/extraction/ocr_text_correction_engine.dart`
- 模式：接口优先，运行时注入具体实现，例如 `lib/core/ocr/vision_ocr.dart`、`lib/core/extraction/deepseek_text_understanding_engine.dart`

**`CanvasSaveService`：**
- 目的：把“保存一个画布笔记”收敛成单一服务入口，统一处理图片、主笔记、旧条目和结构化条目。
- 示例：`lib/features/canvas/services/canvas_save_service.dart`
- 模式：应用服务/编排服务，不持有 UI 状态，只接收 `CanvasSaveInput`

## 入口点

**程序入口：**
- 位置：`lib/main.dart`
- 触发：Flutter 运行时启动应用
- 职责：`WidgetsFlutterBinding.ensureInitialized()`，预热 `DatabaseHelper.instance.database`，随后 `runApp(const IdeaNotesApp())`

**应用根：**
- 位置：`lib/app/app.dart`
- 触发：由 `lib/main.dart` 创建
- 职责：创建全局 `NoteListBloc`、触发首次 `LoadNotes()`、挂载 `MaterialApp` 和首页 `lib/features/notelist/note_list_screen.dart`

**首页列表入口：**
- 位置：`lib/features/notelist/note_list_screen.dart`
- 触发：作为 `home` 页面打开
- 职责：展示首页 Hero、全文搜索入口、记录中心入口、最近笔记列表，以及新建/删除/进入详情/进入画布

**画布工作流入口：**
- 位置：`lib/features/canvas/canvas_screen.dart`
- 触发：由列表页新建、语音速记、详情页继续编辑等路径打开
- 职责：采集笔迹、运行 OCR、打开语音录入、预览 AI 整理结果、保存并回写列表状态

**详情入口：**
- 位置：`lib/features/notedetail/note_detail_screen.dart`
- 触发：从列表页或搜索页点击单条笔记
- 职责：加载最新笔记快照、OCR 文本、结构化条目、AI 审计结果，并提供再次进入画布编辑的入口

**结构化查询入口：**
- 位置：`lib/features/records/records_hub_screen.dart`
- 触发：从首页记录中心卡片进入
- 职责：按财务、待办、健康三个标签页展示结构化聚合结果

## 错误处理

**策略：** 以页面级 `try/catch`、结果对象和局部 fallback 为主，把失败转成可见的 UI 状态、提示文案或空结果；当前没有全局异常总线、统一日志系统或集中式错误页。

**模式：**
- `lib/features/notelist/bloc/note_list_bloc.dart` 捕获数据库异常后把状态切到 `NoteListStatus.error`，由 `lib/features/notelist/note_list_screen.dart` 负责渲染错误态。
- `lib/features/canvas/canvas_screen.dart` 在 `_runOcr()` 中先跑手写识别，再回退到图像 OCR；这是当前最明确的链式容错路径。
- `lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/core/extraction/ai_extraction_service.dart`、`lib/features/canvas/services/canvas_ocr_service.dart` 都返回 success/failure DTO，而不是要求调用方解析异常类型。
- `lib/features/canvas/canvas_screen.dart` 在保存、AI 预览、权限申请、OCR 失败时统一用 `SnackBar`、面板状态或底部弹层反馈。
- `lib/core/storage/image_storage.dart` 删除图片失败时只 `debugPrint`，不会阻止数据库删除继续执行。

## 横切关注点

**日志：** 当前没有集中日志框架。运行时日志只在 `lib/core/storage/image_storage.dart` 使用 `debugPrint` 输出图片删除失败信息，其余错误主要在 UI 层转成提示文案。

**校验：** 规则与 schema 校验分散在 `lib/core/parser/entry_text_rules.dart`、`lib/core/parser/expense_extractor.dart`、`lib/core/extraction/extraction_schema_parser.dart`、`lib/core/storage/entry_repository.dart` 的 `_normalizeSortKey()` 等位置；输入通常先 `trim()` 再进入保存或查询流程。

**认证：** 应用本地功能无用户认证。外部 AI 调用通过 `lib/core/config/app_secrets.dart` 读取编译期 `DEEPSEEK_API_KEY`，由 `lib/core/extraction/deepseek_text_understanding_engine.dart` 在请求头中发送。

---

*架构分析：2026-04-16*
