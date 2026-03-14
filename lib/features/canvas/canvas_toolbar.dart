import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import 'bloc/canvas_bloc.dart';

class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CanvasBloc, CanvasState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AppSurface(
            padding: const EdgeInsets.all(14),
            backgroundColor: const Color(0xFFF6F8F9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '画布工具',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ToolbarGroup(
                      label: '书写',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ToolButton(
                            icon: Icons.edit_rounded,
                            label: '墨蓝笔',
                            swatch: AppColors.inkBlue,
                            isSelected: state.currentTool == CanvasTool.pen,
                            onTap: () => context
                                .read<CanvasBloc>()
                                .add(const CanvasToolChanged(CanvasTool.pen)),
                          ),
                          _ToolButton(
                            icon: Icons.brush_rounded,
                            label: '石板蓝',
                            swatch: const Color(0xFF3C617C),
                            isSelected: state.currentTool == CanvasTool.bluePen,
                            onTap: () => context.read<CanvasBloc>().add(
                                const CanvasToolChanged(CanvasTool.bluePen)),
                          ),
                          _ToolButton(
                            icon: Icons.draw_rounded,
                            label: '批注红',
                            swatch: const Color(0xFF8A4145),
                            isSelected: state.currentTool == CanvasTool.redPen,
                            onTap: () => context.read<CanvasBloc>().add(
                                const CanvasToolChanged(CanvasTool.redPen)),
                          ),
                          _ToolButton(
                            icon: Icons.mode_edit_outline_rounded,
                            label: '铅笔',
                            swatch: const Color(0xFF62717D),
                            isSelected: state.currentTool == CanvasTool.pencil,
                            onTap: () => context.read<CanvasBloc>().add(
                                const CanvasToolChanged(CanvasTool.pencil)),
                          ),
                          _ToolButton(
                            icon: Icons.auto_fix_high_rounded,
                            label: '橡皮',
                            swatch: AppColors.textMuted,
                            isSelected: state.currentTool == CanvasTool.eraser,
                            onTap: () => context.read<CanvasBloc>().add(
                                const CanvasToolChanged(CanvasTool.eraser)),
                          ),
                        ],
                      ),
                    ),
                    _ToolbarGroup(
                      label: '回退',
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _ActionChip(
                            icon: Icons.undo_rounded,
                            label: '撤销',
                            enabled: state.canUndo,
                            onTap: state.canUndo
                                ? () => context
                                    .read<CanvasBloc>()
                                    .add(StrokeUndone())
                                : null,
                          ),
                          _ActionChip(
                            icon: Icons.redo_rounded,
                            label: '重做',
                            enabled: state.canRedo,
                            onTap: state.canRedo
                                ? () => context
                                    .read<CanvasBloc>()
                                    .add(StrokeRedone())
                                : null,
                          ),
                        ],
                      ),
                    ),
                    _ToolbarGroup(
                      label: '危险操作',
                      child: _ActionChip(
                        icon: Icons.delete_sweep_rounded,
                        label: '清空画布',
                        enabled: true,
                        isDanger: true,
                        onTap: () => _showClearDialog(context),
                      ),
                    ),
                  ],
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

class _ToolbarGroup extends StatelessWidget {
  final String label;
  final Widget child;

  const _ToolbarGroup({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color swatch;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.swatch,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color:
                isSelected ? const Color(0xFFDDE8EE) : const Color(0xFFF4F6F7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AppColors.selection : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: swatch, size: 20),
              const SizedBox(height: 8),
              Container(
                width: 18,
                height: 4,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? AppColors.inkBlue
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDanger;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.enabled,
    this.isDanger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? AppColors.disabled
        : isDanger
            ? AppColors.error
            : AppColors.inkBlue;
    final background = !enabled
        ? const Color(0xFFF0F2F4)
        : isDanger
            ? const Color(0xFFF8EDEE)
            : const Color(0xFFE9F0F3);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
