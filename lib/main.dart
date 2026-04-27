import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idea_notes/app/app.dart';
import 'core/backup/backup_service.dart';
import 'core/diagnostics/error_log.dart';
import 'core/notifications/weekly_review_notifier.dart';
import 'core/storage/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge display
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // Initialize database
  await DatabaseHelper.instance.database;

  // Limit image cache to 50 MB
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  // 后台计划本周回顾通知（非阻塞，失败不影响启动）
  unawaited(
    WeeklyReviewNotifier()
        .scheduleNextWeeklyReview()
        .catchError((Object e, StackTrace st) {
      ErrorLog.instance.warn('startup.weekly_review', '启动时排程本周回顾失败',
          error: e, stack: st);
    }),
  );

  // 后台自动备份（非阻塞，距上次备份 > 24h 时执行）
  unawaited(
    BackupService.instance
        .autoBackupIfNeeded()
        .catchError((Object e, StackTrace st) {
      ErrorLog.instance.warn('startup.auto_backup', '启动时自动备份失败',
          error: e, stack: st);
    }),
  );

  runApp(const IdeaNotesApp());
}
