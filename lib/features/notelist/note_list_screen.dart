import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import '../../core/models/note.dart';
import '../canvas/canvas_screen.dart';
import '../notedetail/note_detail_screen.dart';
import '../records/records_hub_screen.dart';
import '../search/search_screen.dart';
import 'bloc/note_list_bloc.dart';
import 'note_list_item.dart';

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    context.read<NoteListBloc>().add(LoadNotes());
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal =
        context.isLarge ? 32.0 : (context.isCompact ? 16.0 : 20.0);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewNote,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.isCompact ? '记一页' : '新建笔记'),
        tooltip: '新建笔记',
      ),
      body: SafeArea(
        child: BlocBuilder<NoteListBloc, NoteListState>(
          builder: (context, state) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<NoteListBloc>().add(RefreshNotes());
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 16, horizontal, 12),
                    sliver: SliverToBoxAdapter(
                      child: _buildHeader(context, state),
                    ),
                  ),
                  if (_isSearchExpanded)
                    SliverPadding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 0, horizontal, 12),
                      sliver: SliverToBoxAdapter(
                        child: _buildSearchBar(context),
                      ),
                    ),
                  if (state.status == NoteListStatus.loaded &&
                      state.filteredNotes.isNotEmpty)
                    SliverPadding(
                      padding:
                          EdgeInsets.fromLTRB(horizontal, 2, horizontal, 8),
                      sliver: const SliverToBoxAdapter(
                        child: _ListSectionHeader(),
                      ),
                    ),
                  SliverPadding(
                    padding:
                        EdgeInsets.fromLTRB(horizontal, 0, horizontal, 120),
                    sliver: _buildBody(context, state),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NoteListState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHero(context, state),
        const SizedBox(height: 12),
        _buildPrimaryActions(context),
        const SizedBox(height: 12),
        _buildRecordsPanel(context),
      ],
    );
  }

  Widget _buildHero(BuildContext context, NoteListState state) {
    final notesCount = state.notes.length;
    final visibleCount = state.filteredNotes.length;
    final recognizedCount = state.notes
        .where((note) => (note.recognizedText ?? '').trim().isNotEmpty)
        .length;

    return AppSurface(
      padding: EdgeInsets.all(context.isCompact ? 16 : 20),
      radius: context.isCompact ? 28 : 32,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('IdeaNotes',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Text(
                      context.isCompact ? '先记下来，再慢慢查' : '把手写页整理成能继续查询的记录',
                      style: context.isCompact
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _heroDescription(state),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  IconButton.filledTonal(
                    onPressed: _toggleSearch,
                    tooltip: _isSearchExpanded ? '收起快速筛选' : '展开快速筛选',
                    icon: Icon(
                      _isSearchExpanded
                          ? Icons.close_rounded
                          : Icons.tune_rounded,
                    ),
                  ),
                  const SizedBox(height: 8),
                  IconButton.filledTonal(
                    onPressed: _openSearchCenter,
                    tooltip: '打开搜索页',
                    icon: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(
                icon: Icons.library_books_outlined,
                label: '$notesCount 页笔记',
              ),
              _HeroPill(
                icon: Icons.text_snippet_outlined,
                label: '$recognizedCount 页已识别',
                accent: recognizedCount > 0
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
              _HeroPill(
                icon: Icons.visibility_outlined,
                label: state.searchQuery.isEmpty
                    ? '当前显示 $visibleCount 页'
                    : '筛到 $visibleCount 页',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _heroDescription(NoteListState state) {
    if (state.searchQuery.isNotEmpty) {
      return '你现在正在按关键词筛选，列表里只保留和搜索词相关的笔记。';
    }
    if (state.notes.isEmpty) {
      return '先写一页，再识别，再把花费、事项和健康记录沉淀成可查询的数据。';
    }
    return '上面是操作入口，下面是最近笔记。支出分类、待办时间线、健康记录都可以直接点进去看。';
  }

  Widget _buildPrimaryActions(BuildContext context) {
    final cards = [
      _ActionPanelSpec(
        icon: Icons.draw_rounded,
        title: '记一页手写',
        description: '直接进入画布，先把事情写下来。',
        onTap: _createNewNote,
      ),
      _ActionPanelSpec(
        icon: Icons.search_rounded,
        title: '搜全部内容',
        description: '搜索 OCR 文本、事项、金额和关键词。',
        onTap: _openSearchCenter,
      ),
    ];

    if (context.isCompact) {
      return Column(
        children: cards
            .map(
              (spec) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ActionPanelCard(spec: spec),
              ),
            )
            .toList(growable: false),
      );
    }

    return Row(
      children: cards
          .map(
            (spec) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: spec == cards.first ? 6 : 0,
                  left: spec == cards.last ? 6 : 0,
                ),
                child: _ActionPanelCard(spec: spec),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildRecordsPanel(BuildContext context) {
    final cards = [
      _RecordsShortcutSpec(
        title: '支出分类',
        description: '看近一段时间记过哪些花费，按分类汇总金额。',
        icon: Icons.attach_money_rounded,
        accent: AppColors.warning,
        onTap: () => _openRecordsHub(RecordsHubTab.finance),
      ),
      _RecordsShortcutSpec(
        title: '待办时间线',
        description: '按日期回看待办、提醒和当天发生的事项。',
        icon: Icons.event_note_rounded,
        accent: AppColors.inkBlue,
        onTap: () => _openRecordsHub(RecordsHubTab.tasks),
      ),
      _RecordsShortcutSpec(
        title: '健康记录',
        description: '查疫苗、用药、就诊和相关事项的时间线。',
        icon: Icons.vaccines_rounded,
        accent: AppColors.success,
        onTap: () => _openRecordsHub(RecordsHubTab.health),
      ),
    ];

    return AppSurface(
      padding: EdgeInsets.all(context.isCompact ? 16 : 18),
      radius: context.isCompact ? 28 : 30,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            eyebrow: '结构化记录',
            title: '不是占位入口，点进去就能查',
            description: '如果这页已经识别并保存过，下面这些入口会直接查询现有结构化数据。',
          ),
          const SizedBox(height: 16),
          if (context.isCompact)
            Column(
              children: cards
                  .map(
                    (spec) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RecordsShortcutCard(spec: spec),
                    ),
                  )
                  .toList(growable: false),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cards
                  .map(
                    (spec) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: spec == cards.last ? 0 : 8,
                        ),
                        child: _RecordsShortcutCard(spec: spec),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(12),
      radius: 28,
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜标题关键词、识别文本或待办内容',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    context.read<NoteListBloc>().add(const SearchNotes(''));
                  },
                  tooltip: '清空搜索词',
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: (value) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 220), () {
            context.read<NoteListBloc>().add(SearchNotes(value));
          });
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, NoteListState state) {
    switch (state.status) {
      case NoteListStatus.initial:
      case NoteListStatus.loading:
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        );
      case NoteListStatus.error:
        return SliverFillRemaining(
          hasScrollBody: false,
          child: _buildErrorState(context, state.errorMessage),
        );
      case NoteListStatus.loaded:
        if (state.filteredNotes.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(context, state.searchQuery.isNotEmpty),
          );
        }
        if (context.isLarge) {
          return SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final note = state.filteredNotes[index];
                return NoteListItem(
                  note: note,
                  isGridMode: true,
                  onTap: () => _openNoteDetail(note),
                  onDelete: () => _deleteNote(note.id),
                );
              },
              childCount: state.filteredNotes.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              mainAxisExtent: 352,
            ),
          );
        }
        return SliverList.separated(
          itemCount: state.filteredNotes.length,
          itemBuilder: (context, index) {
            final note = state.filteredNotes[index];
            return NoteListItem(
              note: note,
              onTap: () => _openNoteDetail(note),
              onDelete: () => _deleteNote(note.id),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 0),
        );
    }
  }

  Widget _buildEmptyState(BuildContext context, bool isSearching) {
    return EmptyStateView(
      icon:
          isSearching ? Icons.search_off_rounded : Icons.auto_stories_outlined,
      title: isSearching ? '没有找到相关笔记' : '先写下第一条想法吧',
      description: isSearching
          ? '换一个关键词，或者打开结构化记录按分类、时间线继续查。'
          : '新建一页手写内容后，可以继续识别、编辑，再整理成可查询的信息。',
      action: isSearching
          ? TextButton(
              onPressed: () {
                _searchController.clear();
                context.read<NoteListBloc>().add(const SearchNotes(''));
              },
              child: const Text('清空搜索词'),
            )
          : ElevatedButton.icon(
              onPressed: _createNewNote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建第一条笔记'),
            ),
    );
  }

  Widget _buildErrorState(BuildContext context, String? errorMessage) {
    return EmptyStateView(
      icon: Icons.cloud_off_rounded,
      title: '笔记列表暂时打不开',
      description: errorMessage?.trim().isNotEmpty == true
          ? '$errorMessage\n你可以先重试，若仍失败再检查本地存储权限。'
          : '请先刷新一次；如果问题持续，再检查本地存储是否可用。',
      action: ElevatedButton.icon(
        onPressed: () => context.read<NoteListBloc>().add(LoadNotes()),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新加载'),
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        context.read<NoteListBloc>().add(const SearchNotes(''));
      }
    });
  }

  void _openSearchCenter() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (context) => const SearchScreen()),
    );
  }

  void _openRecordsHub(RecordsHubTab tab) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => RecordsHubScreen(initialTab: tab),
      ),
    );
  }

  void _createNewNote() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => CanvasScreen(
          onSave: () => context.read<NoteListBloc>().add(RefreshNotes()),
        ),
      ),
    );
  }

  void _openNoteDetail(Note note) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => NoteDetailScreen(note: note),
      ),
    );
  }

  void _deleteNote(String noteId) {
    context.read<NoteListBloc>().add(DeleteNote(noteId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这条笔记已删除。')),
    );
  }
}

class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('最近笔记', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '按最近更新时间排序，方便快速回到刚记过的内容。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _HeroPill({
    required this.icon,
    required this.label,
    this.accent = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent == AppColors.success
            ? const Color(0xFFE7F2EC)
            : const Color(0xFFF2F5F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanelSpec {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ActionPanelSpec({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
}

class _ActionPanelCard extends StatelessWidget {
  final _ActionPanelSpec spec;

  const _ActionPanelCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: spec.onTap,
      borderRadius: BorderRadius.circular(26),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        radius: 26,
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE8EE),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(spec.icon, color: AppColors.inkBlue, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spec.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    spec.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _RecordsShortcutSpec {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _RecordsShortcutSpec({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

class _RecordsShortcutCard extends StatelessWidget {
  final _RecordsShortcutSpec spec;

  const _RecordsShortcutCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: spec.onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: spec.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: spec.accent.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: spec.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(spec.icon, color: spec.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spec.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spec.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: spec.accent),
          ],
        ),
      ),
    );
  }
}
