# Testing Patterns

**Analysis Date:** 2026-04-16

## Test Framework

**Runner:**
- `flutter_test`，依赖定义在 `pubspec.yaml`。
- 配置文件：未检测到单独的 `flutter_test_config.dart`、`jest.config.*`、`vitest.config.*`；数据库相关测试靠每个测试文件自行初始化 `sqflite_common_ffi`。

**Assertion Library:**
- 使用 `package:flutter_test/flutter_test.dart` 自带断言与 widget test 能力，例如 `test/widgets/canvas_screen_test.dart`、`test/parser/entry_parser_test.dart`。

**Run Commands:**
```bash
flutter test                    # 运行全部测试
flutter test test/widgets       # 运行某个目录
flutter test --coverage         # 生成 coverage/lcov.info（仓库当前未提交覆盖率产物）
```

## Test File Organization

**Location:**
- 测试全部放在仓库根目录 `test/` 下，按业务层次分目录，而不是与源码同目录共置。
- 主要目录与源码映射如下：
  - `test/widgets/` 对应 `lib/features/...` 与 `lib/shared/widgets/...`
  - `test/bloc/` 对应 `lib/features/.../bloc/...`
  - `test/services/` 与 `test/features/canvas/services/` 对应 service 层
  - `test/query/` 对应 `lib/core/query/...` 与 `lib/core/storage/entry_repository.dart`
  - `test/storage/` 对应 `lib/core/storage/...`
  - `test/parser/`、`test/extraction/`、`test/models/`、`test/core/config/` 对应 `lib/core/...`

**Naming:**
- 统一使用 `*_test.dart`，例如 `test/widgets/search_screen_test.dart`、`test/services/canvas_save_service_test.dart`、`test/storage/database_migrations_test.dart`。

**Structure:**
```text
test/
├── bloc/
├── core/config/
├── extraction/
├── features/canvas/services/
├── models/
├── parser/
├── query/
├── services/
├── storage/
├── widgets/
└── widget_test.dart
```

## Test Structure

**Suite Organization:**
```dart
void main() {
  group('CanvasSaveService', () {
    setUp(() async {
      await _setUpInMemoryDatabase();
    });

    tearDown(() async {
      await DatabaseHelper.instance.close();
    });

    test('创建新 note 时会写入 note 与 entries', () async {
      // arrange
      // act
      // assert
    });
  });
}
```
- 上述模式直接见 `test/services/canvas_save_service_test.dart`、`test/services/canvas_load_service_test.dart`、`test/query/query_services_test.dart`。

**Patterns:**
- 使用 `group(...)` 按模块或子场景分组，复杂解析类会按规则分多组，例如 `test/parser/entry_parser_test.dart`。
- `setUp` / `tearDown` 常用于初始化与关闭内存数据库，见 `test/bloc/note_list_bloc_test.dart`、`test/storage/database_migrations_test.dart`、`test/widgets/note_detail_screen_test.dart`。
- Widget 测试使用 `testWidgets` + `pumpWidget`/`pumpAndSettle`，并配合 `find.text`、`find.byType`、`find.byIcon` 验证 UI。
- 对异步 Bloc 测试，当前代码库多用 `Future.delayed(...)` 等待状态稳定，而不是引入专门的 bloc 测试工具，见 `test/bloc/note_list_bloc_test.dart`。

## Mocking

**Framework:** 手写 fake / stub / test subclass；未检测到 `mockito`、`mocktail`。

**Patterns:**
```dart
class _FakeOcrEngine implements OcrEngine {
  List<String> result;
  Object? error;

  _FakeOcrEngine({this.result = const [], this.error});

  @override
  Future<List<String>> recognizeTextFromFile(String imagePath) async {
    if (error != null) throw error!;
    return result;
  }
}
```
- 该模式见 `test/services/canvas_ocr_service_test.dart`。

```dart
class _TestNoteListBloc extends NoteListBloc {
  _TestNoteListBloc(NoteListState initial)
      : super(databaseHelper: DatabaseHelper.instance) {
    emit(initial);
  }

  @override
  void add(NoteListEvent event) {
    // 屏蔽真实加载
  }
}
```
- 该模式见 `test/widgets/note_list_screen_test.dart`、`test/widgets/search_screen_test.dart`。

**What to Mock:**
- 外部引擎或平台依赖用 fake 替换：
  - OCR 引擎：`test/services/canvas_ocr_service_test.dart`
  - 文本理解/文本纠正引擎：`test/features/canvas/services/canvas_ai_preview_service_test.dart`、`test/widgets/canvas_screen_test.dart`、`test/extraction/ai_extraction_service_test.dart`
