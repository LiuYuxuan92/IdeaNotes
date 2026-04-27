import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/design_system.dart';
import '../../core/backup/backup_service.dart';
import '../../core/config/api_key_storage.dart';
import '../../core/diagnostics/error_log.dart';
import '../../core/notifications/weekly_review_notifier.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _isLoading = true;
  bool _hasKey = false;
  bool _obscure = true;
  bool _isSaving = false;
  bool _isBackupBusy = false;
  List<File> _backups = const [];

  @override
  void initState() {
    super.initState();
    _loadKey();
    _refreshBackups();
  }

  Future<void> _refreshBackups() async {
    try {
      final files = await BackupService.instance.listBackups();
      if (!mounted) return;
      setState(() => _backups = files);
    } catch (_) {
      // 列出备份失败不阻塞页面
    }
  }

  Future<void> _loadKey() async {
    final key = await ApiKeyStorage.instance.getDeepSeekApiKey();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _hasKey = key != null && key.isNotEmpty;
      if (_hasKey) {
        _controller.text = key!;
      }
    });
  }

  Future<void> _saveKey() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() => _isSaving = true);
    await ApiKeyStorage.instance.setDeepSeekApiKey(key);
    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hasKey = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key 已保存')),
    );
  }

  Future<void> _enableWeeklyReview() async {
    final notifier = WeeklyReviewNotifier();
    final granted = await notifier.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未授权通知权限，请到系统设置开启。')),
      );
      return;
    }
    await notifier.scheduleNextWeeklyReview();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已安排下周日 20:00 推送本周回顾。')),
    );
  }

  Future<void> _previewWeeklyReview() async {
    final notifier = WeeklyReviewNotifier();
    final granted = await notifier.requestPermissions();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未授权通知权限，请到系统设置开启。')),
      );
      return;
    }
    await notifier.showNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已发送一条试看通知。')),
    );
  }

  Future<void> _disableWeeklyReview() async {
    await WeeklyReviewNotifier().cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已关闭本周回顾推送。')),
    );
  }

  Future<void> _runBackupNow() async {
    if (_isBackupBusy) return;
    setState(() => _isBackupBusy = true);
    try {
      final result = await BackupService.instance.exportBackup();
      await _refreshBackups();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导出备份：${result.noteCount} 条笔记，${_formatBytes(result.sizeBytes)}',
          ),
        ),
      );
    } catch (e, st) {
      ErrorLog.instance.error('backup.manual', '手动备份失败',
          error: e, stack: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _isBackupBusy = false);
    }
  }

  Future<void> _exportLatestToDownloads() async {
    if (_backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可导出的备份，请先点「立即备份」。')),
      );
      return;
    }
    setState(() => _isBackupBusy = true);
    try {
      final ok = await BackupService.instance.exportToDownloads(_backups.first);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '已复制到 Download/IdeaNotes/'
                : '复制到 Download 失败，请查看错误日志。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBackupBusy = false);
    }
  }

  Future<void> _shareLatestBackup() async {
    if (_backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可分享的备份。')),
      );
      return;
    }
    await Share.shareXFiles(
      [XFile(_backups.first.path)],
      subject: 'IdeaNotes 备份',
      text: '附件为 IdeaNotes 数据备份（含笔记、图片、结构化记录）。',
    );
  }

  Future<void> _restoreFlow() async {
    final source = await showModalBottomSheet<_RestoreSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '从哪里恢复？',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('最近的自动备份'),
              subtitle: Text(
                _backups.isEmpty
                    ? '暂无可用备份'
                    : '${_backups.length} 份，最新 ${_formatTime(_backups.first.statSync().modified)}',
              ),
              enabled: _backups.isNotEmpty,
              onTap: _backups.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, _RestoreSource.recent),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('选择 zip 文件...'),
              subtitle: const Text('从文件管理器/云盘选择一个备份'),
              onTap: () => Navigator.pop(ctx, _RestoreSource.picker),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    File? zipFile;
    if (source == _RestoreSource.recent) {
      zipFile = await _pickFromRecent();
    } else {
      zipFile = await _pickViaFilePicker();
    }
    if (zipFile == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: Text(
          '将用此备份覆盖当前所有笔记与图片：\n\n'
          '${zipFile?.path.split(Platform.pathSeparator).last}\n\n'
          '当前数据会先改名为 *.pre_restore 以便人工回退。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBackupBusy = true);
    final result = await BackupService.instance.restoreBackup(zipFile);
    if (!mounted) return;
    setState(() => _isBackupBusy = false);
    await _refreshBackups();
    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '恢复成功（${result.restoredNoteCount ?? 0} 条笔记）。建议手动重启应用。',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败：${result.errorMessage ?? '未知错误'}')),
      );
    }
  }

  Future<File?> _pickFromRecent() async {
    if (_backups.isEmpty) return null;
    return showDialog<File>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要恢复的备份'),
        children: _backups.take(10).map((file) {
          final stat = file.statSync();
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, file),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.path.split(Platform.pathSeparator).last),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(stat.modified)} · ${_formatBytes(stat.size)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<File?> _pickViaFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: false,
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  String _formatBytes(int bytes) {
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String _formatTime(DateTime t) {
    return DateFormat('yyyy-MM-dd HH:mm').format(t);
  }

  Future<void> _shareErrorLog() async {
    final files = await ErrorLog.instance.latestLogFiles();
    if (!mounted) return;
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无错误日志。')),
      );
      return;
    }
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
      subject: 'IdeaNotes 错误日志',
      text: '附件为最近的应用诊断日志（JSON-lines）。',
    );
  }

  Future<void> _clearKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('清除后 AI 功能将不可用，确定要清除 API Key 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiKeyStorage.instance.clearDeepSeekApiKey();
    unawaited(HapticFeedback.mediumImpact());
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _controller.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key 已清除')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                children: [
                  // Header card
                  AppSurface(
                    padding: const EdgeInsets.all(20),
                    radius: 24,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.inkBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.key_rounded,
                            color: AppColors.inkBlue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DeepSeek API Key',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _hasKey ? '已配置，AI 功能可用' : '未配置，请输入后保存',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _hasKey
                                          ? AppColors.success
                                          : AppColors.warning,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _hasKey
                              ? Icons.check_circle_rounded
                              : Icons.warning_amber_rounded,
                          color: _hasKey ? AppColors.success : AppColors.warning,
                          size: 28,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Input section
                  Text(
                    'API Key',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    obscureText: _obscure,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'sk-xxxxxxxxxxxxxxxx',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.5),
                        fontFamily: 'monospace',
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: AppColors.inkBlue,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveKey,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: Text(_isSaving ? '保存中...' : '保存'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (_hasKey) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _clearKey,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18, color: AppColors.error),
                          label: const Text('清除',
                              style: TextStyle(color: AppColors.error)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Weekly review card
                  AppSurface(
                    padding: const EdgeInsets.all(20),
                    radius: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.aiAccent
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.notifications_active_rounded,
                                color: AppColors.aiAccent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '本周回顾推送',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '每周日晚 8 点弹出一条本周记录摘要，含花费、待办与笔数。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          height: 1.5,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _enableWeeklyReview,
                                icon: const Icon(
                                    Icons.event_repeat_rounded,
                                    size: 18),
                                label: const Text('开启 / 重排'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _previewWeeklyReview,
                                icon: const Icon(
                                    Icons.notifications_outlined,
                                    size: 18),
                                label: const Text('立即试一下'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _disableWeeklyReview,
                            icon: const Icon(Icons.alarm_off_rounded, size: 16),
                            label: const Text('关闭推送'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Backup card
                  AppSurface(
                    padding: const EdgeInsets.all(20),
                    radius: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.success
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.cloud_download_rounded,
                                color: AppColors.success,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '数据备份',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _backups.isEmpty
                                        ? '尚未创建任何备份'
                                        : '最近：${_formatTime(_backups.first.statSync().modified)} · 共 ${_backups.length} 份',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          height: 1.5,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _isBackupBusy ? null : _runBackupNow,
                                icon: _isBackupBusy
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_alt_rounded,
                                        size: 18),
                                label: const Text('立即备份'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isBackupBusy ? null : _restoreFlow,
                                icon: const Icon(Icons.restore_rounded,
                                    size: 18),
                                label: const Text('恢复备份'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: _isBackupBusy
                                    ? null
                                    : _exportLatestToDownloads,
                                icon: const Icon(Icons.download_rounded,
                                    size: 16),
                                label: const Text('另存到 Download'),
                              ),
                            ),
                            Expanded(
                              child: TextButton.icon(
                                onPressed:
                                    _isBackupBusy ? null : _shareLatestBackup,
                                icon: const Icon(Icons.ios_share_rounded,
                                    size: 16),
                                label: const Text('分享最新备份'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Diagnostics card
                  AppSurface(
                    padding: const EdgeInsets.all(20),
                    radius: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.warning
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.bug_report_rounded,
                                color: AppColors.warning,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '诊断日志',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '保存最近 5 段（每段 256KB）应用错误记录，本地存储不上传。',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          height: 1.5,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _shareErrorLog,
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: const Text('分享错误日志'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info section
                  AppSurface(
                    padding: const EdgeInsets.all(16),
                    radius: 16,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 18, color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Text(
                              '说明',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '• API Key 仅存储在本地设备，不会上传到任何服务器\n'
                          '• 用于驱动 AI 文本理解、OCR 纠错等功能\n'
                          '• 从 platform.deepseek.com 获取 Key',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.textMuted,
                                height: 1.6,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

enum _RestoreSource { recent, picker }
