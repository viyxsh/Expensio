import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import 'transactions_screen.dart';
import 'groups_screen.dart';
import 'more_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _selectTab(int i) => setState(() => _currentIndex = i);

  @override
  Widget build(BuildContext context) {
    // Intentionally non-const: a theme change rebuilds MainShell, and these
    // must be fresh instances so each screen re-runs build() and repaints with
    // the new palette (colours come from AppTheme getters, not the inherited
    // Theme, so they don't rebuild on their own).
    // ignore: prefer_const_constructors
    final screens = [
      TransactionsScreen(), // ignore: prefer_const_constructors
      GroupsScreen(), // ignore: prefer_const_constructors
      MoreScreen(onSelectTab: _selectTab),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          indicatorColor: AppTheme.primary.withOpacity(0.1),
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.receipt_long_outlined),
              selectedIcon:
              Icon(Icons.receipt_long, color: AppTheme.primary),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: const Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group, color: AppTheme.primary),
              label: 'Groups',
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz_outlined),
              selectedIcon:
              Icon(Icons.more_horiz, color: AppTheme.primary),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}