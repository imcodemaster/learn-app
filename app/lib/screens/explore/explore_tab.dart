import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/course.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/course_widgets.dart';
import '../home/home_tab.dart' show openCourse;

class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key, this.initialCategory, this.focusSearch = false, this.requestId = 0});

  final String? initialCategory;
  final bool focusSearch;
  final int requestId;

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  static const _sorts = <String, String>{
    'recommended': 'Recommended',
    'popular': 'Most popular',
    'newest': 'Newest',
    'price_low': 'Price: low to high',
    'price_high': 'Price: high to low',
  };

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;
  late final Session _session;
  int _seenVersion = 0;

  String? _category;
  String _sort = 'recommended';
  String? _price;
  List<CourseCategory> _categories = const [];

  final List<CourseSummary> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _session = context.read<Session>();
    _seenVersion = _session.version;
    _session.addListener(_onSessionChanged);
    _category = widget.initialCategory;
    _scrollController.addListener(_onScroll);
    _loadCategories();
    _reset();
  }

  @override
  void didUpdateWidget(covariant ExploreTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.requestId != oldWidget.requestId) {
      _category = widget.initialCategory;
      if (widget.focusSearch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
      _reset();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (_session.version != _seenVersion) {
      _seenVersion = _session.version;
      _reset();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await CatalogApi(_session.api).categories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // Category chips are optional.
    }
  }

  Future<void> _reset() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await CatalogApi(_session.api).courses(
        search: _searchController.text,
        category: _category,
        sort: _sort,
        price: _price,
        page: _page + 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.meta.page;
        _hasMore = page.meta.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = errorText(error);
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore courses')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _reset(),
              decoration: fieldDecoration(
                'Search courses',
                icon: Icons.search,
                suffix: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _reset();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: [
                _chip('All', _category == null, () {
                  _category = null;
                  _reset();
                }),
                for (final category in _categories)
                  _chip(category.name, _category == category.slug, () {
                    _category = category.slug;
                    _reset();
                  }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                _chip('Free', _price == 'free', () {
                  _price = _price == 'free' ? null : 'free';
                  _reset();
                }),
                _chip('Paid', _price == 'paid', () {
                  _price = _price == 'paid' ? null : 'paid';
                  _reset();
                }),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: (value) {
                    _sort = value;
                    _reset();
                  },
                  itemBuilder: (context) => [
                    for (final entry in _sorts.entries) PopupMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 20, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(_sorts[_sort] ?? 'Sort',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
      ),
    );
  }

  Widget _results() {
    if (_items.isEmpty) {
      if (_loading) return const LoadingView();
      if (_error != null) return ErrorView(message: _error!, onRetry: _reset);
      return const EmptyView(
        icon: Icons.search_off,
        title: 'No courses found',
        message: 'Try another word or category.',
      );
    }
    return RefreshIndicator(
      onRefresh: _reset,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index < _items.length) {
            final course = _items[index];
            return CourseTile(course: course, onTap: () => openCourse(context, course));
          }
          if (_loading) {
            return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
          }
          if (_error != null) {
            return Center(child: TextButton(onPressed: _loadMore, child: const Text('Couldn’t load more. Try again')));
          }
          return const SizedBox(height: 12);
        },
      ),
    );
  }
}
