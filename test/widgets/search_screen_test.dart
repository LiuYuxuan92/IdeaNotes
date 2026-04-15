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

Widget _wrapWithBloc(
  NoteListBloc bloc, {
  Size? mediaSize,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  Widget child = BlocProvider.value(
    value: bloc,
    child: const SearchScreen(),
  );

  if (mediaSize != null) {
    child = MediaQuery(
      data: MediaQueryData(
        size: mediaSize,
        viewInsets: viewInsets,
      ),
      child: child,
    );
  }

  return MaterialApp(
    home: child,
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

      expect(find.text('输入关键词搜索笔记'), findsWidgets);
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

      expect(find.text('未找到相关笔记'), findsWidgets);
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

    testWidgets('手机端有查询时进入结果优先布局', (tester) async {
      final note = Note(
        id: 'search-note-mobile-1',
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

      await tester.pumpWidget(
        _wrapWithBloc(bloc, mediaSize: const Size(390, 844)),
      );
      await tester.pump();

      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('全文搜索只搜 OCR 原文；按类型查请直接走下面的结构化入口。'), findsNothing);
      expect(find.text('支出分类'), findsNothing);
      expect(find.text('待办时间线'), findsNothing);
      expect(find.text('健康记录'), findsNothing);
      expect(find.textContaining('买牛奶'), findsWidgets);

      bloc.close();
    });

    testWidgets('手机端键盘弹起时仍然保留结果列表可见区域', (tester) async {
      final note = Note(
        id: 'search-note-mobile-2',
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

      await tester.pumpWidget(
        _wrapWithBloc(
          bloc,
          mediaSize: const Size(390, 844),
          viewInsets: const EdgeInsets.only(bottom: 320),
        ),
      );
      await tester.pump();

      expect(find.text('已筛出 1 条结果'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.textContaining('买牛奶'), findsWidgets);

      final listRect = tester.getRect(find.byType(ListView));
      expect(listRect.height, greaterThan(120));

      bloc.close();
    });
  });
}
