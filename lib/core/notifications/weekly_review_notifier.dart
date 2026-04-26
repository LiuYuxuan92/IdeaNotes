import 'package:decimal/decimal.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../query/analytics_service.dart';
import '../query/entry_query.dart';
import '../query/timeline_service.dart';
import '../storage/database_helper.dart';
import '../storage/entry_repository.dart';

/// 周日 20:00 推送一份本周回顾通知。
///
/// 实现要点：
/// - 用 [flutter_local_notifications] 的 `zonedSchedule` 排周期通知
/// - 内容是一段动态生成的摘要（笔数、花费、待办剩余）
/// - APP 启动时调用 [scheduleNextWeeklyReview]，幂等
/// - 用户在设置页可以一键关闭（取消所有挂起通知）
class WeeklyReviewNotifier {
  static const int _notificationId = 1001;
  static const String _channelId = 'weekly_review';
  static const String _channelName = '本周回顾';
  static const String _channelDescription = '每周日晚上推送一份本周记录摘要';

  final FlutterLocalNotificationsPlugin _plugin;
  final EntryRepository _entryRepository;
  bool _initialized = false;

  WeeklyReviewNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    EntryRepository? entryRepository,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _entryRepository = entryRepository ??
            EntryRepository(databaseHelper: DatabaseHelper.instance);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      // fall back to default
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;
  }

  /// 请求通知权限（Android 13+ 和 iOS 必须主动请求）。
  /// 返回是否已获得权限。
  Future<bool> requestPermissions() async {
    await _ensureInitialized();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted =
        await android?.requestNotificationsPermission() ?? true;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;
    return androidGranted && iosGranted;
  }

  /// 排下一次周日 20:00 的提醒（幂等：会先取消同 ID 的）。
  Future<void> scheduleNextWeeklyReview({DateTime? now}) async {
    await _ensureInitialized();
    final summary = await _buildSummary(now: now ?? DateTime.now());

    await _plugin.cancel(_notificationId);

    final next = _nextSundayAt20(now ?? tz.TZDateTime.now(tz.local));
    await _plugin.zonedSchedule(
      _notificationId,
      '本周回顾',
      summary,
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// 取消已计划的周回顾通知。
  Future<void> cancel() async {
    await _ensureInitialized();
    await _plugin.cancel(_notificationId);
  }

  /// 用户在设置里可点击的"立即试一下"按钮 - 立刻弹一次摘要。
  Future<void> showNow({DateTime? now}) async {
    await _ensureInitialized();
    final summary = await _buildSummary(now: now ?? DateTime.now());
    await _plugin.show(
      _notificationId + 1,
      '本周回顾（试看）',
      summary,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ── 内部 ──

  Future<String> _buildSummary({required DateTime now}) async {
    // 本周 = 周一 00:00 ~ 现在
    final weekStart = _startOfWeek(now);
    final query = EntryQuery(from: weekStart, to: now);

    try {
      final analytics = AnalyticsService(entryRepository: _entryRepository);
      final timeline =
          TimelineService(entryRepository: _entryRepository);

      final expenseQuery = query.copyWith(
        entryTypes: const {'expense'},
        domains: const {'finance'},
      );
      final expenseSummary =
          await analytics.getAmountSummary(expenseQuery);
      final taskGroups = await timeline.getDailyTimeline(
        query.copyWith(entryTypes: const {'task'}),
      );
      var pendingTasks = 0;
      for (final g in taskGroups) {
        for (final e in g.entries) {
          if (e.status != 'done') pendingTasks += 1;
        }
      }

      final parts = <String>[];
      if (expenseSummary.entryCount > 0) {
        parts.add(
          '本周记了 ${expenseSummary.entryCount} 笔花费，'
          '共 ¥${_formatAmount(expenseSummary.totalAmount)}',
        );
      } else {
        parts.add('本周还没记录花费');
      }
      if (pendingTasks > 0) {
        parts.add('还有 $pendingTasks 件待办没完成');
      }
      parts.add('点开看看本周时间线？');
      return parts.join('，');
    } catch (_) {
      return '本周时间线已就绪，点开看看吧';
    }
  }

  static String _formatAmount(Decimal amount) {
    final str = amount.toString();
    if (str.contains('.')) {
      final parts = str.split('.');
      return '${parts[0]}.${parts[1].padRight(2, '0').substring(0, 2)}';
    }
    return str;
  }

  static DateTime _startOfWeek(DateTime now) {
    // 周一作为一周开始
    final weekday = now.weekday; // Monday = 1
    final monday = DateTime(now.year, now.month, now.day - (weekday - 1));
    return monday;
  }

  /// 计算下一个周日 20:00 (本地时区)
  static tz.TZDateTime _nextSundayAt20(DateTime now) {
    final tzNow = now is tz.TZDateTime ? now : tz.TZDateTime.from(now, tz.local);
    // weekday: Mon=1..Sun=7
    var daysUntilSunday = (DateTime.sunday - tzNow.weekday) % 7;
    var candidate = tz.TZDateTime(
      tz.local,
      tzNow.year,
      tzNow.month,
      tzNow.day + daysUntilSunday,
      20,
      0,
    );
    // 如果今天就是周日且已过 20:00，下一个周日
    if (!candidate.isAfter(tzNow)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }
}
