# IdeaNotes 代码评审报告

> 基于 NoteArt 原始设计文档 (`2026-02-23-noteapp-design.md` + `2026-02-23-noteapp-implementation-plan.md`) 对 IdeaNotes Flutter 重构版本的评审。
> 本文档用于交给 AI 模型执行修复和改进。

---

## 一、平台与技术栈变更（已确认的合理偏差）

以下变更属于从 iPadOS/Swift 重构到 Flutter 的预期改动，**不需要修正**：

| 原设计 | IdeaNotes 实现 | 状态 |
|--------|---------------|------|
| iPadOS only | Flutter 跨平台 | ✅ 合理 |
| SwiftUI + MVVM | Flutter + BLoC | ✅ 合理 |
| PencilKit | CustomPainter + GestureDetector | ✅ 合理 |
| Core Data | SQLite (sqflite) | ✅ 合理 |
| Apple Vision OCR | Google ML Kit + Apple Vision 双引擎 | ✅ 合理 |
| 零第三方依赖 | Flutter 生态必要依赖 | ✅ 合理 |

---

## 二、严重问题（必须修复）

### 2.1 金额使用 `double` 而非 `Decimal`

**文件**: `lib/core/models/note_entry.dart:31`，`lib/core/storage/database_helper.dart:59`

**设计文档要求**: "Use Decimal for monetary amounts. NEVER use Float or Double for money."

**当前实现**: `ExpenseRecord.amount` 类型为 `double`，数据库中 `amount` 列类型为 `REAL`。

**修复指令**:
1. 在 `pubspec.yaml` 添加 `decimal: ^2.3.3` 依赖
2. `ExpenseRecord.amount` 改为 `Decimal` 类型
3. 数据库 `amount` 列改为 `TEXT` 存储（SQLite 没有原生 Decimal，用文本存储后解析）
4. 更新 `ExpenseExtractor` 返回 `Decimal`
5. 更新所有引用 `amount` 的 UI 代码

### 2.2 保存功能未实现（仅 TODO 占位）

**文件**: `lib/features/canvas/canvas_screen.dart:156-162`

`_saveNote()` 方法只弹了一个 SnackBar，**没有实际保存画布数据、快照、OCR 文本到数据库**。这是 MVP 核心功能。

**修复指令**:
1. 在 `_saveNote()` 中：
   - 将当前 `CanvasBloc` 的 `strokes` 序列化为 `Uint8List`（canvas BLOB）
   - 使用 `screenshot` 包或 `RepaintBoundary` 捕获画布为图片
   - 调用 `ImageStorage.saveSnapshot()` 保存快照 PNG
   - 调用 `ImageStorage.saveThumbnail()` 生成并保存 200x200 缩略图
   - 将 note 数据（canvasData, snapshotImagePath, recognizedText）通过 `DatabaseHelper.insertNote()` 写入数据库
   - 如果有 OCR 结果，调用 `EntryParser.parseMultiLine()` 后批量 `insertNoteEntry()`
2. 保存完成后触发 `NoteListBloc.add(RefreshNotes())` 刷新列表

### 2.3 OCR 功能未实现（仅模拟数据）

**文件**: `lib/features/canvas/canvas_screen.dart:164-177`

`_runOcr()` 只返回硬编码字符串，未调用任何 OCR 引擎。

**修复指令**:
1. 在 `CanvasScreen` 中注入 `OcrEngine` 实例（通过 `OcrEngineFactory` 按平台创建）
2. 捕获画布为 `UIImage`/`File`，调用 `ocrEngine.recognizeText()` 或 `recognizeTextFromFile()`
3. 将识别结果更新到 `_ocrResult` 状态
4. 识别完成后调用 `EntryParser.parseMultiLine()` 生成结构化条目并展示
5. 错误处理：OCR 失败时显示 "识别失败，请重试"

### 2.4 编辑笔记（重新打开已保存笔记）未实现

**文件**: `lib/features/canvas/canvas_screen.dart`

`CanvasScreen` 接受 `noteId` 参数，但从未用它从数据库加载已有笔记数据并还原到画布。

**修复指令**:
1. 在 `initState` 中检查 `widget.noteId`，如果非 null 则从 `DatabaseHelper.getNote(noteId)` 加载数据
2. 反序列化 `canvasData` BLOB 为 `List<DrawingStroke>` 并通过 `CanvasBloc` 恢复
3. 加载已有的 `recognizedText` 到 OCR 结果区域
4. 保存时区分 `insertNote` vs `updateNote`

### 2.5 NoteListBloc 创建笔记使用 timestamp 作为 ID

**文件**: `lib/features/notelist/bloc/note_list_bloc.dart`

设计文档要求使用 UUID 作为 ID，当前使用 `DateTime.now().millisecondsSinceEpoch` 转为字符串，在快速操作时可能产生 ID 冲突。

