import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import 'contact_picker.dart';
import 'invite_sheet.dart';

/// Opens the create / edit group sheet. Reusable from the Groups list and from
/// inside a group (Group detail), so editing is reachable wherever you are.
Future<void> showGroupEditor(BuildContext context, {GroupModel? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.cardBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _GroupEditorSheet(existing: existing),
  );
}

class _GroupEditorSheet extends StatefulWidget {
  final GroupModel? existing;
  const _GroupEditorSheet({this.existing});

  @override
  State<_GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _MemberRow {
  final TextEditingController ctrl;
  final String? existingId; // null for a newly-added member
  _MemberRow(this.ctrl, this.existingId);
}

class _GroupEditorSheetState extends State<_GroupEditorSheet> {
  static const _uuid = Uuid();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final List<_MemberRow> _members;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _descCtrl = TextEditingController(text: g?.description ?? '');
    // "You" is an implicit member — never shown as an editable row.
    final existingMembers = _isEdit
        ? g!.memberIds
            .where((id) => id != Services.currentUserId)
            .map(Services.state.getUserById)
            .whereType<UserModel>()
            .toList()
        : <UserModel>[];
    _members = existingMembers
        .map((u) => _MemberRow(TextEditingController(text: u.name), u.id))
        .toList();
    if (_members.isEmpty) _members.add(_MemberRow(TextEditingController(), null));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final m in _members) {
      m.ctrl.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Group name is required');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _update();
      } else {
        await _create();
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Something went wrong. Please try again.');
      }
    }
  }

  Future<void> _create() async {
    // The creator is always the first member, keyed by their auth uid, so the
    // group syncs back to them and the security rules permit the write.
    final ids = <String>[Services.currentUserId];
    for (final m in _members) {
      final n = m.ctrl.text.trim();
      if (n.isEmpty) continue;
      final u = UserModel(id: _uuid.v4(), name: n);
      await Services.state.saveUser(u);
      ids.add(u.id);
    }
    await Services.state.saveGroup(GroupModel(
      id: _uuid.v4(),
      name: _nameCtrl.text.trim(),
      memberIds: ids,
      createdAt: DateTime.now(),
      description: _descCtrl.text.trim(),
    ));
  }

  Future<void> _update() async {
    final group = widget.existing!;
    final ids = <String>[Services.currentUserId];
    for (final m in _members) {
      final n = m.ctrl.text.trim();
      if (n.isEmpty) continue;
      if (m.existingId != null) {
        final user = Services.state.getUserById(m.existingId!);
        if (user != null) {
          user.name = n;
          await Services.state.saveUser(user);
          ids.add(m.existingId!);
        }
      } else {
        final u = UserModel(id: _uuid.v4(), name: n);
        await Services.state.saveUser(u);
        ids.add(u.id);
      }
    }
    // Delete the placeholder members the user removed.
    for (final id in group.memberIds.where((id) => !ids.contains(id))) {
      await Services.state.deleteUser(id);
    }
    group.name = _nameCtrl.text.trim();
    group.description = _descCtrl.text.trim();
    group.memberIds = ids;
    await Services.state.saveGroup(group);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(_isEdit ? 'Edit Group' : 'New Group',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              _isEdit
                  ? 'Update the name, details, and members.'
                  : 'Name your group and add the people in it.',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g. Weekend Trip, Roommates',
                prefixIcon: Icon(Icons.group_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: !_isEdit,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: Icon(Icons.notes_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                const Text('Members',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMid,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('You are included',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Add people you\'re tracking who aren\'t on the app. To add '
              'someone who uses Expensio, invite them with a code.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            ..._members.asMap().entries.map((e) => _memberRow(e.key, e.value)),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() =>
                      _members.add(_MemberRow(TextEditingController(), null))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a name'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _addFromContacts,
                  icon: const Icon(Icons.contacts_outlined, size: 18),
                  label: const Text('From contacts'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _inviteAction(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEdit ? 'Save Changes' : 'Create Group'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFromContacts() async {
    final names = await pickContacts(context);
    if (names == null || names.isEmpty || !mounted) return;
    setState(() {
      // Drop a single empty starter row so contacts aren't mixed with a blank.
      _members.removeWhere((m) => m.ctrl.text.trim().isEmpty);
      for (final n in names) {
        _members.add(_MemberRow(TextEditingController(text: n), null));
      }
      if (_members.isEmpty) {
        _members.add(_MemberRow(TextEditingController(), null));
      }
    });
  }

  Widget _inviteAction() {
    if (!_isEdit) {
      // A new group has no id yet; invites are created once it exists.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Create the group, then invite people who use Expensio.',
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => showInviteSheet(context, widget.existing!),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: const Text('Invite someone on the app'),
      ),
    );
  }

  Widget _memberRow(int i, _MemberRow m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: m.ctrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Member name',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppTheme.textSecondary, size: 20),
            tooltip: 'Remove',
            onPressed: () => setState(() {
              m.ctrl.dispose();
              _members.removeAt(i);
              if (_members.isEmpty) {
                _members.add(_MemberRow(TextEditingController(), null));
              }
            }),
          ),
        ],
      ),
    );
  }
}
