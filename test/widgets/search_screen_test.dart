import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/features/notelist/bloc/note_list_bloc.dart';
import 'package:idea_notes/features/search/search_screen.dart';

class _TestSearchBloc extends NoteListBloc {
  _TestSearchBloc(NoteListState initial)
      : super(databaseHelper: DatabaseHelper.instance) {
    emit(initial);
  }

  @override
  void add(NoteListEvent event) {
    // 保持测试状态稳定，不触发真实数据库读取
  }
}

Widget _wrapWithBloc(NoteListBloc bloc) {
  return MaterialApp(
    home: BlocProvider.value(
      value: bloc,
      child: const SearchScreen(),
    ),
  );
}

void main() {
  group('SearchScreen widget', () {
    testWidgets('空查询时显示搜索引导', (tester) async {
      final bloc = _TestSearchBloc(const NoteListState(
        status: NoteListStatus.loaded,
        searchQuery: '',
        notes: [],
        filteredNotes: [],
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.text('输入关键词搜索笔记'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsWidgets);

      bloc.close();
    });

    testWidgets('有查询但无结果时显示未找到相关笔记', (tester) async {
      final bloc = _TestSearchBloc(const NoteListState(
        status: NoteListStatus.loaded,
        searchQuery: '牛奶',
        notes: [],
        filteredNotes: [],
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.text('未找到相关笔记'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);

      bloc.close();
    });

    testWidgets('有查询且有结果时显示搜索结果列表', (tester) async {
      final note = Note(
        id: 'search-note-1',
        createdAt: DateTime(2026, 3, 13, 10, 0),
        updatedAt: DateTime(2026, 3, 13, 10, 0),
        recognizedText: '买牛奶\n记得今天下班前',
      );

      final bloc = _TestSearchBloc(NoteListState(
        status: NoteListStatus.loaded,
        searchQuery: '牛奶',
        notes: [note],
        filteredNotes: [note],
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.textContaining('买牛奶'), findsWidgets);
      expect(find.byType(ListView), findsOneWidget);

      bloc.close();
    });
  });
}
