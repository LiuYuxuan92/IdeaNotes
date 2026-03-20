import 'dart:convert';

enum ExtractionEntryType {
  expense,
  income,
  task,
  appointment,
  healthRecord,
  vaccination,
  medication,
  metric,
  purchase,
  travel,
  document,
  memo,
  custom,
}

extension ExtractionEntryTypeX on ExtractionEntryType {
  static ExtractionEntryType fromValue(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'expense':
        return ExtractionEntryType.expense;
      case 'income':
        return ExtractionEntryType.income;
      case 'task':
        return ExtractionEntryType.task;
      case 'appointment':
        return ExtractionEntryType.appointment;
      case 'health_record':
      case 'healthrecord':
        return ExtractionEntryType.healthRecord;
      case 'vaccination':
        return ExtractionEntryType.vaccination;
      case 'medication':
        return ExtractionEntryType.medication;
      case 'metric':
        return ExtractionEntryType.metric;
      case 'purchase':
        return ExtractionEntryType.purchase;
      case 'travel':
        return ExtractionEntryType.travel;
      case 'document':
        return ExtractionEntryType.document;
      case 'memo':
        return ExtractionEntryType.memo;
      default:
        return ExtractionEntryType.custom;
    }
  }

  String toValue() {
    switch (this) {
      case ExtractionEntryType.healthRecord:
        return 'health_record';
      default:
        return name;
    }
  }
}

class ExtractionNoteContext {
  final String noteId;
  final DateTime noteCreatedAt;
  final String timezone;
  final String locale;

  const ExtractionNoteContext({
    required this.noteId,
    required this.noteCreatedAt,
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
  });

  Map<String, dynamic> toMap() {
    return {
      'note_id': noteId,
      'note_created_at': noteCreatedAt.toIso8601String(),
      'timezone': timezone,
      'locale': locale,
    };
  }

  factory ExtractionNoteContext.fromMap(Map<String, dynamic> map) {
    final noteId = map['note_id']?.toString();
    final createdAtRaw = map['note_created_at']?.toString();
    if (noteId == null || noteId.isEmpty || createdAtRaw == null) {
      throw const FormatException('Invalid note_context payload');
    }

    return ExtractionNoteContext(
      noteId: noteId,
      noteCreatedAt: DateTime.parse(createdAtRaw),
      timezone: map['timezone']?.toString() ?? 'Asia/Shanghai',
      locale: map['locale']?.toString() ?? 'zh-CN',
    );
  }
}

class ExtractionOcrSummary {
  final String fullText;
  final int lineCount;

  const ExtractionOcrSummary({
    required this.fullText,
    required this.lineCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'full_text': fullText,
      'line_count': lineCount,
    };
  }

  factory ExtractionOcrSummary.fromMap(Map<String, dynamic> map) {
    return ExtractionOcrSummary(
      fullText: map['full_text']?.toString() ?? '',
      lineCount: _toInt(map['line_count']) ?? 0,
    );
  }
}

class ExtractionAmount {
  final String value;
  final String currency;

  const ExtractionAmount({
    required this.value,
    this.currency = 'CNY',
  });

  Map<String, dynamic> toMap() {
    return {
      'value': value,
      'currency': currency,
    };
  }

  factory ExtractionAmount.fromMap(Map<String, dynamic> map) {
    final value = map['value']?.toString().trim();
    if (value == null || value.isEmpty) {
      throw const FormatException('Invalid amount payload');
    }
    return ExtractionAmount(
      value: value,
      currency: map['currency']?.toString().trim().isNotEmpty == true
          ? map['currency'].toString()
          : 'CNY',
    );
  }
}

class ExtractionCategory {
  final String l1;
  final String? l2;

  const ExtractionCategory({
    required this.l1,
    this.l2,
  });

  Map<String, dynamic> toMap() {
    return {
      'l1': l1,
      'l2': l2,
    };
  }

