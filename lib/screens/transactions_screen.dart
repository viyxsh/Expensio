import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/expense_model.dart';
import '../services/app_settings.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';
import 'add_personal_expense_screen.dart';
import 'monthly_unwrapped.dart';

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
      body: ListenableBuilder(
        listenable: Services.state,
        builder: (context, _) {
          final all = Services.state.getAllExpenses();

          final filtered = _filterCategory == 'All'
              ? all
              : all.where((e) => e.category == _filterCategory).toList();

          return CustomScrollView(
            slivers: [
              // Monthly Unwrapped recap (hidden when this month has no spending)
              SliverToBoxAdapter(
                child: MonthlyUnwrappedCard(expenses: all),
              ),

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
                        Text(
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

              const SliverPadding(padding: EdgeInsets.only(bottom: 104)),
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
        foregroundColor: AppTheme.onPrimary,
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
  _StatsPeriod _period = _StatsPeriod.month;
  late bool _expanded = AppSettings.chartsExpanded;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    AppSettings.setChartsExpanded(_expanded);
  }

  String get _periodLabel => switch (_period) {
        _StatsPeriod.week => 'Last 7 Days',
        _StatsPeriod.month => 'This Month',
        _StatsPeriod.year => 'This Year',
      };

  String get _periodNoun => switch (_period) {
        _StatsPeriod.week => 'in the last 7 days',
        _StatsPeriod.month => 'this month',
        _StatsPeriod.year => 'this year',
      };

  /// Inclusive start of the selected window. Week = the last 7 days (rolling),
  /// month = the 1st of this month, year = Jan 1st of this year.
  DateTime _periodStart() {
    final now = DateTime.now();
    return switch (_period) {
      _StatsPeriod.week => DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6)),
      _StatsPeriod.month => DateTime(now.year, now.month, 1),
      _StatsPeriod.year => DateTime(now.year, 1, 1),
    };
  }

  /// Expenses within the selected time window, drives the summary tiles, the
  /// donut and the bar chart so all three agree on the period.
  List<ExpenseModel> _withinPeriod(List<ExpenseModel> all) {
    final start = _periodStart();
    return all.where((e) => !e.createdAt.isBefore(start)).toList();
  }

  /// Bucket [expenses] into bars at the period's natural granularity:
  /// weekdays for week, weeks for month, months for year. Amounts in major
  /// units (for the axis); each bar carries its short axis label.
  List<_Bar> _buildBars(List<ExpenseModel> expenses) {
    final now = DateTime.now();
    int cents(int i, bool Function(DateTime) inBucket) => expenses
        .where((e) => inBucket(e.createdAt))
        .fold<int>(0, (s, e) => s + e.totalAmount);

    switch (_period) {
      case _StatsPeriod.week:
        return List.generate(7, (i) {
          final day = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: 6 - i));
          final next = day.add(const Duration(days: 1));
          final sum = cents(i,
              (d) => !d.isBefore(day) && d.isBefore(next));
          return _Bar(
              label: DateFormat('E').format(day)[0], amount: Money.toMajor(sum));
        });
      case _StatsPeriod.month:
        final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
        final weeks = (daysInMonth / 7).ceil();
        return List.generate(weeks, (i) {
          final from = DateTime(now.year, now.month, i * 7 + 1);
          final to = i == weeks - 1
              ? DateTime(now.year, now.month + 1, 1)
              : DateTime(now.year, now.month, (i + 1) * 7 + 1);
          final sum = cents(i,
              (d) => !d.isBefore(from) && d.isBefore(to));
          return _Bar(label: 'W${i + 1}', amount: Money.toMajor(sum));
        });
      case _StatsPeriod.year:
        return List.generate(12, (i) {
          final from = DateTime(now.year, i + 1, 1);
          final to = DateTime(now.year, i + 2, 1);
          final sum = cents(i,
              (d) => !d.isBefore(from) && d.isBefore(to));
          return _Bar(
              label: DateFormat('MMM').format(from)[0],
              amount: Money.toMajor(sum));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expenses.isEmpty) return const SizedBox.shrink();

    final periodExpenses = _withinPeriod(widget.expenses);

    // Category breakdown for pie chart (totals in cents)
    final catTotals = <String, int>{};
    for (final e in periodExpenses) {
      catTotals[e.category] =
          (catTotals[e.category] ?? 0) + e.totalAmount;
    }
    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total =
    periodExpenses.fold<int>(0, (s, e) => s + e.totalAmount);

    // Bar chart bucketed at the period's natural granularity.
    final barData = _buildBars(periodExpenses);
    final maxBar =
    barData.map((d) => d.amount).fold<double>(1, (a, b) => a > b ? a : b);
    // Bars shrink as their count grows so 12 months still fit the width.
    final barWidth = barData.length <= 7
        ? 22.0
        : (barData.length <= 8 ? 16.0 : 9.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period selector + collapse toggle
          Row(
            children: [
              Expanded(
                child: _PeriodSelector(
                  selected: _period,
                  onChanged: (p) => setState(() => _period = p),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _toggleExpanded,
                tooltip: _expanded ? 'Hide charts' : 'Show charts',
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.bar_chart_outlined,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Summary row
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Total Spent',
                  value:
                      '${AppSettings.currencySymbol} ${_compact(Money.toMajor(total))}',
                  icon: Icons.payments_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: 'Transactions',
                  value: '${periodExpenses.length}',
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
          if (_expanded) ...[
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
                Text(_periodLabel,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                if (!barData.any((d) => d.amount > 0))
                  SizedBox(
                    height: 120,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.show_chart,
                              size: 26, color: AppTheme.surfaceMid),
                          const SizedBox(height: 8),
                          Text('No spending $_periodNoun',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  )
                else
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
                                  barData[i].label,
                                  style: TextStyle(
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
                              width: barWidth,
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
                              '${AppSettings.currencySymbol} ${rod.toY.toStringAsFixed(0)}',
                              TextStyle(
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
                  Text('By Category',
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
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
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
                                value: e.value.value.toDouble(),
                                title: isTouched
                                    ? '${pct.toStringAsFixed(0)}%'
                                    : '',
                                titleStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.surface,
                                ),
                                radius: isTouched ? 38 : 32,
                              );
                            }).toList(),
                          ),
                        ),
                            // Total spent shown in the donut hole.
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${AppSettings.currencySymbol}${_compact(Money.toMajor(total))}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                                Text('total',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                          ],
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
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textPrimary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${pct.toStringAsFixed(0)}%',
                                    style: TextStyle(
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

class _Bar {
  final String label;
  final double amount;
  _Bar({required this.label, required this.amount});
}

/// Small circular avatar showing the first letter of a name, tinted by a
/// stable per-name colour so payers are visually distinguishable.
class _InitialAvatar extends StatelessWidget {
  final String name;
  const _InitialAvatar({required this.name});

  static const _palette = [
    Color(0xFF00E5BE), Color(0xFFFF7043), Color(0xFF448AFF),
    Color(0xFFE040FB), Color(0xFF40C4FF), Color(0xFFFFD740),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final color = _palette[trimmed.hashCode.abs() % _palette.length];
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

enum _StatsPeriod { week, month, year }

class _PeriodSelector extends StatelessWidget {
  final _StatsPeriod selected;
  final ValueChanged<_StatsPeriod> onChanged;
  const _PeriodSelector({required this.selected, required this.onChanged});

  static const _labels = {
    _StatsPeriod.week: 'Week',
    _StatsPeriod.month: 'Month',
    _StatsPeriod.year: 'Year',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: _StatsPeriod.values.map((p) {
          final sel = p == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(p),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  _labels[p]!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? AppTheme.onPrimary : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
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
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ),
          Text(label,
              style: TextStyle(
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
                  color: sel ? AppTheme.onPrimary : AppTheme.textSecondary,
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
        style: TextStyle(
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
    final payer = Services.state.getUserById(expense.payerId);
    final group = Services.state.getGroupById(expense.groupId);
    final payerName = payer?.name ?? 'Unknown';
    final groupName = group?.name ?? '';

    final participantCount = expense.participantIds.length;
    final isGroup = !expense.isPersonal && participantCount > 1;

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
        await Services.state.deleteExpense(expense.id);

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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                if (!expense.isPersonal) ...[
                  _InitialAvatar(name: payerName),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    expense.isPersonal
                        ? 'Personal'
                        : 'Paid by $payerName'
                            '${groupName.isNotEmpty ? '  •  $groupName' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                CategoryBadge(category: expense.category),
              ],
            ),
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.withSymbol(expense.totalAmount, decimals: 0),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              if (isGroup)
                Text('total',
                    style: TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
            ],
          ),
          isThreeLine: false,
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