import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../data/budget.dart';
import '../models/expense_model.dart';
import '../services/app_settings.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

const _amber = Color(0xFFE0A52F);

Color _budgetColor(BudgetState s) => switch (s) {
      BudgetState.over => AppTheme.errorColor,
      BudgetState.warning => _amber,
      _ => AppTheme.successColor,
    };

/// Number-entry dialog for a single budget line. Returns the new cents value,
/// 0 to clear, or null if cancelled.
Future<int?> _editBudgetDialog(
    BuildContext context, String title, int current) {
  final ctrl = TextEditingController(
      text: current > 0 ? Money.toMajor(current).toStringAsFixed(0) : '');
  final sym = AppSettings.currencySymbol;
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          prefixText: '$sym ',
          hintText: 'Monthly limit',
        ),
        onSubmitted: (_) =>
            Navigator.pop(ctx, Money.tryParseToCents(ctrl.text) ?? 0),
      ),
      actions: [
        if (current > 0)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Clear'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, Money.tryParseToCents(ctrl.text) ?? 0),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: ListenableBuilder(
        listenable: Services.state,
        builder: (context, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box('settings').listenable(),
            builder: (context, __, ___) {
              final uid = Services.currentUserId;
              final now = DateTime.now();
              final byCat = BudgetMath.spendByCategory(
                  Services.state.getAllExpenses(), uid, now);
              final elapsed = BudgetMath.monthElapsed(now);
              final overall = BudgetLine(
                limit: AppSettings.overallBudget,
                spent: BudgetMath.total(byCat),
                monthElapsed: elapsed,
              );
              final catBudgets = AppSettings.categoryBudgets;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OverallCard(line: overall),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Category budgets'),
                  const SizedBox(height: 8),
                  ...AppTheme.categoryColors.keys.map((cat) => _CategoryRow(
                        category: cat,
                        line: BudgetLine(
                          limit: catBudgets[cat] ?? 0,
                          spent: byCat[cat] ?? 0,
                          monthElapsed: elapsed,
                        ),
                      )),
                  const SizedBox(height: 40),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  final BudgetLine line;
  const _OverallCard({required this.line});

  Future<void> _edit(BuildContext context) async {
    final cents = await _editBudgetDialog(
        context, 'Monthly budget', line.limit);
    if (cents != null) await AppSettings.setOverallBudget(cents);
  }

  @override
  Widget build(BuildContext context) {
    final sym = AppSettings.currencySymbol;
    final color = _budgetColor(line.state);

    if (!line.hasLimit) {
      return GestureDetector(
        onTap: () => _edit(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              Icon(Icons.savings_outlined,
                  size: 32, color: AppTheme.textSecondary),
              const SizedBox(height: 10),
              const Text('Set a monthly budget',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Track your spending against a monthly cap.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('This month',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: () => _edit(context),
                child: Icon(Icons.edit_outlined,
                    size: 16, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(Money.withSymbol(line.spent, decimals: 0),
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text('of ${Money.withSymbol(line.limit, decimals: 0)}',
                  style: TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          _BudgetBar(fraction: line.fraction, color: color, height: 10),
          const SizedBox(height: 10),
          Text(_statusLine(line, sym),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

String _statusLine(BudgetLine line, String sym) {
  if (line.isOver) {
    return 'Over by ${Money.withSymbol(-line.remaining, decimals: 0)}';
  }
  final left = '${Money.withSymbol(line.remaining, decimals: 0)} left';
  if (line.aheadOfPace) return '$left · spending ahead of pace';
  if (line.isNear) return '$left · almost there';
  return left;
}

class _CategoryRow extends StatelessWidget {
  final String category;
  final BudgetLine line;
  const _CategoryRow({required this.category, required this.line});

  Future<void> _edit(BuildContext context) async {
    final cents =
        await _editBudgetDialog(context, '$category budget', line.limit);
    if (cents != null) await AppSettings.setCategoryBudget(category, cents);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.categoryColor(category);
    final color = _budgetColor(line.state);
    return InkWell(
      onTap: () => _edit(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(category,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                ),
                if (line.hasLimit)
                  Text(
                    '${Money.withSymbol(line.spent, decimals: 0)} / ${Money.withSymbol(line.limit, decimals: 0)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: line.isOver ? AppTheme.errorColor : null),
                  )
                else
                  Text(
                    line.spent > 0
                        ? '${Money.withSymbol(line.spent, decimals: 0)} · Set'
                        : 'Set budget',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
              ],
            ),
            if (line.hasLimit) ...[
              const SizedBox(height: 8),
              _BudgetBar(fraction: line.fraction, color: color, height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetBar extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;
  const _BudgetBar(
      {required this.fraction, required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: AppTheme.surfaceMid,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Compact budget tile for the Transactions home: overall progress this month,
/// or a prompt to set one. Tapping opens the full Budget screen.
class BudgetSummaryCard extends StatelessWidget {
  final List<ExpenseModel> expenses;
  const BudgetSummaryCard({super.key, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spent = BudgetMath.total(BudgetMath.spendByCategory(
        expenses, Services.currentUserId, now));
    final line = BudgetLine(
      limit: AppSettings.overallBudget,
      spent: spent,
      monthElapsed: BudgetMath.monthElapsed(now),
    );
    final color = _budgetColor(line.state);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BudgetScreen())),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: !line.hasLimit
              ? Row(
                  children: [
                    Icon(Icons.savings_outlined,
                        size: 20, color: AppTheme.textSecondary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Set a monthly budget',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppTheme.textSecondary),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Monthly budget',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary)),
                        const Spacer(),
                        Text(
                          line.isOver
                              ? 'Over budget'
                              : '${Money.withSymbol(line.remaining, decimals: 0)} left',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _BudgetBar(fraction: line.fraction, color: color, height: 8),
                    const SizedBox(height: 8),
                    Text(
                      '${Money.withSymbol(line.spent, decimals: 0)} of ${Money.withSymbol(line.limit, decimals: 0)}',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
