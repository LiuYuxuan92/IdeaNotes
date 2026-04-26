import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import 'bloc/canvas_bloc.dart';

class CanvasToolbar extends StatelessWidget {
  /// 复位视图（100%、回 World 原点）。
  final VoidCallback? onFitToScreen;

  /// 把所有笔迹适配到当前视口（无限画布场景）。
  final VoidCallback? onFitToInk;

  /// 当前 viewport transform，用于显示缩放百分比。
  /// 传 null 时不显示百分比。
  final TransformationController? viewTransform;

  const CanvasToolbar({
    super.key,
    this.onFitToScreen,
    this.onFitToInk,
    this.viewTransform,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        final isCompact = context.isCompact;
        const tools = [
          _ToolSpec(
            tool: CanvasTool.pen,
            icon: Icons.edit_rounded,
            label: '墨蓝笔',
            swatch: AppColors.inkBlue,
          ),
          _ToolSpec(
            tool: CanvasTool.bluePen,
            icon: Icons.brush_rounded,
            label: '石板蓝',
            swatch: Color(0xFF3C617C),
          ),
          _ToolSpec(
            tool: CanvasTool.redPen,
            icon: Icons.draw_rounded,
            label: '批注红',
            swatch: Color(0xFF8A4145),
          ),
          _ToolSpec(
            tool: CanvasTool.pencil,
            icon: Icons.mode_edit_outline_rounded,
            label: '铅笔',
            swatch: Color(0xFF62717D),
          ),
          _ToolSpec(
            tool: CanvasTool.eraser,
            icon: Icons.auto_fix_high_rounded,
            label: '橡皮',
            swatch: AppColors.textMuted,
          ),
        ];

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.isLarge ? 920 : double.infinity,
          ),
          child: AppSurface(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 10 : 14,
              isCompact ? 10 : 12,
              isCompact ? 10 : 14,
              isCompact ? 10 : 12,
            ),
            radius: isCompact ? 28 : 32,
            backgroundColor: Colors.white.withValues(alpha: 0.97),
            border: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: AppShadows.floating,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isCompact)
                      Text(
                        _ToolbarLead.labelForTool(state.currentTool),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      )
                    else
                      _ToolbarLead(tool: state.currentTool),
                    const Spacer(),
                    _CompactActionButton(
                      icon: Icons.undo_rounded,
                      label: '撤销',
                      enabled: state.canUndo,
                      onTap: state.canUndo
                          ? () => context.read<CanvasBloc>().add(StrokeUndone())
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _CompactActionButton(
                      icon: Icons.redo_rounded,
                      label: '重做',
                      enabled: state.canRedo,
                      onTap: state.canRedo
                          ? () => context.read<CanvasBloc>().add(StrokeRedone())
                          : null,
                    ),
                    const SizedBox(width: 8),
                    _CompactActionButton(
                      icon: state.stylusOnlyMode
                          ? Icons.draw_rounded
                          : Icons.touch_app_rounded,
                      label: state.stylusOnlyMode ? '仅触控笔' : '手指+笔',
                      onTap: () {
                        HapticFeedback.selectionClick(); // Add haptic feedback
                        context.read<CanvasBloc>().add(StylusOnlyModeToggled());
                      },
                    ),
                    const SizedBox(width: 8),
                    if (viewTransform != null) ...[
                      _ZoomBadge(
                        controller: viewTransform!,
                        onTap: onFitToScreen,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onFitToInk != null) ...[
                      _CompactActionButton(
                        icon: Icons.center_focus_strong_rounded,
                        label: '适配笔迹',
                        enabled: state.strokes.isNotEmpty,
                        onTap: state.strokes.isNotEmpty ? onFitToInk : null,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onFitToScreen != null) ...[
                      _CompactActionButton(
                        icon: Icons.fit_screen_rounded,
                        label: '复位视图',
                        onTap: onFitToScreen,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _CompactActionButton(
                      icon: Icons.delete_sweep_rounded,
                      label: '清空画布',
                      isDanger: true,
                      onTap: () => _showClearDialog(context),
                    ),
                  ],
                ),
                SizedBox(height: isCompact ? 8 : 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tools.length; i++) ...[
                        _ToolPill(
                          spec: tools[i],
                          isSelected: state.currentTool == tools[i].tool,
                          onTap: () {
                            HapticFeedback.selectionClick(); // Add haptic feedback
                            context
                                .read<CanvasBloc>()
                                .add(CanvasToolChanged(tools[i].tool));
                          },
                        ),
                        if (i != tools.length - 1) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空整张画布？'),
        content: const Text('这会移除当前所有笔迹。如果只是写错一点，建议先用撤销或橡皮。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('继续保留'),
          ),
          TextButton(
            onPressed: () {
              context.read<CanvasBloc>().add(CanvasCleared());
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
  }
}

class _ToolbarLead extends StatelessWidget {
  final CanvasTool tool;

  const _ToolbarLead({required this.tool});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '画布工具',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          labelForTool(tool),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
              ),
        ),
      ],
    );
  }

