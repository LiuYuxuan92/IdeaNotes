# IdeaNotes AI-First Refactor Design

**Date**: 2026-04-14
**Status**: Draft
**Scope**: Large — Full handwriting engine + AI extraction overhaul
**Target Platform**: Android-first

## 1. Executive Summary

IdeaNotes 是一款 Flutter 手写笔记应用，集成 OCR + AI 结构化数据提取，自动从手写内容中提取财务/任务/健康记录。当前的核心流程是"手写 → 保存 → OCR → AI 提取"，用户需要手动触发且延迟高。

本次重构将产品转型为 **AI-First 实时体验**：边写边识别、边识别边提取、边提取边展示。通过实时 OCR + 流式 AI 提取 + 用户反馈闭环，将 IdeaNotes 的差异化核心竞争力从"有这个功能"提升到"体验极佳"。

## 2. Competitive Gap Summary

### Unique Position
市面上没有一款应用将 **手写输入 + OCR + AI 提取为结构化记录（费用/任务/健康）** 整合在一个应用中。这是 IdeaNotes 的真正差异化。

### Key Competitive Gaps to Close
| Area | Current State | Target |
|------|--------------|--------|
| Handwriting feel | Basic Flutter canvas | Pressure sensitivity, stroke variety, low latency |
| AI extraction timing | Manual, post-save | Real-time, incremental, streaming |
| Extraction accuracy | Single-shot DeepSeek | Multi-tier (local rules + cloud AI), user feedback loop |
| Result visualization | Simple lists | Charts, trends, interactive dashboards |
| Canvas screen | 1989-line monolith | Modular, testable components |

### Competitive Threats
- **华为 XiaoYi**：已深度整合中文 AI，有设备预装优势，若加入结构化提取会威胁核心差异化
- **GoodNotes/Notability**：手写引擎领先，若加入 AI 提取会威胁定位
- **Speed to market is critical**: 需要尽快将"功能有"升级为"体验好"

## 3. Core Flow Redesign

### Current Flow
```
User writes on canvas → Taps save → Canvas screenshot → OCR (ML Kit) →
Rule engine + DeepSeek extraction → Merge → Store to DB
```

### New Flow
```
User writes on canvas
  ↓ (ink stability detection: pause > 1.5s in a region)
Region screenshot → Incremental OCR
  ↓ (text change detection vs. previous buffer)
Local rule matching (< 100ms)
  ↓ (for complex content)
DeepSeek streaming API (async, SSE)
  ↓
Preview card updates in real-time
  ↓ (user taps confirm or edits)
Structured record stored to DB
  ↓
Correction feedback saved to ai_extractions
  ↓ (used as few-shot context next time)
AI accuracy improves over time
```

### Tiered Processing Strategy
| Scenario | Processing | Latency Target | Cost |
|----------|-----------|---------------|------|
| Amounts, dates, simple patterns | Local rule engine | <100ms | Free |
| Category classification, multi-line | DeepSeek Chat | 1-3s | Low |
| Complex multi-entry correlation | DeepSeek Reasoner | 3-5s | Medium |
| OCR text correction | DeepSeek Chat | 0.5-1s | Low |

## 4. Handwriting Engine Enhancement

### 4.1 Pressure Sensitivity (Android)
- Access Android MotionEvent pressure data via MethodChannel
- Map pressure to stroke width: lightweight press → thin line, heavy press → thick line
- Configurable sensitivity curve (linear, logarithmic, custom)
- Fallback for devices without pressure support (velocity-based width mapping)

### 4.2 Stroke Effects
- **Pen nib**: Uniform width + entry/exit tapering based on velocity
- **Brush**: Pressure + velocity dual mapping, simulating calligraphy
- **Highlighter**: Semi-transparent wide stroke with blend mode
- **Pencil**: Textured stroke effect using noise-based alpha variation

### 4.3 Latency Optimization
- **Input prediction**: Predict next-frame position based on movement direction and velocity
- **Incremental rendering**: Double-buffer architecture — completed strokes cached as image, only current stroke rendered in real-time
- **120Hz adaptation**: Ensure rendering pipeline can keep up with high refresh rate displays
- **Event batching**: Batch touch events to reduce GC pressure from `_onPanUpdate` point list copies

