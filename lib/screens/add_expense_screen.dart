import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../models/bill_item_model.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

enum _SplitType { percentage, fixed }

class _ParticipantSplit {
  _SplitType type;
  TextEditingController ctrl;
  _ParticipantSplit({required this.type, required this.ctrl});
}

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final List<UserModel> members;
  final List<BillItem>? prefillItems;
  final double? prefillTotal;

  const AddExpenseScreen({
    super.key,
    required this.group,
    required this.members,
    this.prefillItems,
    this.prefillTotal,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _selectedCategory = 'General';
  String? _payerId;
  bool _splitEqually = true;
  final Set<String> _selectedParticipants = {};
  final Map<String, _ParticipantSplit> _splitData = {};

  List<BillItem> _items = [];
  DateTime _selectedDateTime = DateTime.now();

  static const List<String> _categories = [
    'General', 'Groceries', 'Food & Drink', 'Electronics',
    'Clothing', 'Transport', 'Health', 'Entertainment', 'Utilities',
  ];

  @override
  void initState() {
    super.initState();
    _payerId = widget.members.isNotEmpty ? widget.members.first.id : null;
    _selectedParticipants.addAll(widget.members.map((m) => m.id));
    for (final m in widget.members) {
      _splitData[m.id] = _ParticipantSplit(
        type: _SplitType.percentage,
        ctrl: TextEditingController(),
      );
    }
    _resetEqualSplit();

    if (widget.prefillItems != null) {
      _items = List.from(widget.prefillItems!);
      final total = _items.fold<double>(0, (s, i) => s + i.price * i.quantity);
      _amountCtrl.text = total.toStringAsFixed(2);
      _selectedCategory = _dominantCategory(_items);
    } else if (widget.prefillTotal != null) {
      _amountCtrl.text = widget.prefillTotal!.toStringAsFixed(2);
    }
  }

  void _resetEqualSplit() {
    if (_selectedParticipants.isEmpty) return;
    final pct = 100 / _selectedParticipants.length;
    for (final id in widget.members.map((m) => m.id)) {
      final sd = _splitData[id]!;
      if (_selectedParticipants.contains(id)) {
        sd.type = _SplitType.percentage;
        sd.ctrl.text = pct.toStringAsFixed(1);
      } else {
        sd.ctrl.text = '0';
      }
    }
  }

  String _dominantCategory(List<BillItem> items) {
    if (items.isEmpty) return 'General';
    final freq = <String, int>{};
    for (final i in items) {
      freq[i.category] = (freq[i.category] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    for (final sd in _splitData.values) {
      sd.ctrl.dispose();
    }
    super.dispose();
  }

  /// Total amount in cents.
  int get _totalCents => Money.tryParseToCents(_amountCtrl.text) ?? 0;

  /// Resolved split as cents per participant. For equal splits the remainder is
  /// distributed exactly; for custom splits values may drift by a few cents and
  /// are snapped to the total in [_save].
  Map<String, int> _resolvedSplitMap() {
    final total = _totalCents;
    final participants = _selectedParticipants.toList();
    if (participants.isEmpty) return {};

    if (_splitEqually) {
      final shares = Money.splitEqual(total, participants.length);
      return {
        for (int i = 0; i < participants.length; i++) participants[i]: shares[i]
      };
    }

    int fixedTotal = 0;
    final Map<String, int> result = {};

    for (final id in participants) {
      final sd = _splitData[id]!;
      if (sd.type == _SplitType.fixed) {
        final c = Money.tryParseToCents(sd.ctrl.text) ?? 0;
        result[id] = c;
        fixedTotal += c;
      }
    }

    final remainder = total - fixedTotal;
    for (final id in participants) {
      final sd = _splitData[id]!;
      if (sd.type == _SplitType.percentage) {
        final pct = double.tryParse(sd.ctrl.text) ?? 0;
        result[id] = (remainder * pct / 100).round();
      }
    }
    return result;
  }

  bool get _splitIsValid {
    if (_splitEqually) return true;
    final sum = _resolvedSplitMap().values.fold<int>(0, (s, v) => s + v);
    return (_totalCents - sum).abs() < 50; // within 50 cents
  }

  String _splitStatusText() {
    final sum = _resolvedSplitMap().values.fold<int>(0, (s, v) => s + v);
    final diff = _totalCents - sum;
    if (diff.abs() < 50) return 'Looks good';
    if (diff > 0) return '${Money.withSymbol(diff)} unassigned';
    return 'Over by ${Money.withSymbol(-diff)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_payerId == null) { _snack('Select who paid'); return; }
    if (_selectedParticipants.isEmpty) { _snack('Select at least one participant'); return; }
    if (_totalCents <= 0) { _snack('Enter a valid amount'); return; }
    if (!_splitIsValid) { _snack(_splitStatusText()); return; }

    // Snap the split to the exact total so balances always reconcile to zero.
    final split = _resolvedSplitMap();
    final splitSum = split.values.fold<int>(0, (s, v) => s + v);
    final drift = _totalCents - splitSum;
    if (drift != 0 && split.isNotEmpty) {
      final firstKey = split.keys.first;
      split[firstKey] = split[firstKey]! + drift;
    }

    final expense = ExpenseModel(
      id: _uuid.v4(),
      title: _titleCtrl.text.trim(),
      totalAmount: _totalCents,
      payerId: _payerId!,
      participantIds: _selectedParticipants.toList(),
      groupId: widget.group.id,
      createdAt: _selectedDateTime,
      items: _items,
      category: _selectedCategory,
      isPersonal: false,
      splitMap: split,
    );

    try {
      await Services.state.saveExpense(expense);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense added')));
      }
    } catch (e, st) {
      debugPrint('[Expensio] Error saving group expense: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Please try again.')),
        );
      }
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense Title',
                hintText: 'e.g. Dinner, Movie tickets',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Amount
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Total Amount',
                prefixText: 'Rs ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (double.tryParse(v) == null || double.parse(v) <= 0) {
                  return 'Invalid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Category
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              dropdownColor: AppTheme.surfaceHigh,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(
                value: c,
                child: Row(children: [
                  Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.categoryColor(c),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(c),
                ]),
              ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 16),

            // Date & Time
            const SectionHeader(title: 'Date & Time'),
            DateTimePicker(
              value: _selectedDateTime,
              onChanged: (dt) => setState(() => _selectedDateTime = dt),
            ),
            const SizedBox(height: 20),

            // Payer
            const SectionHeader(title: 'Paid By'),
            _buildPayerSelector(),
            const SizedBox(height: 20),

            // Split Between
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionHeader(title: 'Split Between'),
                Row(children: [
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedParticipants
                          .addAll(widget.members.map((m) => m.id));
                      if (_splitEqually) _resetEqualSplit();
                    }),
                    child: const Text('All'),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _selectedParticipants.clear()),
                    child: const Text('None'),
                  ),
                ]),
              ],
            ),
            _buildParticipantChips(),
            const SizedBox(height: 16),

            // Split equally toggle
            _buildSplitToggle(),

            // Custom split section
            if (!_splitEqually) ...[
              const SizedBox(height: 14),
              _buildCustomSplitSection(),
            ],
            const SizedBox(height: 20),

            // Scanned items
            if (_items.isNotEmpty) ...[
              const SectionHeader(title: 'Scanned Items'),
              _buildItemsList(),
              const SizedBox(height: 20),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('Save Expense'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPayerSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: widget.members.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final isSelected = _payerId == m.id;
          return Column(
            children: [
              if (i > 0)
                Divider(height: 1, indent: 56, color: AppTheme.divider),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? AppTheme.primary
                      : AppTheme.surfaceMid,
                  child: Text(m.name[0].toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isSelected
                              ? AppTheme.bg
                              : AppTheme.textSecondary)),
                ),
                title: Text(m.name,
                    style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: AppTheme.textPrimary)),
                trailing: isSelected
                    ? Icon(Icons.check_circle,
                    color: AppTheme.primary, size: 20)
                    : null,
                onTap: () => setState(() => _payerId = m.id),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildParticipantChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.members.map((m) {
        final isSelected = _selectedParticipants.contains(m.id);
        return FilterChip(
          label: Text(m.name),
          selected: isSelected,
          onSelected: (selected) => setState(() {
            if (selected) {
              _selectedParticipants.add(m.id);
            } else {
              _selectedParticipants.remove(m.id);
            }
            if (_splitEqually) _resetEqualSplit();
          }),
        );
      }).toList(),
    );
  }

  Widget _buildSplitToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: SwitchListTile(
        title: const Text('Split Equally',
            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        subtitle: Text(
          _splitEqually
              ? 'Divided evenly among participants'
              : 'Set custom amounts per person',
          style: const TextStyle(fontSize: 12),
        ),
        value: _splitEqually,
        onChanged: (v) => setState(() {
          _splitEqually = v;
          if (v) _resetEqualSplit();
        }),
      ),
    );
  }

  Widget _buildCustomSplitSection() {
    final participants = widget.members
        .where((m) => _selectedParticipants.contains(m.id))
        .toList();
    final resolved = _resolvedSplitMap();
    final isValid = _splitIsValid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + status pill
        Row(
          children: [
            Text('CUSTOM SPLIT',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppTheme.textSecondary)),
            const Spacer(),
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isValid
                    ? AppTheme.successColor.withOpacity(0.12)
                    : AppTheme.errorColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _splitStatusText(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isValid
                      ? AppTheme.successColor
                      : AppTheme.errorColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Legend
        Row(children: [
          _Legend(color: AppTheme.primary, label: '% of total'),
          const SizedBox(width: 16),
          const _Legend(color: AppTheme.successColor, label: 'Fixed amount'),
        ]),
        const SizedBox(height: 10),

        // Per-person rows
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isValid ? AppTheme.divider : AppTheme.errorColor),
          ),
          child: Column(
            children: participants.asMap().entries.map((e) {
              final i = e.key;
              final m = e.value;
              final sd = _splitData[m.id]!;
              final share = resolved[m.id] ?? 0;
              final isPct = sd.type == _SplitType.percentage;

              return Column(
                children: [
                  if (i > 0)
                    Divider(height: 1, indent: 56, color: AppTheme.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.surfaceMid,
                          child: Text(m.name[0].toUpperCase(),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textSecondary)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: AppTheme.textPrimary)),
                              if (share > 0)
                                Text(
                                  Money.withSymbol(share),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        // Type toggle
                        GestureDetector(
                          onTap: () => setState(() {
                            sd.type = isPct
                                ? _SplitType.fixed
                                : _SplitType.percentage;
                            sd.ctrl.clear();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: isPct
                                  ? AppTheme.primary.withOpacity(0.12)
                                  : AppTheme.successColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isPct ? '%' : 'Rs',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isPct
                                    ? AppTheme.primary
                                    : AppTheme.successColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Input
                        SizedBox(
                          width: 76,
                          child: TextField(
                            controller: sd.ctrl,
                            keyboardType:
                            const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                            decoration: InputDecoration(
                              suffixText: isPct ? '%' : '',
                              suffixStyle: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: AppTheme.divider),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                    color: AppTheme.divider),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: isPct
                                      ? AppTheme.primary
                                      : AppTheme.successColor,
                                  width: 1.5,
                                ),
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceMid,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() {
            final n = participants.length;
            if (n == 0) return;
            final each = 100 / n;
            for (final m in participants) {
              _splitData[m.id]!.type = _SplitType.percentage;
              _splitData[m.id]!.ctrl.text = each.toStringAsFixed(1);
            }
          }),
          icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
          label: const Text('Auto-balance equally'),
        ),
      ],
    );
  }

  Widget _buildItemsList() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: _items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          return Column(
            children: [
              if (i > 0)
                Divider(height: 1, indent: 56, color: AppTheme.divider),
              ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.categoryColor(item.category)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text('${item.quantity}x',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.categoryColor(item.category))),
                  ),
                ),
                title: Text(item.name,
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textPrimary)),
                subtitle: CategoryBadge(category: item.category),
                trailing: Text(
                  'Rs ${item.totalPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}