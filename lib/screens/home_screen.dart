import 'package:caffeine_tv/screens/movies_screen.dart';
import 'package:caffeine_tv/screens/search_screen.dart';
import 'package:caffeine_tv/screens/settings_screen.dart';
import 'package:caffeine_tv/screens/tv_shows_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _tabs = [
    _Tab(label: 'Movies', icon: Icons.movie),
    _Tab(label: 'TV', icon: Icons.tv),
    _Tab(label: 'Search', icon: Icons.search),
    _Tab(label: 'Settings', icon: Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Row(
        children: [
          _buildNavRail(context),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                MoviesScreen(),
                TvShowsScreen(),
                SearchScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRail(BuildContext context) {
    return Container(
      width: 120,
      color: const Color(0xFF111827),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_tabs.length, (i) {
          final tab = _tabs[i];
          final selected = _selectedIndex == i;
          return Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowUp && i > 0) {
                FocusScope.of(context).focusInDirection(TraversalDirection.up);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown && i < _tabs.length - 1) {
                FocusScope.of(context).focusInDirection(TraversalDirection.down);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                FocusScope.of(context).focusInDirection(TraversalDirection.right);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.select) {
                setState(() => _selectedIndex = i);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: focused 
                        ? Colors.white12 
                        : (selected ? const Color(0xFFDC2626).withValues(alpha: 0.1) : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: focused ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _selectedIndex = i),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              tab.icon, 
                              color: focused ? Colors.white : (selected ? const Color(0xFFDC2626) : Colors.white70), 
                              size: 32
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tab.label,
                              style: TextStyle(
                                color: focused || selected ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: focused || selected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
            ),
          );
        }),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  const _Tab({required this.label, required this.icon});
}
