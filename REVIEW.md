# IdeaNotes 项目评审报告

**评审日期**: 2026-03-21
**代码规模**: ~18,600 行（含测试），47 个 Dart 源文件 + 26 个测试文件

---

## 一、总体评价

IdeaNotes 是一个结构清晰、功能完整度较高的 Flutter 项目。Feature-First 目录组织得当，BLoC 状态管理运用规范，数据库迁移机制成熟（已到 v6），规则引擎 + AI 双轨提取的架构有前瞻性。测试覆盖面广，涵盖 parser、extraction、BLoC、widget 等层级。

以下按**严重程度**分级列出需要关注的问题。

---

## 二、P0 — 必须立即修复

### 2.1 API Key 硬编码在源码中

**文件**: `lib/core/extraction/deepseek_text_understanding_engine.dart:10`

```dart
static const String _defaultApiKey = '[REDACTED_DEEPSEEK_KEY]';
```

API 密钥直接写死在代码里并提交到 Git 仓库，属于严重安全隐患：
- 任何能访问仓库的人都可以盗用该 Key
- Key 已经进入 Git 历史，即使后续删除也可以从历史中恢复
- 如果仓库公开，Key 会被自动扫描工具发现

**建议**:
1. 立即吊销当前 Key，在 DeepSeek 控制台重新生成
2. 改用运行时配置注入（环境变量 / Flutter `--dart-define` / Secure Storage）
3. 将 API Key 加入 `.gitignore` 管理的配置文件中
4. 考虑用 `git filter-branch` 或 BFG 清理历史中的 Key

### 2.2 SQL 注入风险 — `searchNotes` 方法

**文件**: `lib/core/storage/database_helper.dart:122`

```dart
return await db.query(
  'notes',
  where: 'recognized_text LIKE ?',
  whereArgs: ['%$query%'],
);
```

虽然使用了参数化查询（`whereArgs`），但 `query` 中的 `%` 和 `_` 是 LIKE 的通配符，用户输入包含这些字符时会导致非预期匹配。应对 `query` 进行 LIKE 转义：

```dart
final escaped = query.replaceAll('%', '\\%').replaceAll('_', '\\_');
// 并在 WHERE 子句中加 ESCAPE '\\'
```

---

## 三、P1 — 架构 / 设计问题

### 3.1 CanvasScreen 过于庞大（1909 行）

**文件**: `lib/features/canvas/canvas_screen.dart`

这是整个项目最大的单文件，混合了：
- 画布手势处理
- OCR 调度
- AI 预览
- 语音输入
- 权限管理
- 保存逻辑
- 多种 Bottom Sheet
- 响应式布局（Compact / Large）
- 大量私有 Widget 类

**建议**: 按职责拆分为多个文件：
- `canvas_gesture_handler.dart` — 手势 + 笔画
- `canvas_ocr_controller.dart` — OCR 流程
- `canvas_voice_controller.dart` — 语音权限 + 输入
- `canvas_layout.dart` — 响应式布局 Widget
- 将 `_AiPreviewSheet`、`_PanelStatusPill` 等私有 Widget 提取为独立文件

### 3.2 CanvasBloc 未通过 Provider 注入

**文件**: `lib/features/canvas/canvas_screen.dart:82`

```dart
_canvasBloc = CanvasBloc();
```

`CanvasBloc` 在 `_CanvasScreenState.initState()` 中直接 `new` 出来，而非通过 `BlocProvider` 从上层获取。这与 `app.dart` 中 CLAUDE.md 描述的"CanvasBloc are provided globally at app root via MultiBlocProvider"不一致。实际上 `app.dart` 只提供了 `NoteListBloc`。

**影响**:
- 每次进入 CanvasScreen 都创建新实例，无法跨页面共享状态
- 测试时更难 mock

**建议**: 如果确实需要每页独立的 CanvasBloc，文档应更新。如果需要共享，应提升到 `MultiBlocProvider`。

### 3.3 DatabaseHelper 使用 Singleton 模式但无依赖注入

**文件**: `lib/core/storage/database_helper.dart`