  factory ExtractionCategory.fromMap(Map<String, dynamic> map) {
    final l1 = map['l1']?.toString().trim();
    if (l1 == null || l1.isEmpty) {
      throw const FormatException('Invalid category payload');
    }
    final l2Raw = map['l2']?.toString().trim();
    return ExtractionCategory(
      l1: l1,
      l2: l2Raw == null || l2Raw.isEmpty ? null : l2Raw,
    );
  }
}

class ExtractionSubject {
  final String name;
  final String type;
  final String? role;

  const ExtractionSubject({
    required this.name,
    this.type = 'person',
    this.role,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'role': role,
    };
  }

  factory ExtractionSubject.fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString().trim();
    if (name == null || name.isEmpty) {
      throw const FormatException('Invalid subject payload');
    }

    final roleRaw = map['role']?.toString().trim();
    return ExtractionSubject(
      name: name,
      type: map['type']?.toString().trim().isNotEmpty == true
          ? map['type'].toString()
          : 'person',
      role: roleRaw == null || roleRaw.isEmpty ? null : roleRaw,
    );
  }
}

class ExtractionLink {
  final String targetEntryTempId;
  final String type;

  const ExtractionLink({
    required this.targetEntryTempId,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'target_entry_temp_id': targetEntryTempId,
      'type': type,
    };
  }

  factory ExtractionLink.fromMap(Map<String, dynamic> map) {
    final target = map['target_entry_temp_id']?.toString().trim();
    final type = map['type']?.toString().trim();
    if (target == null || target.isEmpty || type == null || type.isEmpty) {
      throw const FormatException('Invalid link payload');
    }
    return ExtractionLink(
      targetEntryTempId: target,
      type: type,
    );
  }
}

class ExtractionWarning {
  final String code;
  final String message;
  final String? entryId;

  const ExtractionWarning({
    required this.code,
    required this.message,
    this.entryId,
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'message': message,
      'entry_id': entryId,
    };
  }

  factory ExtractionWarning.fromMap(Map<String, dynamic> map) {
    final code = map['code']?.toString().trim();
    final message = map['message']?.toString().trim();
    if (code == null || code.isEmpty || message == null || message.isEmpty) {
      throw const FormatException('Invalid warning payload');
    }
    return ExtractionWarning(
      code: code,
      message: message,
      entryId: map['entry_id']?.toString(),
    );
  }
}

class ExtractedEntry {
  final String entryId;
  final ExtractionEntryType entryType;
  final String domain;
  final String title;
  final String? summary;
  final String rawText;
  final DateTime? occurredAt;
  final DateTime occurredDate;
  final DateTime? endAt;
  final String status;
  final ExtractionAmount? amount;
  final ExtractionCategory? category;
  final List<ExtractionSubject> subjects;
  final List<String> tags;
  final List<ExtractionLink> links;
  final Map<String, dynamic> normalized;
  final double confidence;

  const ExtractedEntry({
    required this.entryId,
    required this.entryType,
    required this.domain,
    required this.title,
    required this.rawText,
    required this.occurredDate,
    this.summary,
    this.occurredAt,
    this.endAt,
    this.status = 'recorded',
    this.amount,
    this.category,
    this.subjects = const [],
    this.tags = const [],
    this.links = const [],
    this.normalized = const {},
    this.confidence = 0.0,
  });

