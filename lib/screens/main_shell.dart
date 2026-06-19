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
    final screens = [
      const TransactionsScreen(),
      const GroupsScreen(),
      MoreScreen(onSelectTab: _selectTab),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon:
              Icon(Icons.receipt_long, color: AppTheme.primary),
              label: 'Transactions',
            ),
            NavigationDestination(
              icon: Icon(Icons.group_outlined),
              selectedIcon: Icon(Icons.group, color: AppTheme.primary),
              label: 'Groups',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz_outlined),
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