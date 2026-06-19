import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense_model.dart';
import '../services/app_settings.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

/// A Spotify-Wrapped-style recap of one month's spending, grouped by category
/// (the "genre" of each transaction). Pure data, computed from expenses.
class MonthlyWrapped {
  final DateTime month;
  final int totalCents;
  final int count;
  final List<MapEntry<String, int>> categories; // sorted by spend, descending
  final ExpenseModel? biggest;

  const MonthlyWrapped({
    required this.month,
    required this.totalCents,
    required this.count,
    required this.categories,
    required this.biggest,
  });

  bool get isEmpty => count == 0;
  String get topCategory =>
      categories.isEmpty ? 'General' : categories.first.key;
  int get topCategoryCents => categories.isEmpty ? 0 : categories.first.value;
  double get topCategoryPct =>
      totalCents == 0 ? 0 : topCategoryCents / totalCents * 100;

  /// Build the recap for the calendar month containing [month].
  static MonthlyWrapped forMonth(List<ExpenseModel> all, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final inMonth = all
        .where((e) =>
            !e.createdAt.isBefore(start) && e.createdAt.isBefore(end))
        .toList();

    final catTotals = <String, int>{};
    var total = 0;
    ExpenseModel? biggest;
    for (final e in inMonth) {
      catTotals[e.category] = (catTotals[e.category] ?? 0) + e.totalAmount;
      total += e.totalAmount;
      if (biggest == null || e.totalAmount > biggest.totalAmount) biggest = e;
    }
    final cats = catTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return MonthlyWrapped(
      month: start,
      totalCents: total,
      count: inMonth.length,
      categories: cats,
      biggest: biggest,
    );
  }
}

/// A playful persona for a category, used as the headline of the recap.
({String emoji, String title}) personaFor(String category) {
  switch (category) {
    case 'Groceries':
      return (emoji: '🛒', title: 'Stock-Up Champion');
    case 'Food & Drink':
      return (emoji: '🍔', title: 'Certified Foodie');
    case 'Electronics':
      return (emoji: '🔌', title: 'Tech Enthusiast');
    case 'Clothing':
      return (emoji: '🧥', title: 'Fashion Forward');
    case 'Transport':
      return (emoji: '🚗', title: 'Always On The Move');
    case 'Health':
      return (emoji: '💪', title: 'Self-Care Mode');
    case 'Entertainment':
      return (emoji: '🎬', title: 'Good Times Only');
    case 'Utilities':
      return (emoji: '💡', title: 'Keeping It Running');
    default:
      return (emoji: '✨', title: 'A Bit of Everything');
  }
}