- 页面可替换依赖通过构造器 override 注入，而不是在测试里 patch 全局单例：
  - `lib/features/canvas/canvas_screen.dart` 的 `ocrEngineOverride`
  - `lib/features/canvas/canvas_screen.dart` 的 `saveServiceOverride`
  - `lib/features/canvas/canvas_screen.dart` 的 `aiPreviewServiceOverride`
  - `lib/features/canvas/canvas_screen.dart` 的 `voiceRecognitionServiceOverride`
- 文件系统操作通过依赖注入替换回调，而不是触发真实 IO，见 `lib/features/canvas/services/canvas_ocr_service.dart` 与 `test/services/canvas_ocr_service_test.dart`。

**What NOT to Mock:**
- SQLite 查询、迁移、Repository 组合逻辑通常不 mock；测试会直接起内存数据库或临时数据库验证真实表结构与数据结果，见 `test/query/query_services_test.dart`、`test/storage/database_migrations_test.dart`、`test/services/canvas_flow_contract_test.dart`。
- Parser、模型转换、查询对象 `copyWith` 等纯逻辑直接测真实实现，见 `test/parser/entry_parser_test.dart`、`test/models/note_model_test.dart`、`test/query/entry_query_test.dart`。

## Override / Test Injection

**Patterns:**
- 数据库单例通过 `DatabaseHelper.injectDatabase(db)` 注入测试库，见 `lib/core/storage/database_helper.dart` 和大量测试初始化代码，如 `test/bloc/note_list_bloc_test.dart`、`test/services/canvas_save_service_test.dart`。
- SQLite FFI 通过 `open.overrideForAll(_openSqlite)` 指向本机动态库，见 `test/storage/database_migrations_test.dart`、`test/query/query_services_test.dart`、`test/widgets/note_detail_screen_test.dart`。
- Widget 测试常注入固定 `MediaQuery` 或 surface size 验证响应式布局，见 `test/widgets/search_screen_test.dart`、`test/widgets/canvas_screen_test.dart`。
- 服务层 override 点普遍走构造器注入：
  - `CanvasSaveService(createId/saveSnapshot/saveThumbnail/entryRepository/textUnderstandingEngine)` 于 `lib/features/canvas/services/canvas_save_service.dart`
  - `CanvasOcrService(createTempDirectory/writeFile/deleteDirectory)` 于 `lib/features/canvas/services/canvas_ocr_service.dart`
  - `CanvasAiPreviewService(engine/correctionEngine)` 于 `lib/features/canvas/services/canvas_ai_preview_service.dart`

## Fixtures and Factories

**Test Data:**
```dart
Future<void> _insertNote({
  required String id,
  required String recognizedText,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await DatabaseHelper.instance.insertNote({
    'id': id,
    'notebook_id': 'default-notebook',
    'created_at': now,
    'updated_at': now,
    'recognized_text': recognizedText,
  });
}
```
- 该类轻量 helper 模式见 `test/widgets/canvas_screen_test.dart`。

```dart
Future<void> _seedData() async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('entries', {...});
  await db.insert('entry_tags', {...});
}
```
- 该类直接写表的场景种子模式见 `test/query/query_services_test.dart`、`test/widgets/note_detail_screen_test.dart`。

**Location:**
- 没有集中 `fixtures/` 或 `factories/` 目录。
- 测试数据构建器通常写在各自测试文件顶部，作为私有函数或私有 fake 类，便于就地阅读。

## Coverage

**Requirements:** 
- 未检测到覆盖率门禁、最小阈值或 CI 覆盖率校验配置。
- 当前测试策略明显偏重核心业务路径的“回归防线”而非全量组件覆盖。

**View Coverage:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## Test Types

**Unit Tests:**
- 纯规则和模型优先写单元测试：
  - 解析器：`test/parser/entry_parser_test.dart`、`test/parser/expense_extractor_test.dart`
  - 模型/查询对象：`test/models/note_model_test.dart`、`test/models/canvas_editor_state_test.dart`、`test/query/entry_query_test.dart`
  - AI 结果解析与合并：`test/extraction/extraction_schema_parser_test.dart`、`test/extraction/entry_merge_service_test.dart`

**Integration Tests:**
- 存储、迁移、查询、保存-加载链路用“真实 SQLite + 真实 repository/service”组合测试：
  - 迁移：`test/storage/database_migrations_test.dart`
  - 查询服务：`test/query/query_services_test.dart`
  - 保存/加载合同：`test/services/canvas_flow_contract_test.dart`
  - 保存服务：`test/services/canvas_save_service_test.dart`

**E2E Tests:**
- 未检测到 `integration_test/` 或 Flutter 驱动测试。

## Common Patterns

