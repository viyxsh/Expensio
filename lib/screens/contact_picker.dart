import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../utils/app_theme.dart';

/// Request contacts permission, then let the user multi-select names to add as
/// (ghost) members. Returns the chosen display names, or null if cancelled /
/// permission denied.
Future<List<String>?> pickContacts(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final granted = await FlutterContacts.requestPermission(readonly: true);
  if (!granted) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Contacts permission denied')));
    return null;
  }
  final contacts = await FlutterContacts.getContacts();
  final names = contacts
      .map((c) => c.displayName.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  if (!context.mounted) return null;
  if (names.isEmpty) {
    messenger
        .showSnackBar(const SnackBar(content: Text('No contacts found')));
    return null;
  }

  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.cardBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ContactPickerSheet(names: names),
  );
}

class _ContactPickerSheet extends StatefulWidget {
  final List<String> names;
  const _ContactPickerSheet({required this.names});

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _selected = <String>{};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.names
        : widget.names
            .where((n) => n.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  const Text('Add from Contacts',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${_selected.length} selected',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search contacts',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final name = filtered[i];
                  final checked = _selected.contains(name);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    onChanged: (_) => setState(() {
                      checked ? _selected.remove(name) : _selected.add(name);
                    }),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                    child: Text(_selected.isEmpty
                        ? 'Select contacts'
                        : 'Add ${_selected.length}'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
