import 'dart:typed_data';

import 'package:idea_notes/core/extraction/ai_extraction_service.dart';
import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/extraction/extraction_orchestrator.dart';
import 'package:idea_notes/core/extraction/text_understanding_engine.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/models/note_entry.dart';
import 'package:idea_notes/core/parser/entry_parser.dart';
import 'package:idea_notes/core/parser/entry_text_rules.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/core/storage/entry_repository.dart';
import 'package:idea_notes/core/storage/image_storage.dart';
import 'package:uuid/uuid.dart';

class CanvasSaveInput {
  final Note? existingNote;
  final Uint8List canvasData;
  final Uint8List? snapshotBytes;
  final Uint8List? thumbnailBytes;
  final String? recognizedText;
  final DateTime now;

  const CanvasSaveInput({
    required this.existingNote,
    required this.canvasData,
    required this.snapshotBytes,
    required this.thumbnailBytes,
    required this.recognizedText,
    required this.now,
  });
}

class CanvasSaveService {
  final DatabaseHelper databaseHelper;
  final EntryRepository entryRepository;
  final String Function() createId;
  final Future<String> Function(Uint8List bytes, String noteId) saveSnapshot;
  final Future<String?> Function(Uint8List bytes, String noteId) saveThumbnail;
  final TextUnderstandingEngine? textUnderstandingEngine;
  final String extractionPromptVersion;
  final String timezone;
  final String locale;

  CanvasSaveService({
    required this.databaseHelper,
    String Function()? createId,
    Future<String> Function(Uint8List bytes, String noteId)? saveSnapshot,
    Future<String?> Function(Uint8List bytes, String noteId)? saveThumbnail,
    EntryRepository? entryRepository,
    this.textUnderstandingEngine,
    this.extractionPromptVersion = '1.0',
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
  })  : createId = createId ?? const Uuid().v4,
        saveSnapshot = saveSnapshot ?? ImageStorage.saveSnapshot,
        saveThumbnail = saveThumbnail ?? ImageStorage.saveThumbnail,
        entryRepository =
            entryRepository ?? EntryRepository(databaseHelper: databaseHelper);

  Future<Note> save(CanvasSaveInput input) async {
    final noteId = input.existingNote?.id ?? createId();
    final imagePaths = await _persistImages(
      noteId: noteId,
      snapshotBytes: input.snapshotBytes,
      thumbnailBytes: input.thumbnailBytes,
    );

    final recognizedText = _normalizedText(input.recognizedText);

    final note = await _upsertNote(
      existingNote: input.existingNote,
      noteId: noteId,
      canvasData: input.canvasData,
      snapshotPath: imagePaths.snapshotPath,
      thumbnailPath: imagePaths.thumbnailPath,
      recognizedText: recognizedText,
      now: input.now,
    );

    await _replaceEntries(note, recognizedText, input.now);
    return note;
  }

  Future<_SavedImagePaths> _persistImages({
    required String noteId,
    required Uint8List? snapshotBytes,
    required Uint8List? thumbnailBytes,
  }) async {
    String? snapshotPath;
    String? thumbnailPath;

    if (snapshotBytes != null) {
      snapshotPath = await saveSnapshot(snapshotBytes, noteId);
    }

    if (thumbnailBytes != null) {
      thumbnailPath = await saveThumbnail(thumbnailBytes, noteId);
    }

    return _SavedImagePaths(
      snapshotPath: snapshotPath,
      thumbnailPath: thumbnailPath,
    );
  }

  Future<Note> _upsertNote({
    required Note? existingNote,
    required String noteId,
    required Uint8List canvasData,
    required String? snapshotPath,
    required String? thumbnailPath,
    required String? recognizedText,
    required DateTime now,
  }) async {
    if (existingNote != null) {
      await databaseHelper.updateNote(existingNote.id, {
        'updated_at': now.millisecondsSinceEpoch,
        'canvas_data': canvasData,
        'snapshot_image_path': snapshotPath ?? existingNote.snapshotImagePath,
        'thumbnail_image_path':
            thumbnailPath ?? existingNote.thumbnailImagePath,
        'recognized_text': recognizedText,
      });

      return existingNote.copyWith(
        updatedAt: now,
        canvasData: canvasData,
        snapshotImagePath: snapshotPath ?? existingNote.snapshotImagePath,
        thumbnailImagePath: thumbnailPath ?? existingNote.thumbnailImagePath,
        recognizedText: recognizedText,
      );
    }

    await databaseHelper.insertNote({
      'id': noteId,
      'notebook_id': 'default-notebook',
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
      'canvas_data': canvasData,
      'snapshot_image_path': snapshotPath,
      'thumbnail_image_path': thumbnailPath,
      'recognized_text': recognizedText,
    });

    return Note(
      id: noteId,
      notebookId: 'default-notebook',
      createdAt: now,
      updatedAt: now,
      canvasData: canvasData,
      snapshotImagePath: snapshotPath,
      thumbnailImagePath: thumbnailPath,
      recognizedText: recognizedText,
    );
  }

