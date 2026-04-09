import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/user_model.dart';
import '../services/hive_service.dart';
import '../utils/app_theme.dart';
import 'add_expense_screen.dart';
import 'bill_scan_screen.dart';
import 'settlement_screen.dart';

class GroupDetailScreen extends StatelessWidget {
  final GroupModel group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => SettlementScreen(group: group))),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Settle Up'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<ExpenseModel>('expenses').listenable(),
        builder: (context, _, __) {
          final expenses = HiveService.getExpensesByGroup(group.id);
          final members = group.memberIds
              .map(HiveService.getUserById)
              .whereType<UserModel>()
              .toList();
          final balances = HiveService.computeBalances(group.id);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(expenses),
                      const SizedBox(height: 20),
                      _buildMembersSection(members, balances),
                      const SizedBox(height: 20),
                      _buildActionButtons(context, members),
                      const SizedBox(height: 16),
                      const SectionHeader(title: 'Expenses'),
                    ],
                  ),
                ),
              ),
              if (expenses.isEmpty)
                const SliverFillRemaining(child: _EmptyExpenses())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ExpenseCard(
                          expense: expenses[i],
                          members: members,
                          onDelete: () =>
                              HiveService.deleteExpense(expenses[i].id),
                        ),
                      ),
                      childCount: expenses.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(List<ExpenseModel> expenses) {
    final groupExp = expenses.where((e) => !e.isPersonal).toList();
    final total = groupExp.fold<double>(0, (s, e) => s + e.totalAmount);
    return Row(
      children: [
        Expanded(
          child: InfoCard(
            label: 'Total Spent',
            value: 'Rs ${total.toStringAsFixed(0)}',
            icon: Icons.payments_outlined,
            valueColor: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InfoCard(
            label: 'Transactions',
            value: '${groupExp.length}',
            icon: Icons.receipt_long_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InfoCard(
            label: 'Members',
            value: '${group.memberIds.length}',
            icon: Icons.people_outline,
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection(
      List<UserModel> members, Map<String, double> balances) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Members & Balances'),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: members.asMap().entries.map((e) {
              final i = e.key;
              final m = e.value;
              final balance = balances[m.id] ?? 0;
              return Column(
                children: [
                  if (i > 0) const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.12),
                      child: Text(m.name[0].toUpperCase(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ),
                    title: Text(m.name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: balance.abs() < 0.01
                        ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Text('Settled',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                    )
                        : _BalanceBadge(balance: balance),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
      BuildContext context, List<UserModel> members) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) =>
                        AddExpenseScreen(group: group, members: members))),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Expense'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) =>
                        BillScanScreen(group: group, members: members))),
            icon: const Icon(Icons.document_scanner_outlined, size: 18),
            label: const Text('Scan Bill'),
          ),
        ),
      ],
    );
  }
}

class _BalanceBadge extends StatelessWidget {
  final double balance;
  const _BalanceBadge({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isPos = balance > 0;
    final color = isPos ? AppTheme.successColor : AppTheme.errorColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isPos ? 'Gets back' : 'Owes',
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
        Text(
          'Rs ${balance.abs().toStringAsFixed(2)}',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final ExpenseModel expense;
  final List<UserModel> members;
  final VoidCallback onDelete;

  const _ExpenseCard({
    required this.expense,
    required this.members,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final payer = members.firstWhere(
          (m) => m.id == expense.payerId,
      orElse: () => UserModel(id: '', name: 'Unknown'),
    );
    final participantCount = expense.participantIds.length;

    return Card(
      child: InkWell(
        onLongPress: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Expense'),
              content: Text('Delete "${expense.title}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.errorColor),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (ok == true) onDelete();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.categoryColor(expense.category)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _categoryIcon(expense.category),
                  color: AppTheme.categoryColor(expense.category),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(expense.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      expense.isPersonal
                          ? 'Personal expense'
                          : 'Paid by ${payer.name}  •  $participantCount people',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    CategoryBadge(category: expense.category),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Rs ${expense.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String cat) {
    switch (cat) {
      case 'Groceries': return Icons.shopping_cart_outlined;
      case 'Food & Drink': return Icons.restaurant_outlined;
      case 'Electronics': return Icons.devices_outlined;
      case 'Clothing': return Icons.checkroom_outlined;
      case 'Transport': return Icons.directions_car_outlined;
      case 'Health': return Icons.local_hospital_outlined;
      case 'Entertainment': return Icons.movie_outlined;
      case 'Utilities': return Icons.bolt_outlined;
      default: return Icons.receipt_outlined;
    }
  }
}

class _EmptyExpenses extends StatelessWidget {
  const _EmptyExpenses();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: AppTheme.surfaceHigh),
          const SizedBox(height: 12),
          const Text('No expenses yet',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          const Text(
            'Add an expense or scan a bill\nto get started',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}