**Async Testing:**
```dart
bloc.add(LoadNotes());
await Future.delayed(const Duration(milliseconds: 200));
expect(bloc.state.status, equals(NoteListStatus.loaded));
```
- 该模式见 `test/bloc/note_list_bloc_test.dart`。

```dart
await tester.pumpWidget(const MaterialApp(home: CanvasScreen()));
await tester.pumpAndSettle();
expect(find.text('识别结果'), findsOneWidget);
```
- Widget 异步稳定化使用 `pump()` 或 `pumpAndSettle()`，见 `test/widgets/canvas_screen_test.dart`、`test/widgets/note_detail_screen_test.dart`。

**Error Testing:**
```dart
final result = await service.recognize(
  ocrEngine: _FakeOcrEngine(error: Exception('boom')),
  imageBytes: Uint8List.fromList([1]),
);

expect(result.success, isFalse);
expect(result.errorMessage, '识别失败，请重试');
```
- 该模式见 `test/services/canvas_ocr_service_test.dart`。

```dart
final result = await engine.extractStructuredData(request);
expect(result.success, isFalse);
expect(result.errorMessage, contains('invalid api key'));
```
- API 失败断言见 `test/extraction/deepseek_text_understanding_engine_test.dart`、`test/extraction/deepseek_ocr_text_correction_engine_test.dart`。

## Coverage Focus

**当前覆盖重点：**
- 核心领域规则覆盖很强：
  - OCR 文本到旧版 `NoteEntry` 的解析规则，见 `test/parser/entry_parser_test.dart`
  - OCR 文本到结构化 `entries` 的保存逻辑，见 `test/services/canvas_save_service_test.dart`
  - AI schema 解析、合并、预览与 API 包装，见 `test/extraction/ai_extraction_service_test.dart`、`test/extraction/extraction_orchestrator_test.dart`、`test/features/canvas/services/canvas_ai_preview_service_test.dart`
- 数据库变更覆盖较强：
  - 迁移建表和旧数据回填，见 `test/storage/database_migrations_test.dart`
  - 查询过滤、时间线、统计汇总，见 `test/query/query_services_test.dart`
- 关键页面存在可见性/分支覆盖：
  - `NoteListScreen` 空态、错误态、摘要态：`test/widgets/note_list_screen_test.dart`
  - `SearchScreen` 桌面/手机与键盘场景：`test/widgets/search_screen_test.dart`
  - `CanvasScreen` 编辑、保存、AI 预览：`test/widgets/canvas_screen_test.dart`
  - `NoteDetailScreen` 结构化条目优先展示：`test/widgets/note_detail_screen_test.dart`

## Coverage Gaps

**当前明显缺口：**
- `lib/app/design_system.dart` 只被间接覆盖，没有针对主题 token、响应式扩展、通用组件的专门测试。
- `lib/features/records/records_hub_screen.dart` 体量较大，但未看到对应 widget 测试；结构化查询 UI 的筛选、分页、分栏呈现风险较高。
- `lib/features/canvas/widgets/voice_capture_sheet.dart` 与 `lib/features/canvas/services/voice_recognition_service.dart` 未看到同等级别测试，语音录入流程缺口明显。
- `lib/core/ocr/mlkit_ocr.dart`、`lib/core/ocr/vision_ocr.dart` 只有抽象/服务侧覆盖，平台实现本身缺少单元测试。
- `lib/shared/widgets/ocr_result_banner.dart`、`lib/shared/widgets/entry_row.dart` 未见独立测试；目前主要靠页面集成测试间接覆盖。
- `lib/features/notedetail/note_detail_screen.dart` 与 `lib/features/canvas/canvas_screen.dart` 文件很大，现有测试只覆盖部分关键路径，滚动导航、折叠面板、异常提示、权限拒绝等分支仍有空洞。
- `test/widget_test.dart` 仍是轻量 smoke test，只验证 `MaterialApp` 和标题存在，对应用启动链路的回归价值有限。

## Recommended Test Writing Rules

- 新增 service 时，优先提供可注入依赖或回调，再写 fake 驱动的单元测试；当前代码库已经依赖这种模式，参考 `lib/features/canvas/services/canvas_ocr_service.dart` 和 `test/services/canvas_ocr_service_test.dart`。
- 新增存储或查询逻辑时，优先接入内存 SQLite 测试，而不是只 mock repository；当前真实数据表验证是仓库测试的核心风格，参考 `test/query/query_services_test.dart` 与 `test/storage/database_migrations_test.dart`。
- 新增复杂页面时，至少补三类 widget 测试：
  - 空态/错误态
  - 主要成功态
  - 一种响应式或交互分支
  参考 `test/widgets/note_list_screen_test.dart`、`test/widgets/search_screen_test.dart`、`test/widgets/canvas_screen_test.dart`。

---

*Testing analysis: 2026-04-16*
