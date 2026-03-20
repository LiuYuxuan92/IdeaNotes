import 'dart:convert';

import 'package:idea_notes/core/extraction/extraction_models.dart';
import 'package:idea_notes/core/query/entry_query.dart';
import 'package:idea_notes/core/query/entry_record.dart';
import 'package:uuid/uuid.dart';

import 'database_helper.dart';

class EntryRepository {
  final DatabaseHelper databaseHelper;
  final String Function() createId;

  EntryRepository({
    required this.databaseHelper,
    String Function()? createId,
  }) : createId = createId ?? const Uuid().v4;

  Future<int> insertEntry(Map<String, dynamic> entry) async {
    final db = await databaseHelper.database;
    return db.insert('entries', entry);
  }

  Future<int> insertAiExtraction(ExtractionAuditRecord record) async {
    final db = await databaseHelper.database;
    return db.insert('ai_extractions', {
      'id': createId(),
      'note_id': record.noteId,
      'engine_name': record.engineName,
      'engine_model': record.engineModel,
      'prompt_version': record.promptVersion,
      'input_text': record.inputText,
      'raw_response_json': record.rawResponseJson,
      'normalized_entries_json': record.normalizedEntriesJson,
      'status': record.status,
      'created_at': record.createdAt.millisecondsSinceEpoch,
    });
  }

  Future<int> deleteEntriesForNote(String noteId) async {
    final db = await databaseHelper.database;
    return db.delete(
      'entries',
      where: 'note_id = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> replaceExtractedEntriesForNote({
    required String noteId,
    required List<ExtractedEntry> entries,
    required DateTime now,
    required String sourceEngine,
    String? sourceVersion,
    bool isUserConfirmed = false,
  }) async {
    final db = await databaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'entries',
        where: 'note_id = ?',
        whereArgs: [noteId],
      );