**修复指令**:
使用 `uuid` 包（已在 `pubspec.yaml` 中声明）生成 UUID 作为 note ID。

---

## 三、中等问题（应该修复）

### 3.1 CanvasScreen 创建了独立的 CanvasBloc，与 app.dart 的全局 CanvasBloc 冲突

**文件**: `lib/features/canvas/canvas_screen.dart:33`，`lib/app/app.dart`

`app.dart` 在 `MultiBlocProvider` 中已提供了全局 `CanvasBloc`，但 `CanvasScreen` 又 `BlocProvider(create: ... CanvasBloc())` 创建了一个局部的。这导致全局实例永远不被使用。

**修复指令**:
二选一：
- **方案 A（推荐）**：删除 `app.dart` 中的全局 `CanvasBloc` Provider，因为画布状态应该跟随画布页面生命周期
- **方案 B**：`CanvasScreen` 使用 `context.read<CanvasBloc>()` 而不是创建新实例，但需要在每次进入画布时重置状态

### 3.2 搜索未实现防抖

**文件**: `lib/features/search/search_screen.dart`

设计文档要求 "Debounce search input by 300ms"。但 `search_screen.dart` 虽然有 300ms Timer，搜索实际通过 `NoteListBloc` 执行，而 `NoteListBloc.SearchNotes` 事件没有任何防抖，直接查数据库。

**修复指令**:
确认 `SearchScreen` 中 Timer 防抖逻辑是否正确连接。在 `NoteListBloc` 中使用 `bloc_concurrency` 的 `restartable()` transformer 或在 UI 层确保 Timer 正常工作。

### 3.3 画布缺少贝塞尔曲线平滑

**文件**: `lib/features/canvas/canvas_screen.dart:273-278`

`_CanvasPainter._drawStroke()` 使用 `lineTo` 直线连接点，线条会有明显锯齿。而 `widgets/canvas_painter.dart` 中的 `CanvasPainter` 已实现贝塞尔曲线平滑。

**修复指令**:
`CanvasScreen` 中的 `_CanvasPainter` 应使用 `quadraticBezierTo` 平滑绘制，参考 `widgets/canvas_painter.dart` 的实现。或者直接复用 `CanvasPainter`，避免重复代码。

### 3.4 缺少事件关键词检测

**文件**: `lib/core/parser/entry_parser.dart:60-86`

设计文档要求："Lines containing task keywords (记得, 要, 需要, 别忘了) → type event"。当前实现只匹配了时间关键词（明天、下周等），没有匹配任务关键词。

**修复指令**:
在 `_tryParseEvent()` 中增加对 `记得`、`要`、`需要`、`别忘了` 等关键词的匹配，匹配到时返回 `event` 类型（date 可为 null）。

### 3.5 数据库缺少级联删除实际执行

**文件**: `lib/core/storage/database_helper.dart`

虽然 SQL 定义了 `ON DELETE CASCADE`，但 sqflite 默认**不启用外键约束**。

**修复指令**:
在 `_initDB` 的 `openDatabase` 回调中添加：
```dart
onOpen: (db) async {
  await db.execute('PRAGMA foreign_keys = ON');
},
```

### 3.6 笔记删除时未清理图片文件

**文件**: `lib/features/notelist/bloc/note_list_bloc.dart`

`DeleteNote` 事件只调用 `databaseHelper.deleteNote(id)`，没有调用 `ImageStorage.deleteNoteImages()` 清理对应的快照和缩略图文件。

**修复指令**:
在 `_onDeleteNote` 中，删除数据库记录前先调用 `ImageStorage.deleteNoteImages(event.noteId)` 删除图片文件。

### 3.7 画布 eraser 使用白色覆盖而非真正擦除

**文件**: `lib/features/canvas/canvas_screen.dart:260`

橡皮擦只是用白色画线覆盖，导出的图片上擦除区域仍然有白色笔画。`widgets/canvas_painter.dart` 使用了 `BlendMode.clear` 实现真正擦除。

**修复指令**:
在 `_CanvasPainter._drawStroke()` 中，当 `stroke.isEraser` 为 true 时使用 `BlendMode.clear`，并确保画布使用 `saveLayer`/`restore` 正确处理混合模式。

---

## 四、轻微问题（建议修复）

### 4.1 OCR 编辑对话框未保存修改结果

**文件**: `lib/features/canvas/canvas_screen.dart:186-209`

`_editOcrResult()` 打开编辑对话框，但点击"保存"后没有将 `TextEditingController` 的值写回 `_ocrResult`。

**修复指令**:
保存按钮的 `onPressed` 中获取 controller 的文本并 `setState(() { _ocrResult = controller.text; })`。

