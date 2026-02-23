import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/canvas/bloc/canvas_bloc.dart';
import '../features/notelist/bloc/note_list_bloc.dart';
import '../features/notelist/note_list_screen.dart';
import '../core/storage/database_helper.dart';

class IdeaNotesApp extends StatelessWidget {
  const IdeaNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NoteListBloc>(
          create: (context) => NoteListBloc(
            databaseHelper: DatabaseHelper.instance,
          )..add(LoadNotes()),
        ),
        BlocProvider<CanvasBloc>(
          create: (context) => CanvasBloc(),
        ),
      ],
      child: MaterialApp(
        title: 'IdeaNotes',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E88E5),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const NoteListScreen(),
      ),
    );
  }
}