`DatabaseHelper.instance` 是全局单例，被 `CanvasScreen`、`NoteDetailScreen`、`RecordsHubScreen` 等直接引用。这使得：
- 单元测试必须通过 `injectDatabase()` hack 来替换
- 无法为不同模块使用不同的数据库配置
- 耦合度高

**建议**: 通过构造函数注入或使用 `RepositoryProvider` 在 Widget 树中提供。`NoteListBloc` 已经正确地通过构造函数接收 `DatabaseHelper`，其他地方应保持一致。

### 3.4 NoteListBloc 搜索用 Note ID 代替标题

**文件**: `lib/features/notelist/bloc/note_list_bloc.dart:125`

```dart
final title = note.id.toLowerCase(); // BUG: 搜索匹配的是 UUID，不是标题
```

`Note` 模型没有 `title` 字段，搜索时用 `note.id`（UUID）作为"标题"匹配。UUID 对用户没有语义，搜标题永远命中不了。

**建议**:
- 给 `Note` 模型增加 `title` 字段（可从 recognized_text 第一行自动生成）
- 或者搜索时只匹配 `recognizedText`

### 3.5 双写 Legacy + Structured Entries

**文件**: `lib/features/canvas/services/canvas_save_service.dart:158-165`

每次保存都同时写入 `note_entries`（旧表）和 `entries`（新表）。这意味着：
- 写入量翻倍
- 数据一致性需要额外保证
- 旧表何时可以废弃没有明确计划

**建议**: 制定迁移时间表，评估是否可以只写新表 + 提供兼容读取。

---

## 四、P2 — 代码质量问题

### 4.1 `_onPanUpdate` 每次创建新 List

**文件**: `lib/features/canvas/canvas_screen.dart:914-917`

```dart
void _onPanUpdate(DragUpdateDetails details) {
  setState(() {
    _currentPoints = <Offset>[..._currentPoints, details.localPosition];
  });
}
```

每个手势移动事件都复制整个 `_currentPoints` 列表。在快速书写时这会产生大量 GC 压力（一个笔画可能有数百个点）。

**建议**: 使用可变 List 并直接 `add`，或者避免在 `_currentPoints` 更新时触发 `setState`（改用 `ValueNotifier` 或直接在 `CustomPainter` 层优化）。

### 4.2 重复排序

**文件**: `lib/features/notelist/bloc/note_list_bloc.dart:96-99`

```dart
final notesData = await databaseHelper.getNotes(); // SQL 已经 ORDER BY updated_at DESC
final notes = notesData.map((data) => Note.fromMap(data)).toList();
notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // 又排了一次
```

`getNotes()` 的 SQL 已经按 `updated_at DESC` 排序，Dart 层又排一次，属于冗余操作。

### 4.3 缩略图硬编码 200x200 不保留宽高比

**文件**: `lib/core/storage/image_storage.dart:61`

```dart
final thumbnail = img.copyResize(decoded, width: 200, height: 200);
```

同时指定 width 和 height 会拉伸变形图片。应保留宽高比：

```dart
final thumbnail = img.copyResize(decoded, width: 200); // 高度自动按比例
```

### 4.4 每次保存都生成新文件名（snapshot 泄漏）

**文件**: `lib/core/storage/image_storage.dart:47`

```dart
final fileName = '${noteId}_${_uuid.v4()}.png';
```

每次保存都用新 UUID 生成文件名，但没有删除旧的 snapshot 文件。多次保存同一笔记会导致快照文件不断累积。

**建议**: 保存前先删除该 noteId 的旧快照文件，或复用固定文件名。

### 4.5 `_onRefreshNotes` 在 handler 中 add 事件

**文件**: `lib/features/notelist/bloc/note_list_bloc.dart:192-194`

```dart
Future<void> _onRefreshNotes(RefreshNotes event, Emitter<NoteListState> emit) async {
  add(LoadNotes());
}
```

在事件处理器中 `add` 新事件是 BLoC 的反模式——它跳过了当前 handler 的 emit 生命周期，可能导致状态更新时序问题。应直接调用 `_onLoadNotes` 的逻辑或复用共享方法。

### 4.6 darkTheme 没有实际暗色主题

**文件**: `lib/app/app.dart:23`

```dart
theme: AppTheme.light(),
darkTheme: AppTheme.light(), // 暗色模式也用亮色主题
```

