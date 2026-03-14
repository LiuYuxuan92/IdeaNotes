import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idea_notes/core/models/note.dart';
import 'package:idea_notes/core/storage/database_helper.dart';
import 'package:idea_notes/features/notelist/bloc/note_list_bloc.dart';
import 'package:idea_notes/features/notelist/note_list_screen.dart';

class _TestNoteListBloc extends NoteListBloc {
  _TestNoteListBloc(NoteListState initial)
      : super(databaseHelper: DatabaseHelper.instance) {
    emit(initial);
  }

  @override
  void add(NoteListEvent event) {
    // 忽略页面 initState 触发的真实加载事件，保持测试状态可控
  }
}

Widget _wrapWithBloc(NoteListBloc bloc) {
  return MaterialApp(
    home: BlocProvider.value(
      value: bloc,
      child: const NoteListScreen(),
    ),
  );
}

void main() {
  group('NoteListScreen widget', () {
    testWidgets('loaded 且为空时显示空状态', (tester) async {
      final bloc = _TestNoteListBloc(const NoteListState(
        status: NoteListStatus.loaded,
        notes: [],
        filteredNotes: [],
        searchQuery: '',
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.text('先写下第一条想法吧'), findsOneWidget);
      expect(find.text('新建第一条笔记'), findsOneWidget);

      bloc.close();
    });

    testWidgets('loaded 且有搜索词但无结果时显示搜索空状态', (tester) async {
      final bloc = _TestNoteListBloc(const NoteListState(
        status: NoteListStatus.loaded,
        notes: [],
        filteredNotes: [],
        searchQuery: '牛奶',
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.text('没有找到相关笔记'), findsOneWidget);
      expect(find.text('清空搜索词'), findsOneWidget);

      bloc.close();
    });

    testWidgets('error 状态时显示错误与重试按钮', (tester) async {
      final bloc = _TestNoteListBloc(const NoteListState(
        status: NoteListStatus.error,
        errorMessage: 'db failed',
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.text('笔记列表暂时打不开'), findsOneWidget);
      expect(find.textContaining('db failed'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);

      bloc.close();
    });

    testWidgets('loaded 且有笔记时显示列表摘要', (tester) async {
      final note = Note(
        id: 'note-1',
        createdAt: DateTime(2026, 3, 13, 10, 0),
        updatedAt: DateTime(2026, 3, 13, 10, 0),
        recognizedText: '第一行内容\n第二行内容\n第三行内容',
      );

      final bloc = _TestNoteListBloc(NoteListState(
        status: NoteListStatus.loaded,
        notes: [note],
        filteredNotes: [note],
        searchQuery: '',
      ));

      await tester.pumpWidget(_wrapWithBloc(bloc));
      await tester.pump();

      expect(find.textContaining('第一行内容'), findsWidgets);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      bloc.close();
    });
  });
}
