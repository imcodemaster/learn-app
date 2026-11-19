import 'package:flutter/material.dart';

import 'account/account_tab.dart';
import 'explore/explore_tab.dart';
import 'home/home_tab.dart';
import 'learning/my_learning_tab.dart';
import 'studycenter/study_center_tab.dart';

/// Bottom navigation with five tabs. Tabs keep their state when switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  static const home = 0;
  static const explore = 1;
  static const learning = 2;
  static const studyCenter = 3;
  static const account = 4;

  int _index = home;
  String? _exploreCategory;
  bool _exploreFocusSearch = false;
  int _exploreRequest = 0;

  void openTab(int index) => setState(() => _index = index);

  void openExplore({String? category, bool focusSearch = false}) {
    setState(() {
      _index = explore;
      _exploreCategory = category;
      _exploreFocusSearch = focusSearch;
      _exploreRequest++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomeTab(),
          ExploreTab(
            initialCategory: _exploreCategory,
            focusSearch: _exploreFocusSearch,
            requestId: _exploreRequest,
          ),
          const MyLearningTab(),
          const StudyCenterTab(),
          const AccountTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: openTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(
              icon: Icon(Icons.play_lesson_outlined), selectedIcon: Icon(Icons.play_lesson), label: 'My learning'),
          NavigationDestination(
              icon: Icon(Icons.event_seat_outlined), selectedIcon: Icon(Icons.event_seat), label: 'Study center'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}
