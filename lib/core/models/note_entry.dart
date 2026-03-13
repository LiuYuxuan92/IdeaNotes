import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

enum NoteEntryType {
  expense,
  event,
  memo,
}

class NoteEntry extends Equatable {
  final String id;
  final NoteEntryType type;
  final String rawText;
  final ExpenseRecord? expense;
  final EventRecord? event;
  final String? memoText;

  const NoteEntry({
    required this.id,
    required this.type,
    required this.rawText,
    this.expense,
    this.event,
    this.memoText,
  });

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    final typeString = (map['type'] as String?) ?? 'memo';
    final type = NoteEntryType.values.firstWhere(
      (value) => value.name == typeString,
      orElse: () => NoteEntryType.memo,
    );

    final amountString = map['amount'] as String?;
    final eventDateMillis = map['event_date'] as int?;
    final isCompletedRaw = map['is_completed'];
    final isCompleted = isCompletedRaw == 1 || isCompletedRaw == true;

    return NoteEntry(
      id: map['id'] as String,
      type: type,
      rawText: (map['raw_text'] as String?) ?? '',
      expense: type == NoteEntryType.expense && amountString != null
          ? ExpenseRecord(
              amount: Decimal.parse(amountString),
              category: (map['category'] as String?) ?? '其他',
              description: (map['raw_text'] as String?) ?? '',
            )
          : null,
      event: type == NoteEntryType.event
          ? EventRecord(
              title: (map['event_title'] as String?) ?? ((map['raw_text'] as String?) ?? ''),
              date: eventDateMillis != null
                  ? DateTime.fromMillisecondsSinceEpoch(eventDateMillis)
                  : null,
              isCompleted: isCompleted,
            )
          : null,
      memoText: type == NoteEntryType.memo
          ? (map['memo_text'] as String?) ?? (map['raw_text'] as String?)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, type, rawText, expense, event, memoText];
}

class ExpenseRecord extends Equatable {
  final Decimal amount;
  final String category;
  final String description;

  const ExpenseRecord({
    required this.amount,
    required this.category,
    required this.description,
  });

  @override
  List<Object?> get props => [amount, category, description];
}

class EventRecord extends Equatable {
  final String title;
  final DateTime? date;
  final bool isCompleted;

  const EventRecord({
    required this.title,
    this.date,
    this.isCompleted = false,
  });

  @override
  List<Object?> get props => [title, date, isCompleted];
}
