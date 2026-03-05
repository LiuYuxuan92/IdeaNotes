import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/models/note.dart';
import '../notedetail/note_detail_screen.dart';
import '../notelist/note_list_item.dart';
import '../notelist/bloc/note_list_bloc.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      context.read<NoteListBloc>().add(SearchNotes(query));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索笔记内容...',
            border: InputBorder.none,
          ),
          onSubmitted: (value) {
            _debounce?.cancel();
            context.read<NoteListBloc>().add(SearchNotes(value));
          },
          onChanged: _onSearchChanged,
        ),
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _debounce?.cancel();
                context.read<NoteListBloc>().add(const SearchNotes(''));
              },
            ),
        ],
      ),
      body: BlocBuilder<NoteListBloc, NoteListState>(
        builder: (context, state) {
          return _buildBody(state);
        },
      ),
    );
  }

  Widget _buildBody(NoteListState state) {
    final query = state.searchQuery;

    if (query.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '输入关键词搜索笔记',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (state.filteredNotes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '未找到相关笔记',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.filteredNotes.length,
      itemBuilder: (context, index) {
        final note = state.filteredNotes[index];
        return NoteListItem(
          note: note,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => NoteDetailScreen(note: note),
              ),
            );
          },
        );
      },
    );
  }
}
