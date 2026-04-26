import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idea_notes/app/app.dart';
import 'core/notifications/weekly_review_notifier.dart';
import 'core/storage/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  // ignore: unawaited_futures
  WeeklyReviewNotifier()
      .scheduleNextWeeklyReview()
      .catchError((Object _) {
    // 静默失败：用户没授权 / 系统不支持都没关系
  });

  runApp(const IdeaNotesApp());
}
