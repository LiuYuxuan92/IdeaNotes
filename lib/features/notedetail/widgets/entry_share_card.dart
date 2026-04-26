import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/design_system.dart';
import '../../../core/query/entry_record.dart';

/// 把单条 entry 渲染成精美方形卡片图片，用于分享到微信 / 朋友圈 / 微博等。
///
/// 用法：
/// ```dart
/// await EntryShareCardExporter().shareEntry(context, entry);
/// ```
class EntryShareCardExporter {
  Future<void> shareEntry(BuildContext context, EntryRecord entry) async {
    final controller = ScreenshotController();

    final bytes = await controller.captureFromWidget(
      _ShareCardSurface(entry: entry),
      delay: const Duration(milliseconds: 80),
      pixelRatio: 3,
      context: context,
    );
    if (bytes.isEmpty) return;

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/idea_notes_share_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'IdeaNotes · ${entry.title}',
    );
  }

  /// 仅预览（用于调试）。返回原始 PNG 字节。
  Future<Uint8List> renderToPng(BuildContext context, EntryRecord entry) async {
    final controller = ScreenshotController();
    return controller.captureFromWidget(
      _ShareCardSurface(entry: entry),
      delay: const Duration(milliseconds: 80),
      pixelRatio: 3,
      context: context,
    );
  }
}

/// 分享卡片视觉。固定 360×480 的方形偏长卡片，浅渐变 + 主题色块。
class _ShareCardSurface extends StatelessWidget {
  final EntryRecord entry;

  const _ShareCardSurface({required this.entry});

  @override
  Widget build(BuildContext context) {
    final accent = _accentForType(entry.entryType, entry.domain);
    final typeLabel = _typeLabel(entry);
    final amount = _amountLabel(entry);
    final occurredAt = entry.occurredAt ?? entry.occurredDate;
    final dateLabel =
        '${occurredAt.year}年${occurredAt.month}月${occurredAt.day}日';

    return Container(
      width: 360,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.08),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部品牌 + 类型 pill
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.inkBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'IdeaNotes',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // 主标题
          Text(
            entry.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          if (entry.summary?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              entry.summary!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 24),
          // 金额（如有）
          if (amount != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  amount,
                  style: TextStyle(
                    color: accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          // 元信息行
          Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                dateLabel,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (entry.categoryL1?.trim().isNotEmpty == true) ...[
                const SizedBox(width: 12),
                Container(
                  width: 3,
                  height: 3,
                  decoration: const BoxDecoration(
                    color: AppColors.textMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  entry.categoryL1!.trim(),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          Container(height: 1, color: accent.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          // 底部署名
          Row(
            children: [
              const Text(
                '记一笔，AI 帮你整理',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.auto_awesome_rounded,
                color: accent.withValues(alpha: 0.6),
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _typeLabel(EntryRecord entry) {
    switch (entry.entryType) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      case 'task':
        return entry.domain == 'health' ? '健康待办' : '待办';
      case 'appointment':
        return '安排';
      case 'health_record':
      case 'healthrecord':
        return '健康记录';
      case 'vaccination':
        return '疫苗';
      case 'medication':
        return '用药';
      case 'metric':
        return '指标';
      case 'memo':
        return '备忘';
      default:
        return '记录';
    }
  }

  static Color _accentForType(String entryType, String domain) {
    if (entryType == 'expense' || entryType == 'income') {
      return AppColors.warning;
    }
    if (entryType == 'task' || entryType == 'appointment') {
      return AppColors.inkBlue;
    }
    if (domain == 'health' ||
        entryType == 'health_record' ||
        entryType == 'vaccination' ||
        entryType == 'medication' ||
        entryType == 'metric') {
      return AppColors.success;
    }
    return AppColors.aiAccent;
  }

  static String? _amountLabel(EntryRecord entry) {
    if (entry.amountValue == null) return null;
    final currency =
        (entry.amountCurrency?.trim().isNotEmpty == true) ? entry.amountCurrency!.trim() : 'CNY';
    final symbol = currency == 'CNY' ? '¥' : '$currency ';
    return '$symbol${entry.amountValue}';
  }
}