### 4.4 CanvasPainter Refactor
- Current: Full repaint of all strokes on every frame
- New: Layer-based rendering
  - Background layer (cached image)
  - Completed strokes layer (cached image, updated only on stroke end)
  - Active stroke layer (real-time rendering)
  - UI overlay layer (toolbars, AI preview cards)

## 5. AI Extraction System Upgrade

### 5.1 Real-time Extraction Pipeline
New service: `RealtimeExtractionPipeline`
```
InkStabilityDetector → RegionCaptureService → IncrementalOcrService
                                                     ↓
                                           TextChangeDetector
                                                     ↓
                                           TieredExtractionRouter
                                           ├─ RuleEngine (local, <100ms)
                                           └─ CloudAiExtractor (async, streaming)
                                                     ↓
                                           ExtractionResultMerger
                                                     ↓
                                           PreviewCardUpdater
```

### 5.2 Ink Stability Detection
- Track stroke timestamps per canvas region (grid-based segmentation)
- When a region has no new strokes for a configurable threshold (default: 1.5s), trigger OCR
- Adaptive threshold: shorter for text-heavy regions, longer for drawing regions

### 5.3 Incremental OCR
- Only capture and OCR the changed region (not full canvas)
- Compare new OCR text with previous buffer
- Only send delta text to extraction pipeline

### 5.4 Prompt Engineering Optimization
- **Incremental context**: Send only new/changed text with previous extraction summary
- **Few-shot learning**: Include user corrections from `ai_extractions` as examples
- **Confidence thresholds**: Low-confidence results flagged for user confirmation
- **Domain-specific prompts**: Different prompts for finance, health, task domains

### 5.5 User Feedback Loop
- Extraction preview cards support inline editing (tap to correct amount, category, date)
- Corrections stored in `ai_extractions` table with new `user_correction` and `original_extraction` fields
- Next extraction: query recent corrections for same category as few-shot context
- Analytics dashboard shows correction rate trend (should decrease over time)

### 5.6 Visualization Enhancements
- **Finance tab**: Monthly expense trend (line chart), category breakdown (pie chart), budget comparison (bar chart)
- **Tasks tab**: Completion rate stats, timeline/Gantt view, overdue alerts
- **Health tab**: Trend line charts for recurring metrics, anomaly markers
- Use `fl_chart` package for all charts

## 6. Architecture Refactoring

### 6.1 Canvas Screen Decomposition
Split `canvas_screen.dart` (1989 lines) into:
| File | Responsibility | Est. Lines |
|------|---------------|------------|
| `canvas_screen.dart` | Assembly, coordination, responsive layout | ~300 |
| `canvas_gesture_handler.dart` | Touch event handling, ink stability detection | ~250 |
| `canvas_ai_overlay.dart` | AI preview cards, confirmation UI | ~200 |
| `canvas_responsive_layout.dart` | Compact/Medium/Large layout adaptation | ~150 |
| `canvas_toolbar.dart` | Enhanced toolbar with new pen types (already exists, extend) | ~200 |

### 6.2 Dependency Injection
- Introduce simple DI container (manual or `get_it`)
- Register: DatabaseHelper, EntryRepository, OcrEngine, TextUnderstandingEngine, ExtractionPipeline
- Replace all `DatabaseHelper.instance` calls with injected dependency
- Enables testing with mock dependencies and future multi-engine switching

### 6.3 Event-Driven Architecture
- Introduce lightweight event bus for pipeline decoupling
- Events: `InkStabilized`, `OcrCompleted`, `ExtractionReady`, `UserConfirmedEntry`
- Handlers: pipeline stages subscribe to relevant events
- Enables independent testing and easy addition of new pipeline stages

### 6.4 New Service Interfaces
```dart
abstract class InkStabilityDetector {
  Stream<StableRegion> get onRegionStabilized;
}

abstract class IncrementalOcrService {
  Future<OcrDelta> recognizeRegion(Region region, String? previousText);
}

abstract class RealtimeExtractionPipeline {
  Stream<ExtractionPreview> get onExtractionReady;
  void submitTextDelta(OcrDelta delta);
}

abstract class ExtractionPreviewRepository {
  Stream<List<ExtractionPreview>> watchPreviews(String noteId);
  void confirmPreview(String previewId, ExtractionEntry confirmed);
  void correctPreview(String previewId, ExtractionEntry corrected);
}
```

## 7. Security Fixes (Prerequisite)

