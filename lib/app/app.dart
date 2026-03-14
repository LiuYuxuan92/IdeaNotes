import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/storage/database_helper.dart';
import '../features/notelist/bloc/note_list_bloc.dart';
import '../features/notelist/note_list_screen.dart';
import 'design_system.dart';

class IdeaNotesApp extends StatelessWidget {
  const IdeaNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NoteListBloc>(
      create: (context) => NoteListBloc(
        databaseHelper: DatabaseHelper.instance,
      )..add(LoadNotes()),
      child: MaterialApp(
        title: 'IdeaNotes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.light(),
        themeMode: ThemeMode.system,
        home: const NoteListScreen(),
      ),
    );
  }
}
