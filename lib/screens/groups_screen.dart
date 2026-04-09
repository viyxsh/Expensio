import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/hive_service.dart';
import '../utils/app_theme.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _uuid = const Uuid();

  // Create / Edit group sheet 

  void _showGroupSheet({GroupModel? existing}) {
    final isEdit = existing != null;
    final existingMembers = isEdit
        ? existing.memberIds
        .map(HiveService.getUserById)
        .whereType<UserModel>()
        .toList()
        : <UserModel>[];

    final nameCtrl =
    TextEditingController(text: isEdit ? existing.name : '');
    final descCtrl =
    TextEditingController(text: isEdit ? existing.description : '');

    final memberEntries = isEdit
        ? existingMembers
        .map((u) => (TextEditingController(text: u.name), u.id))
        .toList()
        : [(TextEditingController(), null as String?)];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(isEdit ? 'Edit Group' : 'New Group',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    hintText: 'e.g. Weekend Trip, Roommates',
                  ),
                  textCapitalization: TextCapitalization.words,
                  autofocus: !isEdit,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)'),
                ),
                const SizedBox(height: 20),
                const Text('Members',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                ...memberEntries.asMap().entries.map((entry) {
                  final i = entry.key;
                  final (ctrl, existingId) = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor:
                          AppTheme.primary.withOpacity(0.1),
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                                hintText: 'Member ${i + 1} name'),
                            textCapitalization:
                            TextCapitalization.words,
                          ),
                        ),
                        if (memberEntries.length > 1)
                          IconButton(
                            icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppTheme.errorColor, size: 20),
                            onPressed: () =>
                                setModal(() => memberEntries.removeAt(i)),
                          ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () =>
                      setModal(() => memberEntries.add(
                          (TextEditingController(), null))),
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Add Member'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => isEdit
                        ? _updateGroup(
                      existing,
                      nameCtrl.text.trim(),
                      descCtrl.text.trim(),
                      memberEntries,
                      ctx,
                    )
                        : _createGroup(
                      nameCtrl.text.trim(),
                      descCtrl.text.trim(),
                      memberEntries
                          .map((e) => e.$1.text.trim())
                          .where((n) => n.isNotEmpty)
                          .toList(),
                      ctx,
                    ),
                    child: Text(isEdit ? 'Save Changes' : 'Create Group'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createGroup(String name, String desc,
      List<String> memberNames, BuildContext sheetCtx) async {
    if (name.isEmpty) { _snack('Group name is required'); return; }
    if (memberNames.isEmpty) { _snack('Add at least one member'); return; }

    final ids = <String>[];
    for (final n in memberNames) {
      final u = UserModel(id: _uuid.v4(), name: n);
      await HiveService.saveUser(u);
      ids.add(u.id);
    }
    await HiveService.saveGroup(GroupModel(
      id: _uuid.v4(),
      name: name,
      memberIds: ids,
      createdAt: DateTime.now(),
      description: desc,
    ));
    if (mounted) Navigator.pop(sheetCtx);
  }

  Future<void> _updateGroup(
      GroupModel group,
      String name,
      String desc,
      List<(TextEditingController, String?)> memberEntries,
      BuildContext sheetCtx,
      ) async {
    if (name.isEmpty) { _snack('Group name is required'); return; }

    final ids = <String>[];
    for (final (ctrl, existingId) in memberEntries) {
      final memberName = ctrl.text.trim();
      if (memberName.isEmpty) continue;
      if (existingId != null) {
        // Update existing user name
        final user = HiveService.getUserById(existingId);
        if (user != null) {
          user.name = memberName;
          await HiveService.saveUser(user);
          ids.add(existingId);
        }
      } else {
        // New member
        final u = UserModel(id: _uuid.v4(), name: memberName);
        await HiveService.saveUser(u);
        ids.add(u.id);
      }
    }

    // Remove members who were deleted
    final removed = group.memberIds
        .where((id) => !ids.contains(id))
        .toList();
    for (final id in removed) {
      await HiveService.deleteUser(id);
    }

    group.name = name;
    group.description = desc;
    group.memberIds = ids;
    await HiveService.saveGroup(group);
    if (mounted) Navigator.pop(sheetCtx);
  }

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
    if (ok == true) await HiveService.deleteGroup(groupId);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // Build 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<GroupModel>('groups').listenable(),
        builder: (context, box, _) {
          final groups = box.values.toList().reversed.toList();
          if (groups.isEmpty) return _buildEmpty();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final g = groups[i] as GroupModel;
              final expenses = HiveService.getExpensesByGroup(g.id);
              final total = expenses
                  .where((e) => !e.isPersonal)
                  .fold<double>(0, (s, e) => s + e.totalAmount);
              final members = g.memberIds
                  .map(HiveService.getUserById)
                  .whereType<UserModel>()
                  .toList();
              return _GroupCard(
                group: g,
                members: members,
                expenseCount: expenses.length,
                totalAmount: total,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => GroupDetailScreen(group: g))),
                onEdit: () => _showGroupSheet(existing: g),
                onDelete: () => _deleteGroup(g.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGroupSheet(),
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
            child: const Icon(Icons.group_outlined,
                size: 40, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          const Text('No groups yet',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
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
  final double totalAmount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GroupCard({
    required this.group,
    required this.members,
    required this.expenseCount,
    required this.totalAmount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
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
                    child: const Icon(Icons.group_outlined,
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
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
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
                    icon: const Icon(Icons.more_vert,
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
                      const Text('Total',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary)),
                      Text(
                        'Rs ${totalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
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
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary)),
                      ),
                    )),
                    if (members.length > 6)
                      Text('+${members.length - 6}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
        ),
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
          style: const TextStyle(
              fontSize: 12, color: AppTheme.textSecondary)),
    ]);
  }
}