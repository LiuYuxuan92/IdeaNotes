import 'package:decimal/decimal.dart';

class EntryRecord {
  final String id;
  final String noteId;
  final String entryType;
  final String domain;
  final DateTime? occurredAt;
  final DateTime occurredDate;
  final DateTime? endAt;
  final String title;
  final String? summary;
  final String rawText;
  final String? normalizedJson;
  final Decimal? amountValue;
  final String? amountCurrency;
  final String? categoryL1;
  final String? categoryL2;
  final String? status;
  final double? confidence;
  final bool isUserConfirmed;
  final String sourceEngine;
  final String? sourceVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EntryRecord({
    required this.id,
    required this.noteId,
    required this.entryType,
    required this.domain,
    required this.occurredAt,
    required this.occurredDate,
    required this.endAt,
    required this.title,
    required this.summary,
    required this.rawText,
    required this.normalizedJson,
    required this.amountValue,
    required this.amountCurrency,
    required this.categoryL1,
    required this.categoryL2,
    required this.status,
    required this.confidence,
    required this.isUserConfirmed,
    required this.sourceEngine,
    required this.sourceVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EntryRecord.fromMap(Map<String, dynamic> map) {
    return EntryRecord(
      id: map['id'] as String,
      noteId: map['note_id'] as String,
      entryType: map['entry_type'] as String,
      domain: map['domain'] as String,
      occurredAt: _millisToDateTime(map['occurred_at']),
      occurredDate: _dateStringToDate(map['occurred_date'] as String),
      endAt: _millisToDateTime(map['end_at']),
      title: map['title'] as String,
      summary: map['summary'] as String?,
      rawText: map['raw_text'] as String,
      normalizedJson: map['normalized_json'] as String?,
      amountValue: _decimalFromString(map['amount_value'] as String?),
      amountCurrency: map['amount_currency'] as String?,
      categoryL1: map['category_l1'] as String?,
      categoryL2: map['category_l2'] as String?,
      status: map['status'] as String?,
      confidence: _toDouble(map['confidence']),
      isUserConfirmed: _toInt(map['is_user_confirmed']) == 1,
      sourceEngine: map['source_engine'] as String,
      sourceVersion: map['source_version'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(_toInt(map['created_at'])),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(_toInt(map['updated_at'])),
    );
  }

  static DateTime _dateStringToDate(String raw) {
    final parts = raw.split('-');
    if (parts.length != 3) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static DateTime? _millisToDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_toInt(value));
  }

  static Decimal? _decimalFromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      return Decimal.parse(raw.trim());
    } catch (_) {
      return null;
    }
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.parse(value.toString());
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
