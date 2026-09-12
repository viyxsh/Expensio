import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/expense_model.dart';
import '../services/app_settings.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

class AddPersonalExpenseScreen extends StatefulWidget {
  final ExpenseModel? expense; // for edit mode
  final int? prefillTotalCents; // from bill scan

  const AddPersonalExpenseScreen(
      {super.key, this.expense, this.prefillTotalCents});

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

  @override
  void initState() {
    super.initState();

    if (_isEdit) {
      final e = widget.expense!;
      _titleCtrl.text = e.title;
      _amountCtrl.text = Money.format(e.totalAmount);
      _category = e.category;
      _selectedDateTime = e.createdAt;
    } else if (widget.prefillTotalCents != null) {
      _amountCtrl.text = Money.format(widget.prefillTotalCents!);
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

    final amountCents = Money.tryParseToCents(_amountCtrl.text) ?? 0;

    final expense = ExpenseModel(
      id: _isEdit ? widget.expense!.id : _uuid.v4(), // ✅ keep same id
      title: _titleCtrl.text.trim(),
      totalAmount: amountCents,
      payerId: 'personal',
      participantIds: [],
      groupId: 'personal',
      createdAt: _selectedDateTime,
      category: _category,
      isPersonal: true,
      currencyCode:
          _isEdit ? widget.expense!.currencyCode : AppSettings.currencyCode,
    );

    try {
      // saveExpense upserts by id, so it covers both create and edit.
      await Services.state.saveExpense(expense);

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
      backgroundColor: AppTheme.categoryTintedBg(_category),
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
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Amount
            const SectionHeader(title: 'Amount'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${AppSettings.currencySymbol} ',
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 22,
                          fontWeight: FontWeight.w500)),
                      Expanded(
                        child: TextFormField(
                          controller: _amountCtrl,
                          keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                          // Hint matches the input's scale so it doesn't
                          // look lost inside the tall box.
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '0',
                            hintStyle: TextStyle(
                              color: AppTheme.textSecondary
                                  .withValues(alpha: 0.55),
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                            ),
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
                ),
            const SizedBox(height: 16),

            // Description
            const SectionHeader(title: 'Description'),
            const SizedBox(height: 4),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                hintText: 'Enter Title',
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
            CategoryGrid(
              selected: _category,
              onChanged: (c) => setState(() => _category = c),
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
      ),
    );
  }
}