  static String labelForTool(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.pen:
        return '当前使用墨蓝笔';
      case CanvasTool.bluePen:
        return '当前使用石板蓝';
      case CanvasTool.redPen:
        return '当前使用批注红';
      case CanvasTool.pencil:
        return '当前使用铅笔';
      case CanvasTool.eraser:
        return '当前使用橡皮';
    }
  }
}

class _ToolPill extends StatelessWidget {
  final _ToolSpec spec;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolPill({
    required this.spec,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;

    return Tooltip(
      message: spec.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 12,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? spec.swatch.withValues(alpha: 0.10)
                : const Color(0xFFF5F7F8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSelected
                  ? spec.swatch.withValues(alpha: 0.50)
                  : Theme.of(context).colorScheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: isCompact ? 30 : 34,
                height: isCompact ? 30 : 34,
                decoration: BoxDecoration(
                  color: spec.swatch
                      .withValues(alpha: isSelected ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(isCompact ? 12 : 14),
                ),
                child: Icon(spec.icon,
                    size: isCompact ? 16 : 18, color: spec.swatch),
              ),
              SizedBox(width: isCompact ? 8 : 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isSelected ? spec.swatch : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  SizedBox(height: isCompact ? 3 : 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: isSelected
                        ? (isCompact ? 20 : 24)
                        : (isCompact ? 14 : 18),
                    height: isCompact ? 3 : 4,
                    decoration: BoxDecoration(
                      color: spec.swatch
                          .withValues(alpha: isSelected ? 1.0 : 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDanger;
  final VoidCallback? onTap;

  const _CompactActionButton({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.isDanger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;
    final foreground = !enabled
        ? AppColors.disabled
        : isDanger
            ? AppColors.error
            : AppColors.inkBlue;
    final background = !enabled
        ? const Color(0xFFF0F2F4)
        : isDanger
            ? const Color(0xFFF9EFF0)
            : const Color(0xFFEAF1F4);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48), // Add minimum size
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 10 : 12,
              vertical: isCompact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                if (context.isMedium || context.isLarge) ...[
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolSpec {
  final CanvasTool tool;
  final IconData icon;
  final String label;
  final Color swatch;

  const _ToolSpec({
    required this.tool,
    required this.icon,
    required this.label,
    required this.swatch,
  });
}

/// 显示当前 viewport 缩放百分比的小徽标，点击复位视图。
class _ZoomBadge extends StatelessWidget {
  final TransformationController controller;
  final VoidCallback? onTap;

  const _ZoomBadge({required this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final scale = controller.value.storage[0];
        final percent = (scale * 100).round().clamp(1, 9999);
        return Tooltip(
          message: '缩放 $percent%（点击复位）',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 10 : 12,
                  vertical: isCompact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1F4),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.zoom_in_rounded,
                      size: 18,
                      color: AppColors.inkBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$percent%',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.inkBlue,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
