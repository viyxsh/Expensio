import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/expense_model.dart';
import '../services/hive_service.dart';
import '../utils/app_theme.dart';

class AddPersonalExpenseScreen extends StatefulWidget {
  final ExpenseModel? expense; // for edit mode

  const AddPersonalExpenseScreen({super.key, this.expense});

  @override
  State<AddPersonalExpenseScreen> createState() =>
      _AddPersonalExpenseScreenState();
}

class _AddPersonalExpenseScreenState
    extends State<AddPersonalExpenseScreen> {
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  String _category = 'General';
  DateTime _selectedDateTime = DateTime.now();

  bool get _isEdit => widget.expense != null;

  static const List<String> _categories = [
    'General', 'Groceries', 'Food & Drink', 'Electronics', 'Clothing',
    'Transport', 'Health', 'Entertainment', 'Utilities',
  ];

  @override
  void initState() {
    super.initState();

    if (_isEdit) {
      final e = widget.expense!;
      _titleCtrl.text = e.title;
      _amountCtrl.text = e.totalAmount.toString();
      _category = e.category;
      _selectedDateTime = e.createdAt;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountCtrl.text) ?? 0;

    final expense = ExpenseModel(
      id: _isEdit ? widget.expense!.id : _uuid.v4(), // ✅ keep same id
      title: _titleCtrl.text.trim(),
      totalAmount: amount,
      payerId: 'personal',
      participantIds: [],
      groupId: 'personal',
      createdAt: _selectedDateTime,
      category: _category,
      isPersonal: true,
    );

    try {
      if (_isEdit) {
        await HiveService.updateExpense(expense); // ✅ update
      } else {
        await HiveService.saveExpense(expense); // ✅ create
      }

      if (mounted) {
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Transaction updated'
                  : 'Transaction added',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[Expensio] Error saving expense: $e\n$st');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Transaction' : 'New Transaction'),
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
          padding: const EdgeInsets.all(20),
          children: [
            // Amount 
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Amount',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text('Rs ',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 22,
                              fontWeight: FontWeight.w500)),
                      Expanded(
                        child: TextFormField(
                          controller: _amountCtrl,
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '0',
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter amount';
                            if (double.tryParse(v) == null ||
                                double.parse(v) <= 0) {
                              return 'Invalid amount';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Description 
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Date & Time 
            const SectionHeader(title: 'Date & Time'),
            DateTimePicker(
              value: _selectedDateTime,
              onChanged: (dt) => setState(() => _selectedDateTime = dt),
            ),
            const SizedBox(height: 20),

            // Category 
            const SectionHeader(title: 'Category'),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 2.5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: _categories.map((c) {
                final selected = c == _category;
                final color = AppTheme.categoryColor(c);

                return GestureDetector(
                  onTap: () => setState(() => _category = c),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected
                          ? color.withOpacity(0.15)
                          : AppTheme.surfaceMid,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? color : AppTheme.divider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected ? color : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(_isEdit
                    ? 'Update Transaction'
                    : 'Save Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}