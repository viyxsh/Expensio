import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';
import 'group_detail_screen.dart';
import 'group_editor.dart';
import 'invite_sheet.dart';
import 'join_flow.dart';
import 'qr_scanner_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  Future<void> _deleteGroup(String groupId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
            'All expenses in this group will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await Services.state.deleteGroup(groupId);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // Invites

  void _showJoinSheet() {
    if (!Services.firebaseActive) {
      _snack('Sign in to join a shared group.');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Join a Group',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scan QR code'),
              onTap: () {
                Navigator.pop(ctx);
                _scanToJoin();
              },
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('Enter code'),
              onTap: () {
                Navigator.pop(ctx);
                _enterCode();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scanToJoin() async {
    final raw = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (raw == null || !mounted) return;
    await runJoinFlow(context, raw);
  }

  Future<void> _enterCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Invite Code'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'e.g. K7P2M9QX',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    await runJoinFlow(context, code);
  }

  // Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            tooltip: 'Join a group',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _showJoinSheet,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Services.state,
        builder: (context, _) {
          final groups = Services.state.groups.reversed.toList();
          if (groups.isEmpty) return _buildEmpty();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final g = groups[i];
              final expenses = Services.state.getExpensesByGroup(g.id);
              final total = expenses
                  .where((e) => !e.isPersonal)
                  .fold<int>(0, (s, e) => s + e.totalAmount);
              final members = g.memberIds
                  .map(Services.state.getUserById)
                  .whereType<UserModel>()
                  .toList();
              final myBalance =
                  Services.state.computeBalances(g.id)[Services.currentUserId] ??
                      0;
              return _GroupCard(
                group: g,
                members: members,
                expenseCount: expenses.length,
                totalAmount: total,
                myBalance: myBalance,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => GroupDetailScreen(group: g))),
                onEdit: () => showGroupEditor(context, existing: g),
                onDelete: () => _deleteGroup(g.id),
                onInvite: () => showInviteSheet(context, g),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGroupEditor(context),
        icon: const Icon(Icons.group_add_outlined),
        label: const Text('New Group'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.group_outlined,
                size: 40, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          const Text('No groups yet',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Create a group to start tracking\nshared expenses',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// Group card 

class _GroupCard extends StatelessWidget {
  final GroupModel group;
  final List<UserModel> members;
  final int expenseCount;
  final int totalAmount;
  final int myBalance;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onInvite;

  const _GroupCard({
    required this.group,
    required this.members,
    required this.expenseCount,
    required this.totalAmount,
    required this.myBalance,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.group_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(group.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        if (group.description.isNotEmpty)
                          Text(group.description,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'invite') onInvite();
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'invite',
                        child: Row(children: [
                          Icon(Icons.person_add_alt_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Invite'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Group'),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              color: AppTheme.errorColor, size: 18),
                          SizedBox(width: 8),
                          Text('Delete',
                              style: TextStyle(color: AppTheme.errorColor)),
                        ]),
                      ),
                    ],
                    icon: Icon(Icons.more_vert,
                        color: AppTheme.textSecondary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(icon: Icons.person_outline,
                      value: '${members.length}', label: 'Members'),
                  const SizedBox(width: 20),
                  _Stat(icon: Icons.receipt_outlined,
                      value: '$expenseCount', label: 'Expenses'),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary)),
                      Text(
                        Money.withSymbol(totalAmount, decimals: 0),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    ...members.take(6).map((m) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor:
                        AppTheme.primary.withOpacity(0.1),
                        child: Text(m.name[0].toUpperCase(),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ),
                    )),
                    if (members.length > 6)
                      Text('+${members.length - 6}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                    const Spacer(),
                    _buildBalanceChip(),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Your own position in the group: owed (green), owing (red) or settled.
  Widget _buildBalanceChip() {
    final settled = myBalance == 0;
    final owed = myBalance > 0;
    final color = settled
        ? AppTheme.textSecondary
        : owed
            ? AppTheme.successColor
            : AppTheme.errorColor;
    final label = settled
        ? 'You\'re settled'
        : owed
            ? 'You\'re owed ${Money.withSymbol(myBalance.abs(), decimals: 0)}'
            : 'You owe ${Money.withSymbol(myBalance.abs(), decimals: 0)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Stat(
      {required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: AppTheme.textSecondary),
      const SizedBox(width: 4),
      Text(value,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
              fontSize: 12, color: AppTheme.textSecondary)),
    ]);
  }
}