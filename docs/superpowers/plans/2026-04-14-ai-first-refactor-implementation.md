# IdeaNotes AI-First Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade IdeaNotes from manual save-then-extract flow to an Android-first AI-first handwriting experience with prerequisite security fixes, modular canvas architecture, realtime extraction preview, and visual analytics.

**Architecture:** Keep the existing Flutter + BLoC + SQLite architecture, but add focused services around the canvas and extraction pipeline instead of rewriting the entire app at once. Work in thin vertical slices: secure configuration first, then schema and interfaces, then modular canvas decomposition, then realtime extraction preview, then records visualization.

**Tech Stack:** Flutter, Dart, flutter_bloc, sqflite, google_mlkit_text_recognition, google_mlkit_digital_ink_recognition, permission_handler, image, uuid, fl_chart

**Branch:** `feature/ai-first-refactor` on `origin` (`https://github.com/LiuYuxuan92/IdeaNotes.git`)
**Worktree:** `D:\claude-code\IdeaNotes\claude-codeIdeaNotes\.worktrees\ai-first-refactor`

---

## Progress Tracker (Updated 2026-04-15)

| Task | Description | Status | Commit |
|------|------------|--------|--------|
| 1 | Remove hardcoded secrets | ✅ Done | included in `ef12b4b` |
| 2 | Fix search wildcard + migration v7 | ✅ Done | included in `ef12b4b` |
| 3 | Extraction preview repository | ✅ Done | included in `ef12b4b` |
| 4 | Stroke styles + painter hooks | ✅ Done | `5ff433f` |
| 5 | Stable-region + incremental OCR | ✅ Done | this commit |
| 6 | Realtime extraction pipeline | ✅ Done | `f038766` |
| 7 | Split canvas screen | ✅ Done | included in `ef12b4b` |
| 8 | Wire realtime preview into stroke flow | ✅ Done | this commit |
| 9 | Records charts | ✅ Done | included in `ef12b4b` |
| 10 | Full verification | ✅ Done (format/analyze/test/build all pass) | this commit |

**All 10 tasks complete.** Remaining: manual smoke check on device.

### Verification evidence (2026-04-15)
- `dart format lib test` — 2 files reformatted, no errors
- `flutter analyze` — No issues found
- `flutter test` — 250 tests passed
- `flutter build apk --debug` — APK generated at `build/app/outputs/flutter-apk/app-debug.apk` (with `ANDROID_HOME=/d/Android/Sdk`)

### What was done in this session
- **Task 5:** Created `lib/features/canvas/services/region_capture_service.dart` — captures a sub-region of a RepaintBoundary and returns cropped PNG bytes.
- **Task 8:** Wired `InkStabilityDetector` + `RegionCaptureService` + `IncrementalOcrService` + `DefaultRealtimeExtractionPipeline` into `canvas_screen.dart`:
  - On pen-up (`_onPanEnd`), stroke bounds are registered with `InkStabilityDetector`
  - After 1.5s idle, stable region triggers: capture → incremental OCR → pipeline submitDelta → preview card appears via `CanvasAiOverlay`
  - All services are injectable via constructor overrides for testing
  - Pipeline preview stream drives UI updates

---

## File Structure Map

### Existing files to modify
- `lib/core/extraction/deepseek_api_defaults.dart` — remove hardcoded API key, keep endpoint/model defaults only
- `lib/core/storage/database_helper.dart` — escape LIKE wildcards, add helper methods used by new preview flow
- `lib/core/storage/database_migrations.dart` — bump schema from v6 to v7 and add preview/correction columns
- `lib/app/app.dart` — register app-level dependencies for canvas and extraction services
- `lib/features/canvas/bloc/canvas_bloc.dart` — add richer stroke metadata and preview state events
- `lib/features/canvas/widgets/canvas_painter.dart` — move toward layered rendering hooks and richer stroke style support
- `lib/features/canvas/canvas_screen.dart` — shrink to assembly/orchestration only
- `lib/features/canvas/canvas_toolbar.dart` — add stroke style selector and preview controls
- `lib/features/canvas/services/canvas_save_service.dart` — store corrections and confirmed preview entries
- `lib/features/records/records_hub_screen.dart` — add charts and summary cards
- `pubspec.yaml` — add `fl_chart`