### 4.2 `_parseDate` 中 "大后天" 永远不会匹配

**文件**: `lib/core/parser/entry_parser.dart:93-104`

代码先检查 `text.contains('后天')`，再检查 `text.contains('大后天')`。由于"大后天"包含"后天"子串，"大后天"永远会先被"后天"匹配走。

**修复指令**:
将 `大后天` 的检查移到 `后天` 之前。同理，`下下周` 应在 `下周` 之前检查（当前已正确使用正则，但建议改为先匹配长模式）。

### 4.3 复制到剪贴板功能未实现

**文件**: `lib/features/canvas/canvas_screen.dart:179-183`

`_copyOcrResult()` 只弹 SnackBar，没有真正调用 `Clipboard.setData()`。

**修复指令**:
```dart
import 'package:flutter/services.dart';
Clipboard.setData(ClipboardData(text: _ocrResult));
```

### 4.4 缺少 `周X` 关键词匹配

设计文档要求匹配 `周X` 作为事件日期关键词。当前只匹配了 `下周X` 和 `下下周X`，没有匹配 `这周X` 或单独的 `周X`。

**修复指令**:
在 `_parseDate` 中增加 `周X`（本周某天）的匹配逻辑。

### 4.5 UI 未完全实现中文本地化

**文件**: 多个 UI 文件

大部分 UI 字符串已使用中文，但仍有英文残留（如 AppBar 按钮 tooltip、错误信息等）。设计文档要求 "All UI strings in Chinese (zh-Hans)"。

**修复指令**:
全局搜索 UI 文件中的英文字符串并替换为中文。

---

## 五、缺失功能清单（MVP 范围内应实现但完全缺失）

| # | 功能 | 设计文档要求 | 当前状态 |
|---|------|-------------|---------|
| 1 | **画布数据序列化/反序列化** | canvasData 存为 BLOB | 完全缺失，无法保存/恢复笔画 |
| 2 | **快照生成** | 画布截图为 PNG | 完全缺失 |
| 3 | **缩略图生成** | 200x200 PNG | 完全缺失 |
| 4 | **OCR 实际调用** | 手动触发识别 | 仅模拟数据 |
| 5 | **结构化条目存储** | note_entries 表 | 解析器就绪，但未接入保存流程 |
| 6 | **条目编辑** | 用户可修改解析结果 | 完全缺失 |
| 7 | **笔记编辑（重新打开）** | 加载已保存笔记到画布 | 完全缺失 |
| 8 | **删除确认弹窗** | 滑动删除需确认 | `note_list_item.dart` 有确认，✅ 已实现 |

---

## 六、执行优先级建议

按以下顺序修复，每一步应能编译通过并保持现有功能不退化：

1. **修复 `PRAGMA foreign_keys = ON`**（3.5）— 一行代码
2. **修复"大后天"匹配顺序**（4.2）— 几行改动
3. **修复事件关键词缺失**（3.4）— 小改动
4. **修复 NoteListBloc ID 生成**（2.5）— 小改动
5. **实现画布数据序列化**（五-1）— 定义 `DrawingStroke` 的 `toJson`/`fromJson`
6. **实现快照 + 缩略图生成**（五-2, 五-3）— 使用 `RepaintBoundary` + `RenderRepaintBoundary.toImage()`
7. **实现完整保存流程**（2.2）— 串联序列化 + 快照 + 数据库
8. **实现笔记加载/编辑**（2.4）— 反序列化 + 画布恢复
9. **接入 OCR 引擎**（2.3）— 连接已有的 `MlKitOcr`/`VisionOcr`
10. **修复 CanvasBloc 作用域**（3.1）— 架构调整
11. **修复金额 Decimal 类型**（2.1）— 涉及多文件
12. **修复画布绘制平滑 + 橡皮擦**（3.3, 3.7）— 复用 `CanvasPainter`
13. **实现图片清理 + 剪贴板复制 + OCR 编辑保存等**（3.6, 4.1, 4.3）— 零散修复
14. **中文本地化检查**（4.5）— 最后清理

---

## 七、测试情况

**已有测试（质量较好）**:
- `test/parser/entry_parser_test.dart` — 30+ 用例，覆盖费用/事件/备忘解析
- `test/parser/expense_extractor_test.dart` — 40+ 用例，覆盖金额提取和分类匹配

**缺失测试**:
- 数据库 CRUD 操作（`DatabaseHelper` 单元测试）
- `ImageStorage` 文件操作测试
- Widget 测试（当前只有一个 smoke test）
- 保存/加载笔记的集成测试
- BLoC 状态管理测试（`CanvasBloc`, `NoteListBloc`）

设计文档要求 `Core/Parser/` 目录 80%+ 覆盖率，当前 Parser 测试较充分，基本满足。建议补充 BLoC 和数据库测试。