### P0-1: API Key Hardcoded
- Remove `sk-6c543564507b4918ad2c810967d34f50` from `deepseek_api_defaults.dart`
- Load from environment variable `DEEPSEEK_API_KEY` or Flutter secure storage
- Add `.env` to `.gitignore`
- Provide fallback for development: `--dart-define=DEEPSEEK_API_KEY=xxx`

### P0-2: SQL LIKE Wildcard Injection
- Escape `%` and `_` in user input within `searchNotes` in `database_helper.dart`
- Add parameterized escaping utility

## 8. Database Schema Changes

### New Tables
```sql
-- Extraction preview queue (pre-confirmation)
CREATE TABLE extraction_previews (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL REFERENCES notes(id),
  raw_text TEXT NOT NULL,
  rule_extraction TEXT, -- JSON
  ai_extraction TEXT,   -- JSON
  merged_extraction TEXT, -- JSON
  status TEXT NOT NULL DEFAULT 'pending', -- pending, confirmed, corrected, dismissed
  user_correction TEXT,  -- JSON of user's correction
  created_at TEXT NOT NULL,
  confirmed_at TEXT,
  FOREIGN KEY (note_id) REFERENCES notes(id)
);

-- AI learning feedback (extends ai_extractions)
ALTER TABLE ai_extractions ADD COLUMN user_correction TEXT;
ALTER TABLE ai_extractions ADD COLUMN original_extraction TEXT;
ALTER TABLE ai_extractions ADD COLUMN correction_feedback TEXT;
```

### Migration Version
Bump from v6 to v7. Include backfill for existing `ai_extractions` rows.

## 9. Implementation Phases

### Phase 1: Foundation (Security + Decomposition)
- P0 security fixes
- canvas_screen.dart decomposition
- DI container setup
- Event bus introduction
- Database migration to v7

### Phase 2: Handwriting Engine
- Pressure sensitivity (Android MethodChannel)
- Stroke effects (pen, brush, highlighter, pencil)
- Double-buffer CanvasPainter
- Input prediction and latency optimization
- Enhanced toolbar with stroke type selection

### Phase 3: Real-time AI Pipeline
- Ink stability detector
- Region capture service
- Incremental OCR service
- RealtimeExtractionPipeline with tiered routing
- Preview card UI (pending/confirmed/corrected states)

### Phase 4: AI Intelligence
- User feedback loop (correction → few-shot learning)
- Prompt engineering optimization (incremental context, domain-specific)
- Multi-model tiered strategy
- Correction rate analytics

### Phase 5: Visualization & Polish
- fl_chart integration for records hub
- Finance charts (trend, pie, bar)
- Task statistics and timeline
- Health trend charts
- Dark mode support
- Performance profiling and optimization

## 10. Testing Strategy

### New Test Categories
- **Handwriting engine tests**: Pressure mapping, stroke rendering, latency benchmarks
- **Pipeline integration tests**: End-to-end from ink stability to preview card
- **AI accuracy tests**: Regression tests with known inputs/expected outputs
- **Migration tests**: v6 → v7 with backfill verification

### Test Infrastructure
- Golden tests for canvas rendering
- Mock MethodChannel for pressure sensitivity testing
- Recorded DeepSeek responses for deterministic AI tests

## 11. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-----------|--------|------------|
| Real-time OCR performance on low-end devices | Medium | High | Tiered: only run on capable devices, fallback to manual trigger |
| DeepSeek API rate limiting during real-time use | Medium | High | Local rule engine as primary, cloud AI as enhancement; request queuing with backoff |
| Flutter Canvas performance ceiling for GoodNotes-level handwriting | Medium | Medium | Optimize within Flutter first; evaluate native Platform View if insufficient |
| User correction feedback not improving AI accuracy | Low | Medium | Monitor correction rate metrics; tune few-shot selection algorithm |
| Migration data loss (v6 → v7) | Low | Critical | Comprehensive migration tests; backup before migration |

## 12. Success Metrics

| Metric | Current | Target (3 months) |
|--------|---------|-------------------|
| Handwriting latency (frame time) | ~16ms (60Hz) | <8ms (120Hz) |
| Time from writing to extraction preview | Manual save + 5-10s | Auto <3s after ink stabilizes |
| AI extraction accuracy (no correction needed) | Unknown | >85% |
| User correction rate | Unknown | <20% and decreasing |
| Canvas screen file size | 1989 lines | <400 lines per file |
| Test coverage of new pipeline code | N/A | >80% |