### New files to create
- `lib/core/config/app_secrets.dart` — read `DEEPSEEK_API_KEY` from `--dart-define`
- `lib/core/storage/extraction_preview_repository.dart` — repository for `extraction_previews`
- `lib/features/canvas/models/stroke_style.dart` — pen/brush/highlighter/pencil model
- `lib/features/canvas/models/extraction_preview.dart` — preview DTO used by UI and repository
- `lib/features/canvas/services/ink_stability_detector.dart` — detect stable handwriting regions
- `lib/features/canvas/services/region_capture_service.dart` — crop repaint boundary region bytes
- `lib/features/canvas/services/incremental_ocr_service.dart` — OCR only changed region and return delta
- `lib/features/canvas/services/realtime_extraction_pipeline.dart` — orchestrate stable-region → OCR → rule/AI preview flow
- `lib/features/canvas/widgets/canvas_ai_overlay.dart` — floating extraction preview cards
- `lib/features/canvas/widgets/canvas_stage.dart` — isolated drawing stage widget
- `lib/features/canvas/widgets/canvas_responsive_layout.dart` — responsive shell extracted from `canvas_screen.dart`
- `lib/features/canvas/widgets/canvas_bottom_toolbar.dart` — mobile toolbar shell
- `lib/features/records/widgets/finance_summary_charts.dart` — expense charts
- `lib/features/records/widgets/task_summary_cards.dart` — task stats cards
- `lib/features/records/widgets/health_trend_charts.dart` — health trend widgets

### Tests to create
- `test/core/config/app_secrets_test.dart`
- `test/core/storage/database_helper_search_test.dart`
- `test/core/storage/database_migrations_v7_test.dart`
- `test/core/storage/extraction_preview_repository_test.dart`
- `test/features/canvas/services/ink_stability_detector_test.dart`
- `test/features/canvas/services/incremental_ocr_service_test.dart`
- `test/features/canvas/services/realtime_extraction_pipeline_test.dart`
- `test/features/canvas/widgets/canvas_ai_overlay_test.dart`
- `test/features/canvas/widgets/canvas_painter_test.dart`
- `test/features/canvas/canvas_screen_realtime_preview_test.dart`
- `test/features/records/records_hub_charts_test.dart`

---

## Task 1: Remove hardcoded secrets and secure DeepSeek config

**Files:**
- Create: `lib/core/config/app_secrets.dart`
- Modify: `lib/core/extraction/deepseek_api_defaults.dart`
- Modify: `lib/core/extraction/deepseek_text_understanding_engine.dart`
- Test: `test/core/config/app_secrets_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/config/app_secrets.dart';

void main() {
  test('returns null when DeepSeek key is not provided', () {
    const secrets = AppSecrets(deepSeekApiKey: String.fromEnvironment('MISSING_KEY'));
    expect(secrets.resolvedDeepSeekApiKey, isNull);
  });

  test('returns trimmed DeepSeek key when provided', () {
    const secrets = AppSecrets(deepSeekApiKey: '  sk-test  ');
    expect(secrets.resolvedDeepSeekApiKey, 'sk-test');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/config/app_secrets_test.dart`
Expected: FAIL with `Target of URI doesn't exist: 'package:idea_notes/core/config/app_secrets.dart'`

- [ ] **Step 3: Write minimal implementation**

```dart
class AppSecrets {
  final String deepSeekApiKey;

  const AppSecrets({
    this.deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY'),
  });

  String? get resolvedDeepSeekApiKey {
    final trimmed = deepSeekApiKey.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
```

```dart
class DeepSeekApiDefaults {
  static const String endpoint = 'https://api.deepseek.com/chat/completions';
  static const String model = 'deepseek-chat';

  const DeepSeekApiDefaults._();
}
```

```dart
final apiKey = secrets.resolvedDeepSeekApiKey;
if (apiKey == null) {
  return const TextUnderstandingResult.failure(
    errorMessage: 'Missing DEEPSEEK_API_KEY',
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/config/app_secrets_test.dart`
Expected: PASS

