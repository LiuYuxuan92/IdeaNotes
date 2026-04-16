# Coding Conventions

**Analysis Date:** 2026-04-16

## Naming Patterns

**Files:**
- 使用 `snake_case.dart` 文件名。按职责落在分层目录下，例如 `lib/features/notelist/note_list_screen.dart`、`lib/features/canvas/services/canvas_save_service.dart`、`lib/core/storage/database_helper.dart`、`test/widgets/note_detail_screen_test.dart`。
- Widget 文件倾向用 `*_screen.dart`、`*_item.dart`、`*_banner.dart`、`*_sheet.dart`；服务文件倾向用 `*_service.dart`；Bloc 文件放在 `bloc/` 子目录并命名为 `*_bloc.dart`，例如 `lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`。

**Functions:**
- 公有方法、私有方法、局部辅助方法统一使用 `lowerCamelCase`，私有成员以 `_` 开头，例如 `lib/features/notelist/note_list_screen.dart` 中的 `_buildHero`、`_createNewNote`，以及 `lib/features/canvas/services/canvas_save_service.dart` 中的 `_replaceStructuredEntries`。
- 事件处理函数在 Bloc 中固定写成 `_onXxx`，并通过 `on<Event>(_onEvent)` 注册，例如 `lib/features/notelist/bloc/note_list_bloc.dart` 和 `lib/features/canvas/bloc/canvas_bloc.dart`。

**Variables:**
- 普通变量与字段使用 `lowerCamelCase`，布尔值偏好 `is/has/can` 前缀，例如 `lib/features/canvas/canvas_screen.dart` 中的 `_isSaving`、`_hasUnsavedChanges`、`_isResultPanelExpanded`。
- 常量与只读集合多用 `const` + `lowerCamelCase`，例如 `lib/app/design_system.dart` 的 `AppColors` 静态常量、`test/widgets/canvas_screen_test.dart` 的 `_testDatabaseFactory`。

**Types:**
- 类型、枚举、服务、模型、结果对象使用 `UpperCamelCase`，例如 `Note`、`CanvasSaveInput`、`CanvasAiPreviewResult`、`EntryQuery`，见 `lib/core/models/note.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/core/query/entry_query.dart`。
- 枚举值使用简短的 `lowerCamelCase` 或小写词，如 `NoteListStatus.loading`、`CanvasTool.eraser`、`ExtractionEntryType.healthRecord`，见 `lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`、`lib/core/extraction/extraction_models.dart`。

## Code Style

**Formatting:**
- 项目跟随 `flutter_lints`，没有单独的格式化配置文件；基础规则来自 `analysis_options.yaml`。
- 保持 Flutter/Dart 默认格式：命名参数一行一个、长 widget tree 拆成私有构建方法、常量尽量 `const`，对应样例见 `lib/app/app.dart`、`lib/features/search/search_screen.dart`、`lib/app/design_system.dart`。

**Linting:**
- `analysis_options.yaml` 仅 `include: package:flutter_lints/flutter.yaml`，未见额外启停规则。新增代码应先满足 Flutter 官方推荐 lint，再按现有写法补充 `const`、不可变字段和简洁空处理。
- 代码中广泛使用 `Equatable`、`copyWith`、`required` 命名参数来降低状态比较和更新错误，见 `lib/core/models/note.dart`、`lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`。

## Import Organization

**Order:**
1. Dart SDK 导入先写，例如 `dart:async`、`dart:io`、`dart:typed_data`，见 `lib/features/notelist/note_list_screen.dart`、`lib/features/canvas/services/canvas_ocr_service.dart`。
2. 第三方包导入其后，例如 `package:flutter/material.dart`、`package:flutter_bloc/flutter_bloc.dart`、`package:equatable/equatable.dart`，见 `lib/app/app.dart`、`lib/features/canvas/bloc/canvas_bloc.dart`。
3. 项目内相对路径或包路径最后写；`lib/` 下两种写法都存在，但新增代码优先沿用所在目录已有风格。
   - `lib/app/app.dart`、`lib/features/notelist/note_list_screen.dart` 主要用相对导入。
   - 测试文件如 `test/widgets/canvas_screen_test.dart`、`test/services/canvas_save_service_test.dart` 统一使用 `package:idea_notes/...`。