String _compact(int cents) {
  final v = Money.toMajor(cents);
  if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

/// Hero card on the Transactions home page that teases the month's recap and
/// opens the full story on tap. Hides itself when the month has no spending.
class MonthlyUnwrappedCard extends StatelessWidget {
  final List<ExpenseModel> expenses;
  const MonthlyUnwrappedCard({super.key, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final w = MonthlyWrapped.forMonth(expenses, DateTime.now());
    if (w.isEmpty) return const SizedBox.shrink();

    final accent = AppTheme.categoryColor(w.topCategory);
    final persona = personaFor(w.topCategory);
    final sym = AppSettings.currencySymbol;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MonthlyUnwrappedScreen(wrapped: w)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.30),
                accent.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${DateFormat('MMMM').format(w.month).toUpperCase()} UNWRAPPED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: accent,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.auto_awesome, size: 16, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(persona.emoji, style: const TextStyle(fontSize: 34)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(persona.title,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        Text('Your ${w.topCategory} era',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _miniStat('Spent', '$sym ${_compact(w.totalCents)}'),
                  _dot(),
                  _miniStat('Transactions', '${w.count}'),
                  _dot(),
                  _miniStat('Top share',
                      '${w.topCategoryPct.toStringAsFixed(0)}%'),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text('Tap to see your month',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
            color: AppTheme.textSecondary, shape: BoxShape.circle),
      );

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],
      );
}

/// Full-screen, swipeable recap. Each page is a full-bleed gradient slide,
/// Spotify-Wrapped style, ending with a shareable summary.
class MonthlyUnwrappedScreen extends StatefulWidget {
  final MonthlyWrapped wrapped;
  const MonthlyUnwrappedScreen({super.key, required this.wrapped});

  @override
  State<MonthlyUnwrappedScreen> createState() => _MonthlyUnwrappedScreenState();
}

class _MonthlyUnwrappedScreenState extends State<MonthlyUnwrappedScreen> {
  final _controller = PageController();
  int _page = 0;

  MonthlyWrapped get w => widget.wrapped;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _share() {
    final sym = AppSettings.currencySymbol;
    final persona = personaFor(w.topCategory);
    final month = DateFormat('MMMM yyyy').format(w.month);
    Share.share(
      'My $month Unwrapped on Expensio ${persona.emoji}\n'
      '$sym ${Money.format(w.totalCents, decimals: 0)} across ${w.count} '
      'transactions.\n'
      'Top category: ${w.topCategory} '
      '(${w.topCategoryPct.toStringAsFixed(0)}%) — ${persona.title}!',
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.categoryColor(w.topCategory);
    final slides = <Widget>[
      _intro(),
      _total(),
      _topCategory(),
      if (w.biggest != null) _biggest(w.biggest!),
      _recap(),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: slides,
          ),
          // Top bar: progress dots + close.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(
                        slides.length,
                        (i) => Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: i <= _page
                                  ? Colors.white
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          // Hint to keep swiping (hidden on the last slide).
          if (_page < slides.length - 1)
            Positioned(
              right: 20,
              bottom: 28,
              child: Row(
                children: [
                  Text('Swipe',
                      style: TextStyle(
                          color: accent, fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, color: accent),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Slides

  Widget _slide(List<Color> colors, Widget child) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 80, 28, 80),
            child: child,
          ),
        ),
      );

  List<Color> _grad(Color c) =>
      [Color.alphaBlend(c.withValues(alpha: 0.55), Colors.black), Colors.black];

  Widget _intro() {
    final accent = AppTheme.categoryColor(w.topCategory);
    return _slide(
      _grad(accent),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('✨', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(DateFormat('MMMM').format(w.month),
              style: const TextStyle(
                  fontSize: 44,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const Text('unwrapped',
              style: TextStyle(
                  fontSize: 44,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 16),
          const Text("Here's how your month went.",
              style: TextStyle(fontSize: 15, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _total() {
    final sym = AppSettings.currencySymbol;
    return _slide(
      _grad(const Color(0xFF448AFF)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('YOU SPENT',
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$sym ${Money.format(w.totalCents, decimals: 0)}',
                style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ),
          const SizedBox(height: 16),
          Text('across ${w.count} transaction${w.count == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 18, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _topCategory() {
    final accent = AppTheme.categoryColor(w.topCategory);
    final persona = personaFor(w.topCategory);
    final sym = AppSettings.currencySymbol;
    return _slide(
      _grad(accent),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('YOUR TOP CATEGORY',
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
          const SizedBox(height: 20),
          Text(persona.emoji, style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 12),
          Text(w.topCategory,
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text(
              '${w.topCategoryPct.toStringAsFixed(0)}% of your spending · '
              '$sym ${_compact(w.topCategoryCents)}',
              style: const TextStyle(fontSize: 15, color: Colors.white70)),
          const SizedBox(height: 24),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text("You're a ${persona.title}",
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _biggest(ExpenseModel e) {
    final accent = AppTheme.categoryColor(e.category);
    final sym = AppSettings.currencySymbol;
    return _slide(
      _grad(accent),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('BIGGEST SPLURGE',
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
          const SizedBox(height: 16),
          Text(e.title,
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 10),
          Text('$sym ${Money.format(e.totalAmount, decimals: 0)}',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text('in ${e.category} · ${DateFormat('MMM d').format(e.createdAt)}',
              style: const TextStyle(fontSize: 15, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _recap() {
    final sym = AppSettings.currencySymbol;
    final top3 = w.categories.take(3).toList();
    return _slide(
      _grad(AppTheme.categoryColor(w.topCategory)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("THAT'S A WRAP",
              style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70)),
          const SizedBox(height: 20),
          Text('${DateFormat('MMMM').format(w.month)} in numbers',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 20),
          _recapRow('Total spent',
              '$sym ${Money.format(w.totalCents, decimals: 0)}'),
          _recapRow('Transactions', '${w.count}'),
          for (var i = 0; i < top3.length; i++)
            _recapRow(i == 0 ? 'Top category' : '#${i + 1} category',
                '${top3[i].key}  (${(top3[i].value / w.totalCents * 100).toStringAsFixed(0)}%)'),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Share my Unwrapped'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recapRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 14, color: Colors.white70)),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      );
}