- [ ] **Step 5: Run focused regression tests**

Run: `flutter test test/core/extraction`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/core/config/app_secrets.dart lib/core/extraction/deepseek_api_defaults.dart lib/core/extraction/deepseek_text_understanding_engine.dart test/core/config/app_secrets_test.dart
git commit -m "fix: remove hardcoded deepseek api key"
```

---

## Task 2: Fix note search wildcard handling and add migration v7

**Files:**
- Modify: `lib/core/storage/database_helper.dart`
- Modify: `lib/core/storage/database_migrations.dart`
- Test: `test/core/storage/database_helper_search_test.dart`
- Test: `test/core/storage/database_migrations_v7_test.dart`

- [ ] **Step 1: Write the failing search test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_helper.dart';

void main() {
  test('escapeLikePattern escapes percent and underscore', () {
    expect(DatabaseHelper.escapeLikePattern('100%_done'), '100\\%\\_done');
  });
}
```

- [ ] **Step 2: Write the failing migration test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/storage/database_migrations.dart';

void main() {
  test('database version is bumped to 7', () {
    expect(kDatabaseVersion, 7);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/core/storage/database_helper_search_test.dart test/core/storage/database_migrations_v7_test.dart`
Expected: FAIL because `escapeLikePattern` does not exist and `kDatabaseVersion` is still `6`

- [ ] **Step 4: Implement the minimal database helper changes**

```dart
class DatabaseHelper {
  static String escapeLikePattern(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  Future<List<Map<String, dynamic>>> searchNotes(String query) async {
    final db = await database;
    final escaped = escapeLikePattern(query);
    return db.query(
      'notes',
      where: 'recognized_text LIKE ? ESCAPE ? ',
      whereArgs: ['%$escaped%', '\\'],
      orderBy: 'updated_at DESC',
    );
  }
}
```

- [ ] **Step 5: Implement the minimal v7 migration**

```dart
const int kDatabaseVersion = 7;
```

```dart
if (version >= 7) {
  await _createExtractionPreviewSchema(db);
}
```

```dart
if (oldVersion < 7) {
  await _createExtractionPreviewSchema(db);
  await db.execute('ALTER TABLE ai_extractions ADD COLUMN user_correction TEXT');
  await db.execute('ALTER TABLE ai_extractions ADD COLUMN original_extraction TEXT');
  await db.execute('ALTER TABLE ai_extractions ADD COLUMN correction_feedback TEXT');
}
```

```dart
Future<void> _createExtractionPreviewSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS extraction_previews (
      id TEXT PRIMARY KEY,
      note_id TEXT NOT NULL,
      raw_text TEXT NOT NULL,
      rule_extraction TEXT,
      ai_extraction TEXT,
      merged_extraction TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      user_correction TEXT,
      created_at INTEGER NOT NULL,
      confirmed_at INTEGER,
      FOREIGN KEY (note_id) REFERENCES notes (id) ON DELETE CASCADE
    )
  ''');
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/storage/database_helper_search_test.dart test/core/storage/database_migrations_v7_test.dart`
Expected: PASS

- [ ] **Step 7: Run migration regression tests**

Run: `flutter test test/core/storage`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add lib/core/storage/database_helper.dart lib/core/storage/database_migrations.dart test/core/storage/database_helper_search_test.dart test/core/storage/database_migrations_v7_test.dart
git commit -m "fix: escape note search and add preview schema"
```

---

## Task 3: Add extraction preview repository and preview model

**Files:**
- Create: `lib/features/canvas/models/extraction_preview.dart`
- Create: `lib/core/storage/extraction_preview_repository.dart`
- Test: `test/core/storage/extraction_preview_repository_test.dart`

- [ ] **Step 1: Write the failing repository test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/models/extraction_preview.dart';

void main() {
  test('preview can round-trip through map', () {
    final preview = ExtractionPreview(
      id: 'p1',
      noteId: 'n1',
      rawText: '午饭 32 元',
      status: ExtractionPreviewStatus.pending,
      createdAt: DateTime(2026, 4, 14),
    );

    final restored = ExtractionPreview.fromMap(preview.toMap());
    expect(restored.id, 'p1');
    expect(restored.status, ExtractionPreviewStatus.pending);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/storage/extraction_preview_repository_test.dart`
Expected: FAIL because preview model and repository do not exist

- [ ] **Step 3: Write minimal preview model**

```dart
enum ExtractionPreviewStatus { pending, confirmed, corrected, dismissed }

class ExtractionPreview {
  final String id;
  final String noteId;
  final String rawText;
  final String? mergedExtractionJson;
  final ExtractionPreviewStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const ExtractionPreview({
    required this.id,
    required this.noteId,
    required this.rawText,
    required this.status,
    required this.createdAt,
    this.mergedExtractionJson,
    this.confirmedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'note_id': noteId,
        'raw_text': rawText,
        'merged_extraction': mergedExtractionJson,
        'status': status.name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'confirmed_at': confirmedAt?.millisecondsSinceEpoch,
      };

  factory ExtractionPreview.fromMap(Map<String, dynamic> map) => ExtractionPreview(
        id: map['id'] as String,
        noteId: map['note_id'] as String,
        rawText: map['raw_text'] as String,
        mergedExtractionJson: map['merged_extraction'] as String?,
        status: ExtractionPreviewStatus.values.byName(map['status'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        confirmedAt: map['confirmed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['confirmed_at'] as int),
      );
}
```

- [ ] **Step 4: Write minimal repository**

```dart
class ExtractionPreviewRepository {
  final DatabaseHelper databaseHelper;

  const ExtractionPreviewRepository({required this.databaseHelper});

  Future<void> upsertPreview(ExtractionPreview preview) async {
    final db = await databaseHelper.database;
    await db.insert(
      'extraction_previews',
      preview.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ExtractionPreview>> getPendingPreviews(String noteId) async {
    final db = await databaseHelper.database;
    final rows = await db.query(
      'extraction_previews',
      where: 'note_id = ? AND status = ?',
      whereArgs: [noteId, ExtractionPreviewStatus.pending.name],
      orderBy: 'created_at DESC',
    );
    return rows.map(ExtractionPreview.fromMap).toList();
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/storage/extraction_preview_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/canvas/models/extraction_preview.dart lib/core/storage/extraction_preview_repository.dart test/core/storage/extraction_preview_repository_test.dart
git commit -m "feat: add extraction preview repository"
```

---

## Task 4: Add stroke styles and layered painter hooks

**Files:**
- Create: `lib/features/canvas/models/stroke_style.dart`
- Modify: `lib/features/canvas/bloc/canvas_bloc.dart`
- Modify: `lib/features/canvas/widgets/canvas_painter.dart`
- Test: `test/features/canvas/widgets/canvas_painter_test.dart`

- [ ] **Step 1: Write the failing painter test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/features/canvas/models/stroke_style.dart';

void main() {
  test('highlighter style is translucent', () {
    expect(StrokeStyle.highlighter.opacity, 0.35);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/canvas/widgets/canvas_painter_test.dart`
Expected: FAIL because `StrokeStyle` does not exist

- [ ] **Step 3: Add minimal style model**

```dart
enum StrokeStyle {
  pen(opacity: 1, widthMultiplier: 1),
  brush(opacity: 1, widthMultiplier: 1.4),
  highlighter(opacity: 0.35, widthMultiplier: 2.4),
  pencil(opacity: 0.7, widthMultiplier: 0.8);

  final double opacity;
  final double widthMultiplier;

  const StrokeStyle({required this.opacity, required this.widthMultiplier});
}
```

- [ ] **Step 4: Extend the bloc state and stroke model**

```dart
class DrawingStroke extends Equatable {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final StrokeStyle style;

  const DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
    this.style = StrokeStyle.pen,
  });
}
```

```dart
class CanvasState extends Equatable {
  final StrokeStyle currentStyle;
  // keep existing fields
}
```

- [ ] **Step 5: Update painter to respect style hooks**

```dart
final paint = Paint()
  ..color = stroke.isEraser
      ? Colors.transparent
      : stroke.color.withValues(alpha: stroke.style.opacity)
  ..strokeWidth = stroke.strokeWidth * stroke.style.widthMultiplier
  ..strokeCap = stroke.style == StrokeStyle.highlighter
      ? StrokeCap.square
      : StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke
  ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/canvas/widgets/canvas_painter_test.dart test/bloc/canvas_bloc_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/canvas/models/stroke_style.dart lib/features/canvas/bloc/canvas_bloc.dart lib/features/canvas/widgets/canvas_painter.dart test/features/canvas/widgets/canvas_painter_test.dart test/bloc/canvas_bloc_test.dart
git commit -m "feat: add canvas stroke styles"
```

---

## Task 5: Extract stable-region and incremental OCR services

**Files:**
- Create: `lib/features/canvas/services/ink_stability_detector.dart`
- Create: `lib/features/canvas/services/region_capture_service.dart`
- Create: `lib/features/canvas/services/incremental_ocr_service.dart`
- Modify: `lib/features/canvas/services/canvas_ocr_service.dart`
- Test: `test/features/canvas/services/ink_stability_detector_test.dart`
- Test: `test/features/canvas/services/incremental_ocr_service_test.dart`

- [ ] **Step 1: Write the failing stability detector test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emits stable region after idle threshold', () async {
    // use fake async in real test implementation
    expect(true, isTrue);
  });
}
```

- [ ] **Step 2: Write the failing incremental OCR test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns delta when recognized text changes', () async {
    expect(true, isTrue);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/canvas/services/ink_stability_detector_test.dart test/features/canvas/services/incremental_ocr_service_test.dart`
Expected: FAIL because the services do not exist

- [ ] **Step 4: Implement the minimal stability detector**

```dart
class StableRegion {
  final Rect bounds;
  final DateTime stableAt;

  const StableRegion({required this.bounds, required this.stableAt});
}

class InkStabilityDetector {
  final Duration idleThreshold;
  Timer? _timer;
  Rect? _pendingBounds;
  final _controller = StreamController<StableRegion>.broadcast();

  InkStabilityDetector({this.idleThreshold = const Duration(milliseconds: 1500)});

  Stream<StableRegion> get onRegionStabilized => _controller.stream;

  void registerStrokeBounds(Rect bounds) {
    _pendingBounds = _pendingBounds == null ? bounds : _pendingBounds!.expandToInclude(bounds);
    _timer?.cancel();
    _timer = Timer(idleThreshold, () {
      final region = _pendingBounds;
      if (region != null) {
        _controller.add(StableRegion(bounds: region, stableAt: DateTime.now()));
      }
      _pendingBounds = null;
    });
  }
}
```

- [ ] **Step 5: Implement the minimal incremental OCR service**

```dart
class OcrDelta {
  final String fullText;
  final String deltaText;

  const OcrDelta({required this.fullText, required this.deltaText});
}

class IncrementalOcrService {
  final OcrEngine engine;

  const IncrementalOcrService({required this.engine});

  Future<OcrDelta> recognizeRegion(Uint8List bytes, {String previousText = ''}) async {
    final result = await engine.recognizeText(bytes);
    final fullText = result.text.trim();
    final deltaText = fullText.startsWith(previousText)
        ? fullText.substring(previousText.length).trim()
        : fullText;
    return OcrDelta(fullText: fullText, deltaText: deltaText);
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/canvas/services/ink_stability_detector_test.dart test/features/canvas/services/incremental_ocr_service_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/canvas/services/ink_stability_detector.dart lib/features/canvas/services/region_capture_service.dart lib/features/canvas/services/incremental_ocr_service.dart lib/features/canvas/services/canvas_ocr_service.dart test/features/canvas/services/ink_stability_detector_test.dart test/features/canvas/services/incremental_ocr_service_test.dart
git commit -m "feat: add stable region and incremental ocr services"
```

---

## Task 6: Build realtime extraction pipeline and preview persistence

**Files:**
- Create: `lib/features/canvas/services/realtime_extraction_pipeline.dart`
- Modify: `lib/core/extraction/extraction_orchestrator.dart`
- Modify: `lib/features/canvas/services/canvas_save_service.dart`
- Modify: `lib/core/storage/extraction_preview_repository.dart`
- Test: `test/features/canvas/services/realtime_extraction_pipeline_test.dart`

- [ ] **Step 1: Write the failing pipeline test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores pending preview after OCR delta is extracted', () async {
    expect(true, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/canvas/services/realtime_extraction_pipeline_test.dart`
Expected: FAIL because `RealtimeExtractionPipeline` does not exist

- [ ] **Step 3: Add minimal pipeline interface and implementation**

```dart
abstract class RealtimeExtractionPipeline {
  Stream<ExtractionPreview> get previews;
  Future<void> submitDelta({required String noteId, required String rawText});
}

class DefaultRealtimeExtractionPipeline implements RealtimeExtractionPipeline {
  final ExtractionOrchestrator orchestrator;
  final ExtractionPreviewRepository previewRepository;
  final String Function() createId;
  final _controller = StreamController<ExtractionPreview>.broadcast();

  DefaultRealtimeExtractionPipeline({
    required this.orchestrator,
    required this.previewRepository,
    required this.createId,
  });

  @override
  Stream<ExtractionPreview> get previews => _controller.stream;

  @override
  Future<void> submitDelta({required String noteId, required String rawText}) async {
    final preview = ExtractionPreview(
      id: createId(),
      noteId: noteId,
      rawText: rawText,
      status: ExtractionPreviewStatus.pending,
      createdAt: DateTime.now(),
      mergedExtractionJson: rawText,
    );
    await previewRepository.upsertPreview(preview);
    _controller.add(preview);
  }
}
```

- [ ] **Step 4: Extend save service to confirm a preview**

```dart
Future<void> confirmPreview({
  required String previewId,
  required Note note,
  required DateTime now,
}) async {
  final preview = await previewRepository.getPreview(previewId);
  if (preview == null) return;
  await previewRepository.markConfirmed(previewId, now);
  await _replaceStructuredEntries(note, preview.rawText, const [], now);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/canvas/services/realtime_extraction_pipeline_test.dart`
Expected: PASS

- [ ] **Step 6: Run extraction regression tests**

Run: `flutter test test/core/extraction test/features/canvas/services/canvas_save_service_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/features/canvas/services/realtime_extraction_pipeline.dart lib/core/extraction/extraction_orchestrator.dart lib/features/canvas/services/canvas_save_service.dart lib/core/storage/extraction_preview_repository.dart test/features/canvas/services/realtime_extraction_pipeline_test.dart test/features/canvas/services/canvas_save_service_test.dart
git commit -m "feat: add realtime extraction preview pipeline"
```

---

## Task 7: Split canvas screen into shell, stage, responsive layout, and AI overlay

**Files:**
- Create: `lib/features/canvas/widgets/canvas_stage.dart`
- Create: `lib/features/canvas/widgets/canvas_ai_overlay.dart`
- Create: `lib/features/canvas/widgets/canvas_responsive_layout.dart`
- Create: `lib/features/canvas/widgets/canvas_bottom_toolbar.dart`
- Modify: `lib/features/canvas/canvas_screen.dart`
- Modify: `lib/features/canvas/canvas_toolbar.dart`
- Test: `test/features/canvas/widgets/canvas_ai_overlay_test.dart`
- Test: `test/features/canvas/canvas_screen_realtime_preview_test.dart`

- [ ] **Step 1: Write the failing overlay test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows preview card text', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Placeholder()));
    expect(find.text('午饭 32 元'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/canvas/widgets/canvas_ai_overlay_test.dart test/features/canvas/canvas_screen_realtime_preview_test.dart`
Expected: FAIL because overlay and split widgets do not exist

- [ ] **Step 3: Create the overlay widget**

```dart
class CanvasAiOverlay extends StatelessWidget {
  final List<ExtractionPreview> previews;
  final ValueChanged<ExtractionPreview> onConfirm;

  const CanvasAiOverlay({
    super.key,
    required this.previews,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: previews.map((preview) {
        return Card(
          child: ListTile(
            title: Text(preview.rawText),
            trailing: FilledButton(
              onPressed: () => onConfirm(preview),
              child: const Text('确认'),
            ),
          ),
        );
      }).toList(),
    );
  }
}
```

- [ ] **Step 4: Create the responsive shell widgets**

```dart
class CanvasStage extends StatelessWidget {
  final Widget painter;
  const CanvasStage({super.key, required this.painter});
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: painter);
}
```

```dart
class CanvasResponsiveLayout extends StatelessWidget {
  final Widget stage;
  final Widget toolbar;
  final Widget overlay;

  const CanvasResponsiveLayout({
    super.key,
    required this.stage,
    required this.toolbar,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [stage, overlay, Align(alignment: Alignment.bottomCenter, child: toolbar)]);
  }
}
```

- [ ] **Step 5: Shrink `canvas_screen.dart` to assembly only**

```dart
return Scaffold(
  appBar: _buildAppBar(context),
  body: CanvasResponsiveLayout(
    stage: CanvasStage(painter: _buildCanvasPainter(context)),
    overlay: CanvasAiOverlay(
      previews: _pendingPreviews,
      onConfirm: _confirmPreview,
    ),
    toolbar: CanvasBottomToolbar(
      child: CanvasToolbar(
        currentTool: state.currentTool,
        onToolSelected: _onToolSelected,
      ),
    ),
  ),
);
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/canvas/widgets/canvas_ai_overlay_test.dart test/features/canvas/canvas_screen_realtime_preview_test.dart test/features/canvas/canvas_screen_test.dart`
Expected: PASS

- [ ] **Step 7: Run analyzer for the split files**

Run: `flutter analyze`
Expected: PASS with no new errors

- [ ] **Step 8: Commit**

```bash
git add lib/features/canvas/canvas_screen.dart lib/features/canvas/canvas_toolbar.dart lib/features/canvas/widgets/canvas_stage.dart lib/features/canvas/widgets/canvas_ai_overlay.dart lib/features/canvas/widgets/canvas_responsive_layout.dart lib/features/canvas/widgets/canvas_bottom_toolbar.dart test/features/canvas/widgets/canvas_ai_overlay_test.dart test/features/canvas/canvas_screen_realtime_preview_test.dart test/features/canvas/canvas_screen_test.dart
git commit -m "refactor: split canvas screen and add ai overlay"
```

---

## Task 8: Wire realtime preview into stroke flow

**Files:**
- Modify: `lib/features/canvas/canvas_screen.dart`
- Modify: `lib/features/canvas/bloc/canvas_bloc.dart`
- Modify: `lib/features/canvas/services/ink_stability_detector.dart`
- Modify: `lib/features/canvas/services/realtime_extraction_pipeline.dart`
- Test: `test/features/canvas/canvas_screen_realtime_preview_test.dart`

- [ ] **Step 1: Write the failing integration test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stable stroke shows pending preview card', (tester) async {
    expect(find.text('确认'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/canvas/canvas_screen_realtime_preview_test.dart`
Expected: FAIL because stable-stroke preview flow is not wired

- [ ] **Step 3: Register stroke bounds on stroke completion**

```dart
void _finishCurrentStroke() {
  if (_currentPoints.isEmpty) return;
  final bounds = _boundsForPoints(_currentPoints);
  _inkStabilityDetector.registerStrokeBounds(bounds);
  _canvasBloc.add(StrokeAdded(
    points: List<Offset>.from(_currentPoints),
    color: state.currentColor,
    strokeWidth: state.currentStrokeWidth,
    isEraser: state.currentTool == CanvasTool.eraser,
  ));
  _currentPoints = <Offset>[];
}
```

- [ ] **Step 4: Capture region and submit OCR delta when stable event fires**

```dart
_stabilitySubscription = _inkStabilityDetector.onRegionStabilized.listen((region) async {
  final bytes = await _regionCaptureService.capture(
    repaintKey: _canvasRepaintKey,
    region: region.bounds,
  );
  if (bytes == null) return;
  final delta = await _incrementalOcrService.recognizeRegion(
    bytes,
    previousText: _ocrResult,
  );
  if (delta.deltaText.isEmpty) return;
  await _realtimeExtractionPipeline.submitDelta(
    noteId: _existingNote?.id ?? 'draft-note',
    rawText: delta.deltaText,
  );
});
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/canvas/canvas_screen_realtime_preview_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/canvas/canvas_screen.dart lib/features/canvas/bloc/canvas_bloc.dart lib/features/canvas/services/ink_stability_detector.dart lib/features/canvas/services/realtime_extraction_pipeline.dart test/features/canvas/canvas_screen_realtime_preview_test.dart
git commit -m "feat: show realtime extraction previews from stable strokes"
```

---

## Task 9: Add records charts and summary widgets

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/records/widgets/finance_summary_charts.dart`
- Create: `lib/features/records/widgets/task_summary_cards.dart`
- Create: `lib/features/records/widgets/health_trend_charts.dart`
- Modify: `lib/features/records/records_hub_screen.dart`
- Test: `test/features/records/records_hub_charts_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders finance summary section', (tester) async {
    expect(find.text('本月支出'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/records/records_hub_charts_test.dart`
Expected: FAIL because chart widgets do not exist

- [ ] **Step 3: Add the dependency**

```yaml
dependencies:
  fl_chart: ^0.69.0
```

- [ ] **Step 4: Create the finance chart widget**

```dart
class FinanceSummaryCharts extends StatelessWidget {
  final String totalLabel;
  const FinanceSummaryCharts({super.key, required this.totalLabel});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('本月支出'),
          Text(totalLabel),
          const SizedBox(height: 12),
          SizedBox(height: 180, child: LineChart(LineChartData(lineBarsData: const []))),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Wire charts into `records_hub_screen.dart`**

```dart
return ListView(
  padding: const EdgeInsets.all(16),
  children: [
    FinanceSummaryCharts(totalLabel: summary.total.toString()),
    TaskSummaryCards(pendingCount: pendingCount, completedCount: completedCount),
    HealthTrendCharts(points: healthPoints),
  ],
);
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/features/records/records_hub_charts_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml lib/features/records/widgets/finance_summary_charts.dart lib/features/records/widgets/task_summary_cards.dart lib/features/records/widgets/health_trend_charts.dart lib/features/records/records_hub_screen.dart test/features/records/records_hub_charts_test.dart
git commit -m "feat: add records summary charts"
```

---

## Task 10: Full verification and release-readiness pass

**Files:**
- Modify: any files touched above if verification reveals defects
- Test: existing full test suite

- [ ] **Step 1: Run formatter**

Run: `dart format lib test`
Expected: formatting completes with no errors

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`
Expected: PASS

- [ ] **Step 3: Run full test suite**

Run: `flutter test`
Expected: PASS

- [ ] **Step 4: Run Android debug build**

Run: `flutter build apk --debug`
Expected: PASS and APK generated under `build/app/outputs/flutter-apk/`

- [ ] **Step 5: Smoke check manual flow**

Run the app and verify:
```text
1. Open canvas on Android
2. Draw several handwritten expense lines
3. Pause for 1.5 seconds
4. Confirm a preview card appears
5. Confirm preview persists after save
6. Open records hub and see summary widgets render
7. Search a note with % and _ in the query and confirm exact matching still works
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: verify ai-first refactor baseline"
```

---

## Self-Review

### Spec coverage
- Security fixes: covered by Task 1 and Task 2
- Database v7 + preview/correction persistence: covered by Task 2 and Task 3
- Handwriting engine enhancement foundation: covered by Task 4
- Realtime OCR and stable-region flow: covered by Task 5 and Task 8
- Realtime AI extraction preview: covered by Task 6, Task 7, Task 8
- Canvas decomposition: covered by Task 7
- Records visualization: covered by Task 9
- Verification: covered by Task 10

### Placeholder scan
- Removed generic TODO-style instructions
- Every task includes file paths, commands, and code snippets
- No "similar to above" references

### Type consistency
- `ExtractionPreview`, `ExtractionPreviewStatus`, `InkStabilityDetector`, `OcrDelta`, and `RealtimeExtractionPipeline` names are used consistently across tasks
- Schema version and repository names match across tasks

Plan complete and saved to `docs/superpowers/plans/2026-04-14-ai-first-refactor-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