**Path Aliases:**
- 未检测到自定义 path alias。生产代码主要依赖相对路径；测试代码依赖 `package:idea_notes/...` 包导入。

## Error Handling

**Patterns:**
- UI 事件和 Bloc 异步流程以 `try/catch` 包裹，失败时把错误转成状态字段或结果对象，而不是继续向上抛出，见 `lib/features/notelist/bloc/note_list_bloc.dart`、`lib/features/canvas/services/canvas_ocr_service.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`。
- 服务层偏向返回显式结果对象，例如 `CanvasOcrResult`、`CanvasAiPreviewResult`、`AiExtractionResult`、`CanvasLoadResult`，见 `lib/features/canvas/services/canvas_ocr_service.dart`、`lib/features/canvas/services/canvas_ai_preview_service.dart`、`lib/core/extraction/ai_extraction_service.dart`、`lib/features/canvas/services/canvas_load_service.dart`。
- 外部依赖或可选能力失败时常做“降级继续”而不是中断主流程。
  - 图像删除失败会吞掉异常，继续删除数据库记录，见 `lib/features/notelist/bloc/note_list_bloc.dart`。
  - OCR 文本校正失败会直接回退原文本，见 `lib/features/canvas/services/canvas_ai_preview_service.dart`。
  - 临时目录清理失败不会影响 OCR 主结果，见 `lib/features/canvas/services/canvas_ocr_service.dart`。
- 面向 API/网络的底层引擎会细分异常来源并拼装可读错误文本，例如 `lib/core/extraction/deepseek_text_understanding_engine.dart` 与 `lib/core/extraction/deepseek_ocr_text_correction_engine.dart`。

## State Management

**Patterns:**
- 全局列表状态用 `flutter_bloc` 管理，在应用根部注入 `NoteListBloc`，见 `lib/app/app.dart`。
- 页面局部但行为复杂的绘图状态同样用 Bloc，不过由页面自己持有并通过 `BlocProvider.value` 下发，见 `lib/features/canvas/canvas_screen.dart` 和 `lib/features/canvas/bloc/canvas_bloc.dart`。
- 只影响局部交互的瞬时 UI 状态仍保留在 `StatefulWidget` 私有字段中，而不是塞进 Bloc。
  - 搜索框展开、输入防抖、控制器、ScrollController 在 `lib/features/notelist/note_list_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/notedetail/note_detail_screen.dart`。
  - 保存中、识别中、面板展开态在 `lib/features/canvas/canvas_screen.dart`。
- 状态对象尽量不可变，并通过 `copyWith` 更新。
  - `lib/features/notelist/bloc/note_list_bloc.dart` 的 `NoteListState`
  - `lib/features/canvas/bloc/canvas_bloc.dart` 的 `CanvasState`
  - `lib/core/models/note.dart` 的 `Note`
  - `lib/features/canvas/models/canvas_editor_state.dart` 的 `CanvasEditorState`
- UI 通过 `context.read<Bloc>().add(...)` 触发状态变更，渲染侧用 `BlocBuilder` 读取，不直接操作底层存储，见 `lib/features/notelist/note_list_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/canvas/canvas_toolbar.dart`。

## UI / Service Boundaries

**Patterns:**
- `features/` 下的 screen/widget 负责布局、导航、控件交互与少量页面级瞬时状态，不直接拼 SQL 或调用远端接口。
  - `lib/features/search/search_screen.dart` 只负责搜索输入、布局切换和跳转。
  - `lib/features/notedetail/note_detail_screen.dart` 负责展示组合结果，但结构化查询通过 `EntryRepository` 获取。
- 业务和数据写入逻辑下沉到 service / repository / core 层。
  - 保存链路由 `lib/features/canvas/services/canvas_save_service.dart` 执行，负责图片持久化、旧表写入、结构化抽取和 repository 更新。
  - 查询链路由 `lib/core/storage/entry_repository.dart`、`lib/core/query/analytics_service.dart`、`lib/core/query/timeline_service.dart` 负责。
  - OCR/AI 能力通过接口或服务包装，页面用 override 参数注入实现，见 `lib/features/canvas/canvas_screen.dart` 的 `ocrEngineOverride`、`saveServiceOverride`、`aiPreviewServiceOverride`、`voiceRecognitionServiceOverride`。
- 未来新增 UI 代码时，保持“页面编排 + 服务注入 + repository 持久化”的边界，不要把数据库操作写回 `screen.dart`。

