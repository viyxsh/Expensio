import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/hive_service.dart';
import '../utils/app_theme.dart';
import 'add_personal_expense_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _filterCategory = 'All';
  static const List<String> _filterOptions = [
    'All','Groceries','Food & Drink','Electronics','Clothing',
    'Transport','Health','Entertainment','Utilities','General',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<ExpenseModel>('expenses').listenable(),
        builder: (context, _, __) {
          final all = HiveService.getAllExpenses()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final filtered = _filterCategory == 'All'
              ? all
              : all.where((e) => e.category == _filterCategory).toList();

          return CustomScrollView(
            slivers: [
              // Charts section
              SliverToBoxAdapter(
                child: _ChartsSection(expenses: all),
              ),

              // Filter bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterBarDelegate(
                  filterOptions: _filterOptions,
                  selected: _filterCategory,
                  onSelected: (v) => setState(() => _filterCategory = v),
                ),
              ),

              // Empty state
              if (filtered.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 56, color: AppTheme.surfaceMid),
                        const SizedBox(height: 16),
                        const Text('No transactions yet',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap + to add a personal expense\nor add one from a group',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, i) {
                      // Build date-grouped list
                      final grouped = _buildGrouped(filtered);
                      final keys = grouped.keys.toList();
                      // flatten into sections
                      final sections = <_Section>[];
                      for (final k in keys) {
                        sections.add(_Section(header: k, items: grouped[k]!));
                      }
                      int total = sections.fold(
                          0, (s, sec) => s + 1 + sec.items.length);
                      if (i >= total) return null;

                      int cursor = 0;
                      for (final sec in sections) {
                        if (i == cursor) {
                          return _DateHeader(label: sec.header);
                        }
                        cursor++;
                        for (int j = 0; j < sec.items.length; j++) {
                          if (i == cursor) {
                            return _TransactionTile(expense: sec.items[j]);
                          }
                          cursor++;
                        }
                      }
                      return null;
                    },
                    childCount: _countItems(_buildGrouped(filtered)),
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 90)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const AddPersonalExpenseScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New Transaction'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.black,
      ),
    );
  }

  Map<String, List<ExpenseModel>> _buildGrouped(List<ExpenseModel> list) {
    final grouped = <String, List<ExpenseModel>>{};
    for (final e in list) {
      final key = _dateKey(e.createdAt);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    return grouped;
  }

  int _countItems(Map<String, List<ExpenseModel>> grouped) {
    return grouped.entries.fold(0, (s, e) => s + 1 + e.value.length);
  }

  String _dateKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dt.year, dt.month, dt.day);
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(dt);
  }
}

class _Section {
  final String header;
  final List<ExpenseModel> items;
  _Section({required this.header, required this.items});
}

// Charts 

class _ChartsSection extends StatefulWidget {
  final List<ExpenseModel> expenses;
  const _ChartsSection({required this.expenses});

  @override
  State<_ChartsSection> createState() => _ChartsSectionState();
}

