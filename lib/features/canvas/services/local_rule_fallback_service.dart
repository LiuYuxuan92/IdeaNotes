import 'package:uuid/uuid.dart';

import '../../../core/extraction/extraction_models.dart';
import '../../../core/models/note.dart';
import '../../../core/models/note_entry.dart';
import '../../../core/parser/entry_parser.dart';
import 'canvas_ai_preview_service.dart';

/// 当 AI 不可用 / 调用失败时，用本地规则解析器（[EntryParser]）做兜底。
///
/// 把识别文本按行拆分，逐行规则解析，再把结果转成与 AI 通路一致的
/// [NormalizedExtractionDocument] / [CanvasAiPreviewResult]，使下游 UI
/// 与持久化都不需要分支处理。
class LocalRuleFallbackService {
  final String timezone;
  final String locale;
  final Uuid _uuid;

  LocalRuleFallbackService({
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  CanvasAiPreviewResult buildPreview({
    required Note? existingNote,
    required String recognizedText,
    required DateTime now,
    String? upstreamErrorMessage,
  }) {
    final normalized = recognizedText.trim();
    final lines = normalized
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);

    final extracted = <ExtractedEntry>[];
    if (lines.isEmpty && normalized.isNotEmpty) {
      final entry = _toExtractedEntry(EntryParser.parse(normalized), now);
      if (entry != null) extracted.add(entry);
    } else {
      for (final line in lines) {
        final entry = _toExtractedEntry(EntryParser.parse(line), now);
        if (entry != null) extracted.add(entry);
      }
    }

    final noteContext = ExtractionNoteContext(
      noteId: existingNote?.id ?? 'fallback-${now.millisecondsSinceEpoch}',
      noteCreatedAt: existingNote?.createdAt ?? now,
      timezone: timezone,
      locale: locale,
    );
    final ocrSummary = ExtractionOcrSummary(
      fullText: normalized,
      lineCount: lines.isEmpty ? (normalized.isEmpty ? 0 : 1) : lines.length,
    );

    final warnings = <ExtractionWarning>[
      ExtractionWarning(
        code: 'fallback_local_rules',
        message: upstreamErrorMessage == null
            ? 'AI 不可用，已用本地规则做基础整理。'
            : 'AI 失败（$upstreamErrorMessage），已用本地规则做基础整理。',
      ),
    ];

    final document = NormalizedExtractionDocument(
      noteContext: noteContext,
      ocrSummary: ocrSummary,
      entries: extracted,
      warnings: warnings,
    );

    return CanvasAiPreviewResult.success(
      engineName: 'local_rules',
      modelName: null,
      latency: Duration.zero,
      document: document,
      originalText: normalized,
      correctedText: normalized,
    );
  }

  ExtractedEntry? _toExtractedEntry(NoteEntry entry, DateTime now) {
    final raw = entry.rawText.trim();
    if (raw.isEmpty) return null;

    final id = _uuid.v4();
    final occurredDate = DateTime(now.year, now.month, now.day);

    switch (entry.type) {
      case NoteEntryType.expense:
        final exp = entry.expense;
        return ExtractedEntry(
          entryId: id,
          entryType: ExtractionEntryType.expense,
          domain: 'finance',
          title: exp?.description.isNotEmpty == true ? exp!.description : raw,
          rawText: raw,
          occurredAt: now,
          occurredDate: occurredDate,
          amount: exp == null
              ? null
              : ExtractionAmount(
                  value: exp.amount.toString(),
                  currency: 'CNY',
                ),
          category: exp == null
              ? null
              : ExtractionCategory(l1: exp.category),
          confidence: 0.5,
        );
      case NoteEntryType.event:
        final ev = entry.event;
        return ExtractedEntry(
          entryId: id,
          entryType: ExtractionEntryType.task,
          domain: 'productivity',
          title: ev?.title.isNotEmpty == true ? ev!.title : raw,
          rawText: raw,
          occurredAt: ev?.date,
          occurredDate: ev?.date ?? occurredDate,
          status: (ev?.isCompleted ?? false) ? 'done' : 'todo',
          confidence: 0.5,
        );
      case NoteEntryType.health:
        return ExtractedEntry(
          entryId: id,
          entryType: ExtractionEntryType.healthRecord,
          domain: 'health',
          title: raw,
          rawText: raw,
          occurredAt: now,
          occurredDate: occurredDate,
          confidence: 0.4,
        );
      case NoteEntryType.memo:
        return ExtractedEntry(
          entryId: id,
          entryType: ExtractionEntryType.memo,
          domain: 'general',
          title: raw,
          rawText: raw,
          occurredAt: now,
          occurredDate: occurredDate,
          confidence: 0.3,
        );
    }
  }
}