  ExtractedEntry copyWith({
    String? entryId,
    ExtractionEntryType? entryType,
    String? domain,
    String? title,
    String? summary,
    String? rawText,
    DateTime? occurredAt,
    DateTime? occurredDate,
    DateTime? endAt,
    String? status,
    ExtractionAmount? amount,
    ExtractionCategory? category,
    List<ExtractionSubject>? subjects,
    List<String>? tags,
    List<ExtractionLink>? links,
    Map<String, dynamic>? normalized,
    double? confidence,
  }) {
    return ExtractedEntry(
      entryId: entryId ?? this.entryId,
      entryType: entryType ?? this.entryType,
      domain: domain ?? this.domain,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      rawText: rawText ?? this.rawText,
      occurredAt: occurredAt ?? this.occurredAt,
      occurredDate: occurredDate ?? this.occurredDate,
      endAt: endAt ?? this.endAt,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      subjects: subjects ?? this.subjects,
      tags: tags ?? this.tags,
      links: links ?? this.links,
      normalized: normalized ?? this.normalized,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'entry_id': entryId,
      'entry_type': entryType.toValue(),
      'domain': domain,
      'title': title,
      'summary': summary,
      'raw_text': rawText,
      'occurred_at': occurredAt?.toIso8601String(),
      'occurred_date': formatDateOnly(occurredDate),
      'end_at': endAt?.toIso8601String(),
      'status': status,
      'amount': amount?.toMap(),
      'category': category?.toMap(),
      'subjects': subjects.map((item) => item.toMap()).toList(),
      'tags': tags,
      'links': links.map((item) => item.toMap()).toList(),
      'normalized': normalized,
      'confidence': confidence,
    };
  }

  factory ExtractedEntry.fromMap(Map<String, dynamic> map) {
    final entryId = map['entry_id']?.toString().trim();
    final domain = map['domain']?.toString().trim();
    final title = map['title']?.toString().trim();
    final rawText = map['raw_text']?.toString().trim();

    if (entryId == null || entryId.isEmpty) {
      throw const FormatException('entry_id is required');
    }
    if (domain == null || domain.isEmpty) {
      throw const FormatException('domain is required');
    }
    if (title == null || title.isEmpty) {
      throw const FormatException('title is required');
    }
    if (rawText == null || rawText.isEmpty) {
      throw const FormatException('raw_text is required');
    }

    final occurredDateRaw = map['occurred_date']?.toString().trim();
    final occurredAt = _parseDateTime(map['occurred_at']);
    final occurredDate = occurredDateRaw != null && occurredDateRaw.isNotEmpty
        ? parseDateOnly(occurredDateRaw)
        : (occurredAt != null
            ? DateTime(occurredAt.year, occurredAt.month, occurredAt.day)
            : throw const FormatException('occurred_date is required'));

    final amountMap = map['amount'];
    final categoryMap = map['category'];

    final subjectsRaw = map['subjects'];
    final linksRaw = map['links'];
    final tagsRaw = map['tags'];
    final normalizedRaw = map['normalized'];

    return ExtractedEntry(
      entryId: entryId,
      entryType: ExtractionEntryTypeX.fromValue(map['entry_type']?.toString()),
      domain: domain,
      title: title,
      summary: map['summary']?.toString(),
      rawText: rawText,
      occurredAt: occurredAt,
      occurredDate: occurredDate,
      endAt: _parseDateTime(map['end_at']),
      status: map['status']?.toString().trim().isNotEmpty == true
          ? map['status'].toString()
          : 'recorded',
      amount: amountMap is Map<String, dynamic>
          ? ExtractionAmount.fromMap(amountMap)
          : null,
      category: categoryMap is Map<String, dynamic>
          ? ExtractionCategory.fromMap(categoryMap)
          : null,
      subjects: subjectsRaw is List
          ? subjectsRaw
              .whereType<Map<String, dynamic>>()
              .map(ExtractionSubject.fromMap)
              .toList(growable: false)
          : const [],
      tags: tagsRaw is List
          ? tagsRaw
              .whereType<Object>()
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
          : const [],
      links: linksRaw is List
          ? linksRaw
              .whereType<Map<String, dynamic>>()
              .map(ExtractionLink.fromMap)
              .toList(growable: false)
          : const [],
      normalized: normalizedRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(normalizedRaw)
          : const {},
      confidence: _toDouble(map['confidence']) ?? 0.0,
    );
  }
}

