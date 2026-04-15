import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/design_system.dart';
import '../notedetail/note_detail_screen.dart';
import '../notelist/bloc/note_list_bloc.dart';
import '../notelist/note_list_item.dart';
import '../records/records_hub_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _didSyncInitialQuery = false;

  bool _isCompactQueryMode(BuildContext context, NoteListState state) {
    return context.isCompact && _hasActiveQuery(state);
  }

  bool _hasActiveQuery(NoteListState state) {
    return state.searchQuery.trim().isNotEmpty ||
        _searchController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 240), () {
      context.read<NoteListBloc>().add(SearchNotes(query));
    });
  }

  void _applySuggestedQuery(String query) {
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    context.read<NoteListBloc>().add(SearchNotes(query));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final horizontal =
        context.isLarge ? 32.0 : (context.isCompact ? 16.0 : 20.0);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<NoteListBloc, NoteListState>(
          builder: (context, state) {
            _syncControllerFromState(state.searchQuery);
            final isCompactQueryMode = _isCompactQueryMode(context, state);
            final topPadding =
                isCompactQueryMode ? (keyboardVisible ? 8.0 : 12.0) : 16.0;
            final sectionSpacing = isCompactQueryMode ? 10.0 : 16.0;
            final bottomPadding =
                isCompactQueryMode ? (keyboardVisible ? 10.0 : 14.0) : 20.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    topPadding,
                    horizontal,
                    bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(
                        context,
                        isCompactQueryMode: isCompactQueryMode,
                      ),
                      SizedBox(height: sectionSpacing),
                      _buildSearchHero(
                        context,
                        state,
                        isCompactQueryMode: isCompactQueryMode,
                        keyboardVisible: keyboardVisible,
                      ),
                      SizedBox(height: sectionSpacing),
                      Expanded(child: _buildBody(context, state)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _syncControllerFromState(String query) {
    if (_didSyncInitialQuery || query.isEmpty) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _didSyncInitialQuery = true;
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool isCompactQueryMode,
  }) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.maybePop(context),
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCompactQueryMode ? '搜索结果' : '搜索',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!isCompactQueryMode) ...[
                const SizedBox(height: 4),
                Text(
                  '全文搜索只搜 OCR 原文；按类型查请直接走下面的结构化入口。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHero(
    BuildContext context,
    NoteListState state, {
    required bool isCompactQueryMode,
    required bool keyboardVisible,
  }) {
    final query = state.searchQuery;
    final hasQuery = query.isNotEmpty;

    if (isCompactQueryMode) {
      return AppSurface(
        padding: EdgeInsets.fromLTRB(
          12,
          keyboardVisible ? 10 : 12,
          12,
          keyboardVisible ? 10 : 12,
        ),
        radius: 24,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFB)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              autofocus: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索笔记内容...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _debounce?.cancel();
                          context
                              .read<NoteListBloc>()
                              .add(const SearchNotes(''));
                          setState(() {});
                        },
                      ),
              ),
              onSubmitted: (value) {
                _debounce?.cancel();
                context.read<NoteListBloc>().add(SearchNotes(value));
                FocusScope.of(context).unfocus();
              },
              onChanged: (value) {
                setState(() {});
                _onSearchChanged(value);
              },
            ),
            if (!keyboardVisible) ...[
              const SizedBox(height: 8),
              Text(
                '已筛出 ${state.filteredNotes.length} 条结果',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      );
    }

    return AppSurface(
      padding: EdgeInsets.all(
          isCompactQueryMode ? 14 : (context.isCompact ? 16 : 20)),
      radius: context.isCompact ? 28 : 32,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFB)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            eyebrow: '全局搜索',
            title: isCompactQueryMode ? '结果优先显示' : '输入关键词搜索笔记',
            description: isCompactQueryMode
                ? '手机上会自动压缩顶部区域，避免结果被挤到屏幕外。'
                : '找原文内容时用关键词；按支出、待办、健康查时，直接走下面的结构化入口。',
          ),
          SizedBox(height: isCompactQueryMode ? 12 : 16),
          TextField(
            controller: _searchController,
            autofocus: !context.isCompact,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索笔记内容...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _debounce?.cancel();
                        context.read<NoteListBloc>().add(const SearchNotes(''));
                        setState(() {});
                      },
                    ),
            ),
            onSubmitted: (value) {
              _debounce?.cancel();
              context.read<NoteListBloc>().add(SearchNotes(value));
              FocusScope.of(context).unfocus();
            },
            onChanged: (value) {
              setState(() {});
              _onSearchChanged(value);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SuggestionChip(
                icon: Icons.history_rounded,
                label: hasQuery ? '当前关键词：$query' : '试试常见关键词',
              ),
              _InteractiveSuggestionChip(
                icon: Icons.sell_outlined,
                label: hasQuery ? '结果 ${state.filteredNotes.length} 条' : '花费',
                onTap: hasQuery ? null : () => _applySuggestedQuery('花费'),
              ),
              _InteractiveSuggestionChip(
                icon: Icons.vaccines_rounded,
                label: hasQuery ? '继续换词' : '疫苗',
                onTap: hasQuery ? null : () => _applySuggestedQuery('疫苗'),
              ),
              _InteractiveSuggestionChip(
                icon: Icons.event_note_rounded,
                label: hasQuery ? '搜明天' : '明天',
                onTap: () => _applySuggestedQuery('明天'),
              ),
            ],
          ),
          if (!isCompactQueryMode) ...[
            const SizedBox(height: 14),
            _buildQueryJumpRow(context),
          ],
        ],
      ),
    );
  }

  Widget _buildQueryJumpRow(BuildContext context) {
    final cards = [
      _JumpCard(
        icon: Icons.attach_money_rounded,
        title: '支出分类',
        subtitle: '按分类看花费',
        accent: AppColors.warning,
        onTap: () => _openRecordsHub(RecordsHubTab.finance),
      ),
      _JumpCard(
        icon: Icons.event_note_rounded,
        title: '待办时间线',
        subtitle: '按日期回看待办',
        accent: AppColors.inkBlue,
        onTap: () => _openRecordsHub(RecordsHubTab.tasks),
      ),
      _JumpCard(
        icon: Icons.vaccines_rounded,
        title: '健康记录',
        subtitle: '疫苗、用药和排便',
        accent: AppColors.success,
        onTap: () => _openRecordsHub(RecordsHubTab.health),
      ),
    ];

    if (context.isCompact) {
      return Column(
        children: cards
            .map(
              (card) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(width: double.infinity, child: card),
              ),
            )
            .toList(growable: false),
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: cards);
  }

  Widget _buildBody(BuildContext context, NoteListState state) {
    final query = state.searchQuery;
    final isCompactQueryMode = _isCompactQueryMode(context, state);

    if (query.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppSurface(
            isFlat: true,
            backgroundColor: const Color(0xFFF9FAFB),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search,
                      size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 14),
                  Text(
                    '输入关键词搜索笔记',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '可以搜 OCR 文本、事项、金额关键词；如果你想按分类或日期查，直接点上面的结构化入口。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (state.filteredNotes.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppSurface(
            isFlat: true,
            backgroundColor: const Color(0xFFF9FAFB),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.search_off,
                    size: 56,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '未找到相关笔记',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '试试换一个关键词，或者改走支出分类、待办时间线、健康记录入口继续查。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isCompactQueryMode) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: state.filteredNotes.length,
        itemBuilder: (context, index) {
          final note = state.filteredNotes[index];
          return NoteListItem(
            note: note,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => NoteDetailScreen(note: note),
                ),
              );
            },
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(text: '关键词：$query'),
            _InfoChip(text: '结果 ${state.filteredNotes.length} 条'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: state.filteredNotes.length,
            itemBuilder: (context, index) {
              final note = state.filteredNotes[index];
              return NoteListItem(
                note: note,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => NoteDetailScreen(note: note),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
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
}

class _SuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SuggestionChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveSuggestionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _InteractiveSuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1F4),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.inkBlue),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkBlue,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JumpCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _JumpCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
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

class _InfoChip extends StatelessWidget {
  final String text;

  const _InfoChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
