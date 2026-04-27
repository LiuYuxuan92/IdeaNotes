import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/notifications/weekly_review_notifier.dart';
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
    WeeklyReviewNotifier.bindNavigator(_navigatorKey);
    _shareHandler = ShareIntentHandler(navigatorKey: _navigatorKey)..start();
    // 冷启动若是被周回顾通知拉起的，第一帧后再 push Records Hub。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      WeeklyReviewNotifier.handleColdLaunchIfAny();
    });
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
          // 根据当前主题切换系统状态栏 / 导航栏图标颜色，
          // 否则在 dark mode 下深色背景配深色图标会看不见。
          final brightness = Theme.of(context).brightness;
          final isLight = brightness == Brightness.light;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isLight ? Brightness.dark : Brightness.light,
              statusBarBrightness:
                  isLight ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  isLight ? Brightness.dark : Brightness.light,
              systemNavigationBarContrastEnforced: false,
            ),
            child: MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(clampedScale),
              ),
              child: child!,
            ),
          );
        },
        home: const NoteListScreen(),
      ),
    );
  }
}