      final persistedEntryIds = <String>{};
      for (final entry in entries) {
        persistedEntryIds.add(entry.entryId);
        await txn.insert(
          'entries',
          _buildEntryRow(
            noteId: noteId,
            entry: entry,
            now: now,
            sourceEngine: sourceEngine,
            sourceVersion: sourceVersion,
            isUserConfirmed: isUserConfirmed,
          ),
        );

        for (final subject in _dedupeSubjects(entry.subjects)) {
          await txn.insert('entry_subjects', {
            'id': createId(),
            'entry_id': entry.entryId,
            'subject_name': subject.name,
            'subject_type': subject.type,
            'role': _trimToNull(subject.role),
            'created_at': now.millisecondsSinceEpoch,
          });
        }

        for (final tag in _dedupeTags(entry.tags)) {
          await txn.insert('entry_tags', {
            'id': createId(),
            'entry_id': entry.entryId,
            'tag': tag,
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      }

      for (final entry in entries) {
        for (final link in entry.links) {
          if (!persistedEntryIds.contains(link.targetEntryTempId) ||
              link.targetEntryTempId == entry.entryId) {
            continue;
          }
          await txn.insert('entry_links', {
            'id': createId(),
            'from_entry_id': entry.entryId,
            'to_entry_id': link.targetEntryTempId,
            'link_type': link.type,
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      }
    });
  }

  Future<void> replaceEntrySubjects(
    String entryId,
    List<Map<String, dynamic>> subjects,
  ) async {
    final db = await databaseHelper.database;
    await db.delete(
      'entry_subjects',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    for (final subject in subjects) {
      await db.insert('entry_subjects', subject);
    }
  }

  Future<void> replaceEntryTags(
    String entryId,
    List<Map<String, dynamic>> tags,
  ) async {
    final db = await databaseHelper.database;
    await db.delete(
      'entry_tags',
      where: 'entry_id = ?',
      whereArgs: [entryId],
    );
    for (final tag in tags) {
      await db.insert('entry_tags', tag);
    }
  }

  Future<List<EntryRecord>> queryEntries(EntryQuery query) async {
    final db = await databaseHelper.database;
    final built = _buildQuery(query);
    final rows = await db.rawQuery(built.sql, built.args);
    return rows.map(EntryRecord.fromMap).toList();
  }

  Future<List<EntryRecord>> queryEntriesByDate(
    DateTime date, {
    EntryQuery baseQuery = const EntryQuery(),
  }) {
    return queryEntries(
      baseQuery.copyWith(from: _startOfDay(date), to: _startOfDay(date)),
    );
  }

  _BuiltSql _buildQuery(EntryQuery query) {
    final sql = StringBuffer('SELECT DISTINCT e.* FROM entries e');
    final where = <String>[];
    final args = <Object?>[];

    if (query.subjectNames.isNotEmpty) {
      sql.write(' INNER JOIN entry_subjects es ON es.entry_id = e.id');
      where.add(_inClause('es.subject_name', query.subjectNames.length));
      args.addAll(query.subjectNames);
    }

    if (query.tags.isNotEmpty) {
      sql.write(' INNER JOIN entry_tags et ON et.entry_id = e.id');
      where.add(_inClause('et.tag', query.tags.length));
      args.addAll(query.tags);
    }

    if (query.entryTypes.isNotEmpty) {
      where.add(_inClause('e.entry_type', query.entryTypes.length));
      args.addAll(query.entryTypes);
    }
    if (query.domains.isNotEmpty) {
      where.add(_inClause('e.domain', query.domains.length));
      args.addAll(query.domains);
    }
    if (query.categoryL1.isNotEmpty) {
      where.add(_inClause('e.category_l1', query.categoryL1.length));
      args.addAll(query.categoryL1);
    }
    if (query.categoryL2.isNotEmpty) {
      where.add(_inClause('e.category_l2', query.categoryL2.length));
      args.addAll(query.categoryL2);
    }

    if (query.from != null) {
      where.add('e.occurred_date >= ?');
      args.add(_formatDate(_startOfDay(query.from!)));
    }
    if (query.to != null) {
      where.add('e.occurred_date <= ?');
      args.add(_formatDate(_startOfDay(query.to!)));
    }
    if (query.confirmedOnly != null) {
      where.add('e.is_user_confirmed = ?');
      args.add(query.confirmedOnly! ? 1 : 0);
    }
    if (query.keyword != null && query.keyword!.trim().isNotEmpty) {
      final pattern = '%${query.keyword!.trim()}%';
      where.add(
        '(e.title LIKE ? OR e.summary LIKE ? OR e.raw_text LIKE ?)',
      );
      args.addAll([pattern, pattern, pattern]);
    }

    if (where.isNotEmpty) {
      sql.write(' WHERE ${where.join(' AND ')}');
    }

    final sortBy = _normalizeSortKey(query.sortBy);
    final sortDirection = query.descending ? 'DESC' : 'ASC';
    sql.write(' ORDER BY e.$sortBy $sortDirection, e.created_at DESC');

    if (query.limit != null) {
      sql.write(' LIMIT ?');
      args.add(query.limit);
      if (query.offset != null) {
        sql.write(' OFFSET ?');
        args.add(query.offset);
      }
    }

    return _BuiltSql(sql: sql.toString(), args: args);
  }

  static String _normalizeSortKey(String key) {
    const allowed = <String>{
      'occurred_date',
      'created_at',
      'updated_at',
      'entry_type',
    };
    if (allowed.contains(key)) {
      return key;
    }
    return 'occurred_date';
  }

  static String _inClause(String field, int count) {
    final placeholders = List.filled(count, '?').join(', ');
    return '$field IN ($placeholders)';
  }

  static DateTime _startOfDay(DateTime time) {
    return DateTime(time.year, time.month, time.day);
  }

  static String _formatDate(DateTime time) {
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '${time.year}-$m-$d';
  }

  static Map<String, dynamic> _buildEntryRow({
    required String noteId,
    required ExtractedEntry entry,
    required DateTime now,
    required String sourceEngine,
    required String? sourceVersion,
    required bool isUserConfirmed,
  }) {
    return {
      'id': entry.entryId,
      'note_id': noteId,
      'entry_type': entry.entryType.toValue(),
      'domain': entry.domain,
      'occurred_at': entry.occurredAt?.millisecondsSinceEpoch,
      'occurred_date': formatDateOnly(entry.occurredDate),
      'end_at': entry.endAt?.millisecondsSinceEpoch,
      'title': entry.title,
      'summary': _trimToNull(entry.summary),
      'raw_text': entry.rawText,
      'normalized_json':
          entry.normalized.isEmpty ? null : jsonEncode(entry.normalized),
      'amount_value': entry.amount?.value,
      'amount_currency': entry.amount?.currency,
      'category_l1': entry.category?.l1,
      'category_l2': entry.category?.l2,
      'status': entry.status,
      'confidence': entry.confidence,
      'is_user_confirmed': isUserConfirmed ? 1 : 0,
      'source_engine': sourceEngine,
      'source_version': sourceVersion,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    };
  }

  static List<ExtractionSubject> _dedupeSubjects(
    List<ExtractionSubject> subjects,
  ) {
    final deduped = <String, ExtractionSubject>{};
    for (final subject in subjects) {
      final key =
          '${subject.type.toLowerCase()}|${subject.name.toLowerCase()}|${(subject.role ?? '').toLowerCase()}';
      deduped.putIfAbsent(key, () => subject);
    }
    return deduped.values.toList(growable: false);
  }

  static List<String> _dedupeTags(List<String> tags) {
    final deduped = <String>{};
    for (final tag in tags) {
      final normalized = tag.trim();
      if (normalized.isEmpty) {
        continue;
      }
      deduped.add(normalized);
    }
    return deduped.toList(growable: false);
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class _BuiltSql {
  final String sql;
  final List<Object?> args;

  const _BuiltSql({
    required this.sql,
    required this.args,
  });
}