## Logging

**Framework:** `debugPrint`

**Patterns:**
- 没有统一日志框架。仅在底层平台/文件/OCR 辅助代码中零散使用 `debugPrint` 记录非致命错误，见 `lib/core/storage/image_storage.dart`、`lib/core/ocr/mlkit_ocr.dart`。
- 业务层和页面层更常见的做法是返回失败结果、更新状态或弹 `SnackBar`，而不是输出控制台日志，见 `lib/features/canvas/canvas_screen.dart`、`lib/features/notelist/bloc/note_list_bloc.dart`。

## Comments

**When to Comment:**
- 注释数量不多，但在以下位置会写注释：
  - 解释测试专用注入点或单例替换，例如 `lib/core/storage/database_helper.dart` 的 `injectDatabase`。
  - 解释复杂序列化、降级逻辑或工具意图，例如 `lib/features/canvas/bloc/canvas_bloc.dart` 的序列化方法注释。
  - 测试文件用分段注释隔开场景，如 `test/bloc/note_list_bloc_test.dart`。
- 新增注释应继续只写“为什么”或“约束”，不要给明显语句逐行翻译。

**JSDoc/TSDoc:**
- Dart doc comments 存在但不普遍，主要出现在抽象接口与少数关键方法，例如 `lib/core/ocr/ocr_engine.dart`、`lib/core/storage/database_helper.dart`。
- 普通 widget 和服务大多不写完整 API 文档，依靠清晰命名表达意图。

## Function Design

**Size:** 
- 大型 screen 文件把 UI 拆成大量 `_buildXxx` 私有方法，而不是一个超长 `build`，见 `lib/features/notelist/note_list_screen.dart`、`lib/features/search/search_screen.dart`、`lib/features/notedetail/note_detail_screen.dart`、`lib/features/canvas/canvas_screen.dart`。
- 服务方法倾向围绕单一主流程拆成一组私有辅助方法，例如 `lib/features/canvas/services/canvas_save_service.dart` 的 `save`、`_persistImages`、`_upsertNote`、`_replaceEntries`。

**Parameters:**
- 构造器和主入口函数偏好命名参数，依赖通常 `required`，可替换能力通过可选 override 参数暴露，见 `lib/features/canvas/canvas_screen.dart`、`lib/features/canvas/services/canvas_save_service.dart`、`lib/features/canvas/services/canvas_ocr_service.dart`。
- 结果对象和查询对象尽量显式化，避免长参数列表或动态 map 横穿多层，见 `lib/features/canvas/services/canvas_save_service.dart` 的 `CanvasSaveInput` 和 `lib/core/query/entry_query.dart`。

**Return Values:**
- 对外部依赖或多步骤流程，优先返回封装结果对象；对纯查询或简单转换，直接返回模型或集合。
  - 结果对象：`CanvasOcrResult`、`CanvasAiPreviewResult`、`AiExtractionResult`、`CanvasLoadResult`
  - 直接返回：`List<EntryRecord>` 于 `lib/core/storage/entry_repository.dart`，`AmountSummary` 于 `lib/core/query/analytics_service.dart`

## Module Design

**Exports:**
- 未见 barrel file。模块引用直接指向具体文件路径，例如 `lib/app/app.dart` 直接导入 `../features/notelist/bloc/note_list_bloc.dart`，测试直接导入 `package:idea_notes/features/canvas/services/canvas_save_service.dart`。
- 新增模块时应继续直接导入源文件，避免先引入新的 `index.dart`/barrel 层。

**Barrel Files:** 
- 未检测到。

## Additional Guidance

- 配置型密钥通过构造器注入或 `String.fromEnvironment` 读取，不从源码硬编码，见 `lib/core/config/app_secrets.dart`、`lib/core/extraction/deepseek_text_understanding_engine.dart`。
- 数据访问统一经过 `DatabaseHelper` 或 `EntryRepository`，不要在多个 screen 内重复写 SQLite 语句；现有集中入口分别是 `lib/core/storage/database_helper.dart` 和 `lib/core/storage/entry_repository.dart`。
- 查询条件用不可变查询对象 `EntryQuery` 传递，避免把筛选条件拆散成多参数，见 `lib/core/query/entry_query.dart`、`test/query/entry_query_test.dart`。

---

*Convention analysis: 2026-04-16*
