import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/storage/database_helper.dart';
import '../../../core/models/note.dart';

// ==================== Events ====================
abstract class NoteListEvent extends Equatable {
  const NoteListEvent();

  @override
  List<Object?> get props => [];
}

class LoadNotes extends NoteListEvent {}

class SearchNotes extends NoteListEvent {
  final String query;

  const SearchNotes(this.query);

  @override
  List<Object?> get props => [query];
}

class DeleteNote extends NoteListEvent {
  final String noteId;

  const DeleteNote(this.noteId);

  @override
  List<Object?> get props => [noteId];
}

class CreateNote extends NoteListEvent {}

class RefreshNotes extends NoteListEvent {}

// ==================== State ====================
enum NoteListStatus { initial, loading, loaded, error }

class NoteListState extends Equatable {
  final NoteListStatus status;
  final List<Note> notes;
  final List<Note> filteredNotes;
  final String searchQuery;
  final String? errorMessage;

  const NoteListState({
    this.status = NoteListStatus.initial,
    this.notes = const [],
    this.filteredNotes = const [],
    this.searchQuery = '',
    this.errorMessage,
  });

  NoteListState copyWith({
    NoteListStatus? status,
    List<Note>? notes,
    List<Note>? filteredNotes,
    String? searchQuery,
    String? errorMessage,
  }) {
    return NoteListState(
      status: status ?? this.status,
      notes: notes ?? this.notes,
      filteredNotes: filteredNotes ?? this.filteredNotes,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, notes, filteredNotes, searchQuery, errorMessage];
}

// ==================== Bloc ====================
class NoteListBloc extends Bloc<NoteListEvent, NoteListState> {
  final DatabaseHelper databaseHelper;

  NoteListBloc({required this.databaseHelper}) : super(const NoteListState()) {
    on<LoadNotes>(_onLoadNotes);
    on<SearchNotes>(_onSearchNotes);
    on<DeleteNote>(_onDeleteNote);
    on<CreateNote>(_onCreateNote);
    on<RefreshNotes>(_onRefreshNotes);
  }

  Future<void> _onLoadNotes(LoadNotes event, Emitter<NoteListState> emit) async {
    emit(state.copyWith(status: NoteListStatus.loading));
    
    try {
      final notes = await databaseHelper.getAllNotes();
      // 按更新时间倒序排列
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      
      emit(state.copyWith(
        status: NoteListStatus.loaded,
        notes: notes,
        filteredNotes: notes,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: NoteListStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  void _onSearchNotes(SearchNotes event, Emitter<NoteListState> emit) {
    final query = event.query.toLowerCase();
    
    if (query.isEmpty) {
      emit(state.copyWith(
        searchQuery: '',
        filteredNotes: state.notes,
      ));
    } else {
      final filtered = state.notes.where((note) {
        // 搜索标题和识别文本
        final title = note.id.toLowerCase();
        final recognizedText = note.recognizedText?.toLowerCase() ?? '';
        return title.contains(query) || recognizedText.contains(query);
      }).toList();
      
      emit(state.copyWith(
        searchQuery: query,
        filteredNotes: filtered,
      ));
    }
  }

  Future<void> _onDeleteNote(DeleteNote event, Emitter<NoteListState> emit) async {
    try {
      await databaseHelper.deleteNote(event.noteId);
      
      final updatedNotes = state.notes.where((n) => n.id != event.noteId).toList();
      final updatedFiltered = state.filteredNotes.where((n) => n.id != event.noteId).toList();
      
      emit(state.copyWith(
        notes: updatedNotes,
        filteredNotes: updatedFiltered,
      ));
    } catch (e) {
      emit(state.copyWith(
        errorMessage: '删除失败: ${e.toString()}',
      ));
    }
  }

  Future<void> _onCreateNote(CreateNote event, Emitter<NoteListState> emit) async {
    try {
      final now = DateTime.now();
      final newNote = Note(
        id: now.millisecondsSinceEpoch.toString(),
        createdAt: now,
        updatedAt: now,
      );
      
      await databaseHelper.insertNote(newNote);
      
      final updatedNotes = [newNote, ...state.notes];
      final updatedFiltered = state.searchQuery.isEmpty 
          ? updatedNotes 
          : state.filteredNotes;
      
      emit(state.copyWith(
        notes: updatedNotes,
        filteredNotes: updatedFiltered,
      ));
    } catch (e) {
      emit(state.copyWith(
        errorMessage: '创建失败: ${e.toString()}',
      ));
    }
  }

  Future<void> _onRefreshNotes(RefreshNotes event, Emitter<NoteListState> emit) async {
    add(LoadNotes());
  }
}
