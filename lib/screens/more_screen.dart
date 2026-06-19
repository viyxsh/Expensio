import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense_model.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';
import 'auth/sign_in_screen.dart';

class MoreScreen extends StatefulWidget {
  /// Switches the bottom-nav tab (0 = Transactions, 1 = Groups), so the
  /// Overview stat cards can jump to their corresponding lists.
  final void Function(int index)? onSelectTab;
  const MoreScreen({super.key, this.onSelectTab});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  // Notification toggles

  Future<void> _toggleSettlement(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) _snack('Notification permission denied');
        return;
      }
    }
    await AppSettings.setSettlementReminders(value);
    await NotificationService.scheduleSettlementReminder(value);
  }

  Future<void> _toggleDaily(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) _snack('Notification permission denied');
        return;
      }
    }
    await AppSettings.setDailyReminders(value);
    await NotificationService.scheduleDailyTransactionReminder(value);
  }

  // Currency picker 

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ValueListenableBuilder(
        valueListenable: Hive.box('settings').listenable(),
        builder: (_, __, ___) {
          final current = AppSettings.currencyCode;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Currency',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              ...AppSettings.currencies.map((c) => ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMid,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        c['symbol']!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    title: Text(c['name']!,
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(c['code']!,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    trailing: current == c['code']
                        ? Icon(Icons.check_circle,
                            color: AppTheme.primary, size: 20)
                        : null,
                    onTap: () {
                      AppSettings.setCurrency(c['code']!);
                      Navigator.pop(ctx);
                    },
                  )),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // Appearance / theme

  String _themeLabel(String mode) => switch (mode) {
        'light' => 'Light',
        'dark' => 'Dark',
        _ => 'System default',
      };

  void _showThemePicker() {
    const options = [
      ('system', 'System default', Icons.brightness_auto_outlined),
      ('light', 'Light', Icons.light_mode_outlined),
      ('dark', 'Dark', Icons.dark_mode_outlined),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ValueListenableBuilder(
        valueListenable: Hive.box('settings').listenable(),
        builder: (_, __, ___) {
          final current = AppSettings.themeMode;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Appearance',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              for (final (mode, label, icon) in options)
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                  leading: Icon(icon, color: AppTheme.textSecondary),
                  title: Text(label, style: const TextStyle(fontSize: 14)),
                  trailing: current == mode
                      ? Icon(Icons.check_circle,
                          color: AppTheme.primary, size: 20)
                      : null,
                  onTap: () {
                    AppSettings.setThemeMode(mode);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  // Monthly history

  void _showMonthlyHistory(List<ExpenseModel> allExpenses) {
    final Map<String, int> monthly = {};
    for (final e in allExpenses) {
      final key =
          '${e.createdAt.year}-${e.createdAt.month.toString().padLeft(2, '0')}';
      monthly[key] = (monthly[key] ?? 0) + e.totalAmount;
    }

    final sorted = monthly.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final recent = sorted.take(12).toList();

    if (recent.isEmpty) {
      _snack('No spending history yet');
      return;
    }

    final maxVal =
        recent.map((e) => e.value).fold<int>(1, (a, b) => a > b ? a : b);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            _sheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 4, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Monthly Spending',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: recent.length,
                itemBuilder: (_, i) {
                  final entry = recent[i];
                  final parts = entry.key.split('-');
                  final label = DateFormat('MMMM yyyy').format(
                    DateTime(
                        int.parse(parts[0]), int.parse(parts[1])),
                  );
                  final pct = entry.value / maxVal;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            Text(
                              Money.withSymbol(entry.value, decimals: 0),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: AppTheme.divider,
                            valueColor: AlwaysStoppedAnimation(
                                AppTheme.primary),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Export 

  Future<void> _exportData() async {
    try {
      final expenses = Services.state.getAllExpenses();
      final groups = Services.state.getAllGroups();
      final users = Services.state.getAllUsers();

      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'users': users
            .map((u) => {'id': u.id, 'name': u.name})
            .toList(),
        'groups': groups
            .map((g) => {
                  'id': g.id,
                  'name': g.name,
                  'description': g.description,
                  'memberIds': g.memberIds,
                  'createdAt': g.createdAt.toIso8601String(),
                })
            .toList(),
        'expenses': expenses
            .map((e) => {
                  'id': e.id,
                  'title': e.title,
                  'totalAmount': Money.toMajor(e.totalAmount),
                  'payerId': e.payerId,
                  'participantIds': e.participantIds,
                  'groupId': e.groupId,
                  'createdAt': e.createdAt.toIso8601String(),
                  'category': e.category,
                  'isPersonal': e.isPersonal,
                  'splitMap': e.splitMap
                      .map((k, v) => MapEntry(k, Money.toMajor(v))),
                })
            .toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/expensio_export_$ts.json');
      await file.writeAsString(json);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Expensio Data Export',
      );
    } catch (e, st) {
      debugPrint('[Export] Error: $e\n$st');
      if (mounted) _snack('Export failed. Please try again.');
    }
  }

  // Clear all 

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
            'This will permanently delete all groups, expenses, and members. Cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppTheme.errorColor),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Services.state.clearAll();
      if (mounted) _snack('All data cleared');
    } catch (e, st) {
      debugPrint('[Expensio] Error clearing data: $e\n$st');
      if (mounted) _snack('Something went wrong. Please try again.');
    }
  }

  // Account

  void _openSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
            'You\'ll go back to guest mode on this device. Your account data '
            'stays in the cloud and reloads when you sign back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Services.auth.signOut();
    } catch (e, st) {
      debugPrint('[Expensio] Sign-out error: $e\n$st');
      if (mounted) _snack('Could not sign out. Please try again.');
    }
  }

  // Helpers

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  static Widget _sheetHandle() => Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  // Build 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListenableBuilder(
        listenable: Services.state,
        builder: (context, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box('settings').listenable(),
            builder: (context, __, ___) {
              final allExpenses = Services.state.getAllExpenses();
              final allGroups = Services.state.getAllGroups();

              // Current month total
              final now = DateTime.now();
              final monthStart = DateTime(now.year, now.month);
              final monthTotal = allExpenses
                  .where((e) => !e.createdAt.isBefore(monthStart))
                  .fold<int>(0, (s, e) => s + e.totalAmount);

              final sym = AppSettings.currencySymbol;
              final currencyName = AppSettings.currencyName;
              final settlementOn = AppSettings.settlementReminders;
              final dailyOn = AppSettings.dailyReminders;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Account
                  _AccountCard(
                    onSignIn: _openSignIn,
                    onSignOut: _confirmSignOut,
                  ),
                  const SizedBox(height: 20),

                  // Overview
                  const SectionHeader(title: 'Overview'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              _showMonthlyHistory(allExpenses),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.payments_outlined,
                                        size: 13,
                                        color: AppTheme.textSecondary),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text('This Month',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(Icons.chevron_right,
                                        size: 14,
                                        color: AppTheme.textSecondary),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '$sym ${_compact(Money.toMajor(monthTotal))}',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onSelectTab?.call(1),
                          child: InfoCard(
                              label: 'Groups',
                              value: '${allGroups.length}',
                              icon: Icons.group_outlined),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onSelectTab?.call(0),
                          child: InfoCard(
                              label: 'Expenses',
                              value: '${allExpenses.length}',
                              icon: Icons.receipt_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Settings 
                  const SectionHeader(title: 'Settings'),
                  const SizedBox(height: 8),
                  _Section(children: [
                    _SettingsTile(
                      icon: AppTheme.isDark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      title: 'Appearance',
                      subtitle: _themeLabel(AppSettings.themeMode),
                      onTap: _showThemePicker,
                    ),
                    _SettingsTile(
                      icon: Icons.currency_exchange,
                      title: 'Currency',
                      subtitle: '$sym · $currencyName',
                      onTap: _showCurrencyPicker,
                    ),
                    _NotifTile(
                      icon: Icons.handshake_outlined,
                      title: 'Settlement Reminders',
                      subtitle: settlementOn ? 'Daily reminder at 8 PM' : 'Off',
                      value: settlementOn,
                      onChanged: _toggleSettlement,
                    ),
                    _NotifTile(
                      icon: Icons.edit_note_outlined,
                      title: 'Daily Log Reminder',
                      subtitle: dailyOn ? 'Daily reminder at 9 PM' : 'Off',
                      value: dailyOn,
                      onChanged: _toggleDaily,
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Data 
                  const SectionHeader(title: 'Data'),
                  const SizedBox(height: 8),
                  _Section(children: [
                    _SettingsTile(
                      icon: Icons.download_outlined,
                      title: 'Export Data',
                      subtitle: 'Save as JSON file',
                      onTap: _exportData,
                    ),
                    _SettingsTile(
                      icon: Icons.delete_sweep_outlined,
                      title: 'Clear All Data',
                      subtitle: 'Permanently delete everything',
                      iconColor: AppTheme.errorColor,
                      textColor: AppTheme.errorColor,
                      onTap: _confirmClearAll,
                    ),
                  ]),
                  const SizedBox(height: 40),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// Section container 

class _Section extends StatelessWidget {
  final List<Widget> children;
  const _Section({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: children.asMap().entries.map((e) {
          return Column(
            children: [
              if (e.key > 0)
                Divider(height: 1, indent: 56, color: AppTheme.divider),
              e.value,
            ],
          );
        }).toList(),
      ),
    );
  }
}

// Account card: guest vs signed-in, driven by the auth stream

class _AccountCard extends StatelessWidget {
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  const _AccountCard({required this.onSignIn, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: Services.auth.authStateChanges(),
      initialData: Services.auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        final signedIn = user != null && !user.isGuest;
        final title = signedIn
            ? (user.displayName?.isNotEmpty == true
                ? user.displayName!
                : (user.email ?? 'Account'))
            : 'Guest';
        final subtitle = signedIn
            ? (user.email ?? 'Synced across your devices')
            : 'Sign in to sync across devices';

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              child: Icon(
                signedIn ? Icons.person : Icons.person_outline,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            title: Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
                overflow: TextOverflow.ellipsis),
            trailing: signedIn
                ? TextButton(
                    onPressed: onSignOut,
                    child: const Text('Sign Out'),
                  )
                : FilledButton(
                    onPressed: onSignIn,
                    child: const Text('Sign In'),
                  ),
          ),
        );
      },
    );
  }
}

// Settings tile

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (iconColor ?? AppTheme.textSecondary)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: iconColor ?? AppTheme.textSecondary, size: 18),
      ),
      title: Text(title,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor ?? AppTheme.textPrimary)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: AppTheme.textSecondary)),
      trailing: onTap != null
          ? Icon(Icons.chevron_right,
              color: AppTheme.textSecondary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

// Notification toggle tile 

class _NotifTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _NotifTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.textSecondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.textSecondary, size: 18),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12, color: AppTheme.textSecondary)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