class NormalizedExtractionDocument {
  final String schemaVersion;
  final ExtractionNoteContext noteContext;
  final ExtractionOcrSummary ocrSummary;
  final List<ExtractedEntry> entries;
  final List<ExtractionWarning> warnings;
  final List<String> unparsedSegments;

  const NormalizedExtractionDocument({
    this.schemaVersion = '1.0',
    required this.noteContext,
    required this.ocrSummary,
    required this.entries,
    this.warnings = const [],
    this.unparsedSegments = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'schema_version': schemaVersion,
      'note_context': noteContext.toMap(),
      'ocr_summary': ocrSummary.toMap(),
      'entries': entries.map((entry) => entry.toMap()).toList(),
      'warnings': warnings.map((warning) => warning.toMap()).toList(),
      'unparsed_segments': unparsedSegments,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory NormalizedExtractionDocument.fromMap(Map<String, dynamic> map) {
    final noteContextMap = map['note_context'];
    final ocrSummaryMap = map['ocr_summary'];
    if (noteContextMap is! Map<String, dynamic> ||
        ocrSummaryMap is! Map<String, dynamic>) {
      throw const FormatException('Missing note_context or ocr_summary');
    }

    final entriesRaw = map['entries'];
    final warningsRaw = map['warnings'];
    final unparsedRaw = map['unparsed_segments'];

    return NormalizedExtractionDocument(
      schemaVersion: map['schema_version']?.toString() ?? '1.0',
      noteContext: ExtractionNoteContext.fromMap(noteContextMap),
      ocrSummary: ExtractionOcrSummary.fromMap(ocrSummaryMap),
      entries: entriesRaw is List
          ? entriesRaw
              .whereType<Map<String, dynamic>>()
              .map(ExtractedEntry.fromMap)
              .toList(growable: false)
          : const [],
      warnings: warningsRaw is List
          ? warningsRaw
              .whereType<Map<String, dynamic>>()
              .map(ExtractionWarning.fromMap)
              .toList(growable: false)
          : const [],
      unparsedSegments: unparsedRaw is List
          ? unparsedRaw
              .whereType<Object>()
              .map((item) => item.toString())
              .toList(growable: false)
          : const [],
    );
  }
}

class ExtractionRequest {
  final ExtractionNoteContext noteContext;
  final String ocrText;
  final List<ExtractedEntry> ruleCandidates;
  final String promptVersion;

  const ExtractionRequest({
    required this.noteContext,
    required this.ocrText,
    this.ruleCandidates = const [],
    this.promptVersion = '1.0',
  });

  Map<String, dynamic> toMap() {
    return {
      'schema_version': promptVersion,
      'note_context': noteContext.toMap(),
      'ocr_summary': {
        'full_text': ocrText,
        'line_count': _lineCount(ocrText),
      },
      'rule_candidates': ruleCandidates.map((entry) => entry.toMap()).toList(),
    };
  }
}

class ExtractionAuditRecord {
  final String noteId;
  final String engineName;
  final String engineModel;
  final String promptVersion;
  final String inputText;
  final String rawResponseJson;
  final String normalizedEntriesJson;
  final String status;
  final DateTime createdAt;

  const ExtractionAuditRecord({
    required this.noteId,
    required this.engineName,
    required this.engineModel,
    required this.promptVersion,
    required this.inputText,
    required this.rawResponseJson,
    required this.normalizedEntriesJson,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'note_id': noteId,
      'engine_name': engineName,
      'engine_model': engineModel,
      'prompt_version': promptVersion,
      'input_text': inputText,
      'raw_response_json': rawResponseJson,
      'normalized_entries_json': normalizedEntriesJson,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

DateTime parseDateOnly(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw FormatException('Invalid date format: $value');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return DateTime(year, month, day);
}

String formatDateOnly(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

int _lineCount(String input) {
  if (input.trim().isEmpty) return 0;
  return input
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .length;
}

int? _toInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