`darkTheme` 也设置为 `AppTheme.light()`，意味着系统切换到暗色模式后 UI 不会有任何变化。如果暂不支持暗色模式，应移除 `darkTheme` 行或显式设置 `themeMode: ThemeMode.light`。

### 4.7 Note.entries 字段从未被填充

**文件**: `lib/core/models/note.dart:13`

```dart
final List<NoteEntry> entries;
```

`Note` 模型包含 `entries` 字段，默认值为空列表。但 `Note.fromMap()` 从不从数据库读取 entries，`toMap()` 也不写入。这是一个无用字段，会误导阅读者认为 Note 对象自带 entries。

---

## 五、P3 — 可维护性建议

### 5.1 硬编码中文字符串散落各处

UI 文本（"新建手写笔记"、"识别当前画布"、"保存当前笔记"等）直接写在 Widget 树中。建议：
- 集中到 `l10n/` 目录使用 Flutter Intl
- 或至少集中到常量文件，为未来国际化做准备

### 5.2 缺少错误上报机制

`canvas_screen.dart` 中多处 `catch (_)` 吞掉异常，生产环境无法追踪问题。建议接入 Crashlytics 或 Sentry。

### 5.3 EntryParser 对 `DateTime.now()` 的隐式依赖

`_parseTemporalInfo` 内部调用 `DateTime.now()`，使得日期解析在测试中不确定。`_parseDate` 已支持 `now` 参数，应将其传递到外层 `parse()` 方法。

### 5.4 缺少 integration test 和 golden test

当前 26 个测试文件全部是 unit / widget test，缺少：
- Integration test（端到端的 画布→OCR→保存→列表刷新 流程）
- Golden test（UI 截图回归测试）

### 5.5 analysis_options.yaml 规则较松

当前只用了 `flutter_lints` 默认配置，建议启用更多规则：
```yaml
linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: true
    unawaited_futures: true
    cancel_subscriptions: true
```

### 5.6 无 CI/CD 配置

项目只有 `.github/pull_request_template.md`，缺少 GitHub Actions workflow 来自动运行 `flutter analyze` + `flutter test`。

---

## 六、架构亮点（值得肯定的做法）

1. **双轨提取（Rule + AI）架构**: `ExtractionOrchestrator` 先用规则引擎解析，再可选地用 LLM 增强，两者结果通过 `EntryMergeService` 合并。降级路径清晰——没有 AI 时纯规则也能工作。

2. **数据库迁移体系完整**: 6 个版本的 Schema 迁移逻辑清晰，`_backfillEntriesFromLegacyNoteEntries` 用纯 SQL 完成旧数据迁移，高效且原子化。

3. **可测试的 Service 设计**: `CanvasSaveService` 通过构造函数注入 `createId`、`saveSnapshot`、`saveThumbnail` 等依赖，测试时可以完全控制副作用。

4. **中文 NLP 规则引擎**: `EntryParser` + `EntryTextRules` 对中文场景下的时间（今天/明天/下周一）、金额（¥50 / 50块3毛）、关键词（记得/别忘了）做了细致的 Regex 处理，测试覆盖充分。

5. **响应式布局**: CanvasScreen 对 Compact / Medium / Large 三种视口做了完整的自适应布局，包括侧边面板 vs 底部抽屉的切换。

6. **审计追溯**: `ai_extractions` 表记录每次 AI 调用的输入、原始响应和归一化结果，便于调试和质量回溯。

---

## 七、总结

| 级别 | 数量 | 核心议题 |
|------|------|----------|
| P0   | 2    | API Key 泄露、LIKE 通配符转义 |
| P1   | 5    | 巨型文件、BLoC 不一致、搜索 Bug、双写开销、单例耦合 |
| P2   | 7    | 性能（List 复制）、文件泄漏、暗色主题、无用字段等 |
| P3   | 6    | i18n、错误上报、CI/CD、测试覆盖等 |

**优先行动建议**:
1. 立即修复 API Key 泄露（P0）
2. 修复搜索 Bug（用 ID 匹配标题）
3. 拆分 CanvasScreen
4. 添加 CI pipeline（`flutter analyze` + `flutter test`）
5. 制定 Legacy entries 表的废弃计划
