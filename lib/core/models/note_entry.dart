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

  @override
  List<Object?> get props => [id, type, rawText, expense, event, memoText];
}

class ExpenseRecord extends Equatable {
  final double amount;
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