class _ChartsSectionState extends State<_ChartsSection> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.expenses.isEmpty) return const SizedBox.shrink();

    // Category breakdown for pie chart
    final catTotals = <String, double>{};
    for (final e in widget.expenses) {
      catTotals[e.category] =
          (catTotals[e.category] ?? 0) + e.totalAmount;
    }
    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total =
    widget.expenses.fold<double>(0, (s, e) => s + e.totalAmount);

    // Last 7 days bar chart
    final now = DateTime.now();
    final barData = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final sum = widget.expenses
          .where((e) =>
      e.createdAt.isAfter(dayStart) &&
          e.createdAt.isBefore(dayEnd))
          .fold<double>(0, (s, e) => s + e.totalAmount);
      return _DayBar(day: dayStart, amount: sum);
    });
    final maxBar =
    barData.map((d) => d.amount).fold<double>(1, (a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary row
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Total Spent',
                  value: 'Rs ${_compact(total)}',
                  icon: Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: 'Transactions',
                  value: '${widget.expenses.length}',
                  icon: Icons.receipt_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: 'Categories',
                  value: '${catTotals.length}',
                  icon: Icons.category_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 7-day bar chart
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Last 7 Days',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: BarChart(
                    BarChartData(
                      maxY: maxBar * 1.25,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxBar / 3,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: AppTheme.divider,
                          strokeWidth: 1,
                          dashArray: [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= barData.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  DateFormat('E')
                                      .format(barData[i].day),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                            reservedSize: 24,
                          ),
                        ),
                      ),
                      barGroups: barData.asMap().entries.map((e) {
                        final hasData = e.value.amount > 0;
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.amount,
                              color: hasData
                                  ? AppTheme.primary
                                  : AppTheme.divider,
                              width: 22,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxBar * 1.25,
                                color: AppTheme.surface,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppTheme.primary,
                          tooltipRoundedRadius: 8,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (rod.toY == 0) return null;
                            return BarTooltipItem(
                              'Rs ${rod.toY.toStringAsFixed(0)}',
                              const TextStyle(
                                color: AppTheme.surface,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Category donut chart
          if (sorted.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('By Category',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 130,
                        width: 130,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 36,
                            pieTouchData: PieTouchData(
                              touchCallback:
                                  (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event
                                      .isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection ==
                                          null) {
                                    _touchedIndex = -1;
                                    return;
                                  }
                                  _touchedIndex = pieTouchResponse
                                      .touchedSection!
                                      .touchedSectionIndex;
                                });
                              },
                            ),
                            sections: sorted.asMap().entries.map((e) {
                              final isTouched =
                                  e.key == _touchedIndex;
                              final pct = e.value.value / total * 100;
                              return PieChartSectionData(
                                color: AppTheme.categoryColor(e.value.key),
                                value: e.value.value,
                                title: isTouched
                                    ? '${pct.toStringAsFixed(0)}%'
                                    : '',
                                titleStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.surface,
                                ),
                                radius: isTouched ? 38 : 32,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: sorted.take(5).map((e) {
                            final pct = e.value / total * 100;
                            return Padding(
                              padding:
                              const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(
                                      color: AppTheme.categoryColor(
                                          e.key),
                                      borderRadius:
                                      BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textPrimary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${pct.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

class _DayBar {
  final DateTime day;
  final double amount;
  _DayBar({required this.day, required this.amount});
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SummaryTile(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// Filter bar 

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final List<String> filterOptions;
  final String selected;
  final ValueChanged<String> onSelected;

  const _FilterBarDelegate({
    required this.filterOptions,
    required this.selected,
    required this.onSelected,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      height: 52,
      color: AppTheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: filterOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final opt = filterOptions[i];
          final sel = opt == selected;
          return GestureDetector(
            onTap: () => onSelected(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: sel ? AppTheme.primary : AppTheme.cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel ? AppTheme.primary : AppTheme.divider,
                ),
              ),
              child: Text(
                opt,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.black : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterBarDelegate old) =>
      old.selected != selected;
}

// Date header 

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// Transaction tile 
class _TransactionTile extends StatelessWidget {
  final ExpenseModel expense;
  const _TransactionTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final payer = HiveService.getUserById(expense.payerId);
    final group = HiveService.getGroupById(expense.groupId);
    final payerName = payer?.name ?? 'Unknown';
    final groupName = group?.name ?? '';

    final participantCount = expense.participantIds.length;
    final isGroup = !expense.isPersonal && participantCount > 1;

    final displayAmount = isGroup
        ? (expense.splitMap.isNotEmpty
        ? expense.splitMap.values.fold<double>(0, (s, v) => s + v) /
        expense.splitMap.length
        : expense.totalAmount / participantCount)
        : expense.totalAmount;

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Delete Transaction"),
            content:
            const Text("Are you sure you want to delete this transaction?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Delete")),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        await HiveService.deleteExpense(expense.id);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Transaction deleted")),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: ListTile(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),

          // ✅ EDIT ON TAP
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AddPersonalExpenseScreen(expense: expense),
              ),
            );
          },

          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
              AppTheme.categoryColor(expense.category).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _categoryIcon(expense.category),
              color: AppTheme.categoryColor(expense.category),
              size: 20,
            ),
          ),
          title: Text(
            expense.title,
            style:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Text(
                expense.isPersonal
                    ? 'Personal'
                    : 'Paid by $payerName'
                    '${groupName.isNotEmpty ? '  •  $groupName' : ''}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  CategoryBadge(category: expense.category),
                  if (isGroup) ...[
                    const SizedBox(width: 6),
                    TagPill(
                      label:
                      'Rs ${expense.totalAmount.toStringAsFixed(0)} total',
                      color: AppTheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddPersonalExpenseScreen(expense: expense),
                  ),
                );
              } else if (value == 'delete') {
                final confirm = await showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("Delete Transaction"),
                    content: const Text("Are you sure?"),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("Cancel")),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("Delete")),
                    ],
                  ),
                );

                if (confirm == true) {
                  await HiveService.deleteExpense(expense.id);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Transaction deleted")),
                  );
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          isThreeLine: true,
        ),
      ),
    );
  }

  IconData _categoryIcon(String c) {
    switch (c) {
      case 'Groceries':
        return Icons.shopping_cart_outlined;
      case 'Food & Drink':
        return Icons.restaurant_outlined;
      case 'Electronics':
        return Icons.devices_outlined;
      case 'Clothing':
        return Icons.checkroom_outlined;
      case 'Transport':
        return Icons.directions_car_outlined;
      case 'Health':
        return Icons.local_hospital_outlined;
      case 'Entertainment':
        return Icons.movie_outlined;
      case 'Utilities':
        return Icons.bolt_outlined;
      default:
        return Icons.receipt_outlined;
    }
  }
}