  Future<void> _replaceEntries(
      Note note, String? recognizedText, DateTime now) async {
    final parsedEntries = recognizedText == null || recognizedText.isEmpty
        ? const <NoteEntry>[]
        : EntryParser.parseMultiLine(recognizedText);

    await _replaceLegacyEntries(note.id, parsedEntries, now);
    await _replaceStructuredEntries(note, recognizedText, parsedEntries, now);
  }

  Future<void> _replaceLegacyEntries(
    String noteId,
    List<NoteEntry> entries,
    DateTime now,
  ) async {
    await databaseHelper.deleteNoteEntries(noteId);

    if (entries.isEmpty) {
      return;
    }

    for (final entry in entries) {
      await databaseHelper.insertNoteEntry({
        'id': entry.id,
        'note_id': noteId,
        'type': entry.type.name,
        'raw_text': entry.rawText,
        'amount': entry.expense?.amount.toString(),
        'category': entry.expense?.category,
        'event_title': entry.event?.title,
        'event_date': entry.event?.date?.millisecondsSinceEpoch,
        'is_completed': (entry.event?.isCompleted ?? false) ? 1 : 0,
        'memo_text': entry.memoText,
        'created_at': now.millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _replaceStructuredEntries(
    Note note,
    String? recognizedText,
    List<NoteEntry> parsedEntries,
    DateTime now,
  ) async {
    await entryRepository.deleteEntriesForNote(note.id);

    if (recognizedText == null || recognizedText.isEmpty) {
      return;
    }

    final ruleEntries = _buildRuleEntries(
      parsedEntries: parsedEntries,
      note: note,
    );
    final orchestrator = ExtractionOrchestrator(
      aiExtractionService: AiExtractionService(engine: textUnderstandingEngine),
      ruleExtractor: (_) async => ruleEntries,
      auditSink: textUnderstandingEngine == null
          ? null
          : (record) => entryRepository.insertAiExtraction(record),
    );

    final result = await orchestrator.run(
      ExtractionOrchestratorInput(
        request: ExtractionRequest(
          noteContext: ExtractionNoteContext(
            noteId: note.id,
            noteCreatedAt: note.createdAt,
            timezone: timezone,
            locale: locale,
          ),
          ocrText: recognizedText,
          ruleCandidates: ruleEntries,
          promptVersion: extractionPromptVersion,
        ),
        enableRule: true,
        enableAi: textUnderstandingEngine != null,
      ),
    );

    await entryRepository.replaceExtractedEntriesForNote(
      noteId: note.id,
      entries: result.document.entries,
      now: now,
      sourceEngine: _sourceEngineFor(result),
      sourceVersion: _sourceVersionFor(result),
    );
  }

  String? _normalizedText(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<ExtractedEntry> _buildRuleEntries({
    required List<NoteEntry> parsedEntries,
    required Note note,
  }) {
    final extractedEntries = <ExtractedEntry>[];
    for (final entry in parsedEntries) {
      extractedEntries.add(_toExtractedEntry(entry: entry, note: note));

      final relatedHealthEntry = _buildRelatedHealthEntry(
        entry: entry,
        note: note,
      );
      if (relatedHealthEntry != null) {
        extractedEntries.add(relatedHealthEntry);
      }
    }
    return extractedEntries;
  }

  ExtractedEntry _toExtractedEntry({
    required NoteEntry entry,
    required Note note,
  }) {
    final eventDate = entry.event?.date;
    final occurredDate =
        eventDate != null ? _dateOnly(eventDate) : _dateOnly(note.createdAt);
    final classification = _classifyEntry(entry);
    final title = _entryTitle(entry);
    final category = _entryCategory(entry, classification.domain);

    return ExtractedEntry(
      entryId: entry.id,
      entryType: classification.entryType,
      domain: classification.domain,
      title: title,
      summary: _entrySummary(entry),
      rawText: entry.rawText,
      occurredAt: eventDate,
      occurredDate: occurredDate,
      status: _entryStatus(entry),
      amount: entry.expense != null
          ? ExtractionAmount(value: entry.expense!.amount.toString())
          : null,
      category: category,
      subjects: _entrySubjects(entry.rawText),
      tags: _entryTags(
        entryType: classification.entryType,
        text: entry.rawText,
        domain: classification.domain,
        category: category,
      ),
      normalized: _normalizedPayload(
        entry: entry,
        title: title,
        occurredDate: occurredDate,
      ),
      confidence: _entryConfidence(entry, classification.entryType),
    );
  }

  ExtractedEntry? _buildRelatedHealthEntry({
    required NoteEntry entry,
    required Note note,
  }) {
    if (entry.type != NoteEntryType.expense ||
        !EntryTextRules.hasHealthKeyword(entry.rawText)) {
      return null;
    }

    final relatedType = _relatedHealthType(entry.rawText);
    final relatedDate = _dateOnly(note.createdAt);
    final title = _entryTitle(entry);
    final category = _entryCategory(
      NoteEntry(
        id: entry.id,
        type: NoteEntryType.health,
        rawText: entry.rawText,
        memoText: entry.rawText,
      ),
      'health',
    );

    return ExtractedEntry(
      entryId: '${entry.id}::health',
      entryType: relatedType,
      domain: 'health',
      title: title,
      summary: '从花费记录派生的健康记录',
      rawText: entry.rawText,
      occurredDate: relatedDate,
      status: 'recorded',
      category: category,
      subjects: _entrySubjects(entry.rawText),
      tags: _entryTags(
        entryType: relatedType,
        text: entry.rawText,
        domain: 'health',
        category: category,
      ),
      normalized: {
        'derived_from_entry_id': entry.id,
        'derived_from_type': entry.type.name,
        'occurred_date': formatDateOnly(relatedDate),
      },
      confidence: 0.74,
    );
  }

  ExtractionEntryType _relatedHealthType(String text) {
    if (EntryTextRules.hasVaccinationKeyword(text)) {
      return ExtractionEntryType.vaccination;
    }
    if (EntryTextRules.hasMedicationKeyword(text)) {
      return ExtractionEntryType.medication;
    }
    return ExtractionEntryType.healthRecord;
  }

  _EntryClassification _classifyEntry(NoteEntry entry) {
    final text = entry.rawText;
    if (entry.type == NoteEntryType.expense) {
      return const _EntryClassification(
        entryType: ExtractionEntryType.expense,
        domain: 'finance',
      );
    }
    if (entry.type == NoteEntryType.health &&
        EntryTextRules.hasVaccinationKeyword(text)) {
      return const _EntryClassification(
        entryType: ExtractionEntryType.vaccination,
        domain: 'health',
      );
    }
    if (entry.type == NoteEntryType.health &&
        EntryTextRules.hasMedicationKeyword(text)) {
      return const _EntryClassification(
        entryType: ExtractionEntryType.medication,
        domain: 'health',
      );
    }
    if (entry.type == NoteEntryType.health ||
        (EntryTextRules.hasHealthKeyword(text) &&
            entry.type == NoteEntryType.memo)) {
      return const _EntryClassification(
        entryType: ExtractionEntryType.healthRecord,
        domain: 'health',
      );
    }
    if (entry.type == NoteEntryType.event) {
      return EntryTextRules.hasHealthKeyword(text)
          ? const _EntryClassification(
              entryType: ExtractionEntryType.task,
              domain: 'health',
            )
          : const _EntryClassification(
              entryType: ExtractionEntryType.task,
              domain: 'life',
            );
    }
    return EntryTextRules.hasHealthKeyword(text)
        ? const _EntryClassification(
            entryType: ExtractionEntryType.healthRecord,
            domain: 'health',
          )
        : const _EntryClassification(
            entryType: ExtractionEntryType.memo,
            domain: 'life',
          );
  }

  String _entryTitle(NoteEntry entry) {
    if (entry.expense != null) {
      final description = entry.expense!.description.trim();
      if (description.isNotEmpty) {
        return description;
      }
    }
    if (entry.event != null) {
      final title = entry.event!.title.trim();
      if (title.isNotEmpty) {
        return title;
      }
    }
    if (entry.type == NoteEntryType.health) {
      final memoText = entry.memoText?.trim();
      if (memoText != null && memoText.isNotEmpty) {
        return memoText;
      }
    }
    return _shortText(entry.rawText);
  }

  String? _entrySummary(NoteEntry entry) {
    if (entry.expense != null) {
      final category = entry.expense!.category.trim();
      if (category.isNotEmpty) {
        return category;
      }
    }
    if (entry.type == NoteEntryType.memo ||
        entry.type == NoteEntryType.health) {
      final memoText = entry.memoText?.trim();
      if (memoText != null &&
          memoText.isNotEmpty &&
          memoText != entry.rawText) {
        return memoText;
      }
    }
    return null;
  }

  String _entryStatus(NoteEntry entry) {
    if (entry.event != null) {
      return entry.event!.isCompleted ? 'done' : 'pending';
    }
    return 'recorded';
  }

  ExtractionCategory? _entryCategory(NoteEntry entry, String domain) {
    if (entry.expense != null) {
      final category = entry.expense!.category.trim();
      if (category.isNotEmpty) {
        return ExtractionCategory(l1: category);
      }
    }

    final text = entry.rawText;
    if (EntryTextRules.hasVaccinationKeyword(text)) {
      return const ExtractionCategory(l1: '医疗', l2: '疫苗');
    }
    if (EntryTextRules.hasMedicationKeyword(text)) {
      return const ExtractionCategory(l1: '医疗', l2: '用药');
    }
    if (EntryTextRules.hasDietRecordKeyword(text)) {
      return const ExtractionCategory(l1: '健康', l2: '饮食');
    }
    if (EntryTextRules.hasDigestiveKeyword(text)) {
      return const ExtractionCategory(l1: '健康', l2: '排便');
    }
    if (domain == 'health') {
      return const ExtractionCategory(l1: '健康');
    }
    return null;
  }

  List<ExtractionSubject> _entrySubjects(String text) {
    final subjects = <ExtractionSubject>[];
    if (EntryTextRules.hasBabyKeyword(text)) {
      subjects.add(
        const ExtractionSubject(
          name: '宝宝',
          type: 'person',
          role: 'subject',
        ),
      );
    }
    return subjects;
  }

  List<String> _entryTags({
    required ExtractionEntryType entryType,
    required String text,
    required String domain,
    required ExtractionCategory? category,
  }) {
    final tags = <String>{};
    if (_isRecordLikeEntry(entryType)) {
      tags.add('记录');
    }
    if (domain == 'health') {
      tags.add('健康');
    }
    if (EntryTextRules.hasBabyKeyword(text)) {
      tags.add('宝宝');
    }
    if (EntryTextRules.hasVaccinationKeyword(text)) {
      tags.add('疫苗');
    }
    if (EntryTextRules.hasMedicationKeyword(text)) {
      tags.add('用药');
    }
    if (EntryTextRules.hasDietRecordKeyword(text)) {
      tags.add('饮食');
    }
    if (EntryTextRules.hasDigestiveKeyword(text)) {
      tags.add('排便');
    }
    if (category?.l2 != null && category!.l2!.trim().isNotEmpty) {
      tags.add(category.l2!.trim());
    }
    return tags.toList(growable: false);
  }

  bool _isRecordLikeEntry(ExtractionEntryType entryType) {
    switch (entryType) {
      case ExtractionEntryType.healthRecord:
      case ExtractionEntryType.vaccination:
      case ExtractionEntryType.medication:
      case ExtractionEntryType.metric:
      case ExtractionEntryType.memo:
        return true;
      default:
        return false;
    }
  }

  Map<String, dynamic> _normalizedPayload({
    required NoteEntry entry,
    required String title,
    required DateTime occurredDate,
  }) {
    final payload = <String, dynamic>{
      'legacy_type': entry.type.name,
      'title': title,
      'occurred_date': formatDateOnly(occurredDate),
    };

    if (entry.expense != null) {
      payload['expense'] = {
        'amount': entry.expense!.amount.toString(),
        'category': entry.expense!.category,
        'description': entry.expense!.description,
      };
    }
    if (entry.event != null) {
      payload['event'] = {
        'title': entry.event!.title,
        'date': entry.event!.date?.toIso8601String(),
        'is_completed': entry.event!.isCompleted,
      };
    }
    if (entry.memoText != null && entry.memoText!.trim().isNotEmpty) {
      payload['memo_text'] = entry.memoText!.trim();
    }
    return payload;
  }

  double _entryConfidence(NoteEntry entry, ExtractionEntryType entryType) {
    if (entry.type == NoteEntryType.expense) {
      return 0.92;
    }
    if (entry.type == NoteEntryType.event) {
      return 0.88;
    }
    if (entry.type == NoteEntryType.health) {
      return 0.86;
    }
    if (entryType == ExtractionEntryType.vaccination ||
        entryType == ExtractionEntryType.medication ||
        entryType == ExtractionEntryType.healthRecord) {
      return 0.82;
    }
    return 0.76;
  }

  String _sourceEngineFor(OrchestratedExtractionResult result) {
    if (result.usedAi && result.aiError == null && result.aiEntriesCount > 0) {
      return result.usedRule ? 'rule+ai' : 'ai';
    }
    return 'rule-parser';
  }

  String _sourceVersionFor(OrchestratedExtractionResult result) {
    if (result.usedAi && result.aiError == null && result.aiEntriesCount > 0) {
      return extractionPromptVersion;
    }
    return 'v1';
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _shortText(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 32) {
      return normalized;
    }
    return '${normalized.substring(0, 32)}...';
  }
}

class _SavedImagePaths {
  final String? snapshotPath;
  final String? thumbnailPath;

  const _SavedImagePaths({
    required this.snapshotPath,
    required this.thumbnailPath,
  });
}

class _EntryClassification {
  final ExtractionEntryType entryType;
  final String domain;

  const _EntryClassification({
    required this.entryType,
    required this.domain,
  });
}
