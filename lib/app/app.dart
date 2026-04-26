import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/share_intent/share_intent_handler.dart';
import '../core/storage/database_helper.dart';
import '../features/notelist/bloc/note_list_bloc.dart';
import '../features/notelist/note_list_screen.dart';
import 'design_system.dart';

class IdeaNotesApp extends StatefulWidget {
  const IdeaNotesApp({super.key});

  @override
  State<IdeaNotesApp> createState() => _IdeaNotesAppState();
}

class _IdeaNotesAppState extends State<IdeaNotesApp> {
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  late final ShareIntentHandler _shareHandler;

  @override
  void initState() {
    super.initState();
    _shareHandler = ShareIntentHandler(navigatorKey: _navigatorKey)..start();
  }

  @override
  void dispose() {
    _shareHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NoteListBloc>(
      create: (context) => NoteListBloc(
        databaseHelper: DatabaseHelper.instance,
      )..add(LoadNotes()),
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'IdeaNotes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final clampedScale = mq.textScaler.scale(1).clamp(0.85, 1.3);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(clampedScale),
            ),
            child: child!,
          );
        },
        home: const NoteListScreen(),
      ),
    );
  }
}
