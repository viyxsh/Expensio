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

/// Vivid two-tone gradients per slide, kept independent of the (sometimes
/// muddy) category accent so every slide reads as bold and high-contrast.
class _Grad {
  static const intro = [Color(0xFF4F46E5), Color(0xFF9333EA)];
  static const total = [Color(0xFF06B6D4), Color(0xFF2563EB)];
  static const top = [Color(0xFFF59E0B), Color(0xFFEF4444)];
  static const biggest = [Color(0xFF7C3AED), Color(0xFFDB2777)];
  static const recap = [Color(0xFF0D9488), Color(0xFF10B981)];
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
    final dark = AppTheme.isDark;
    // A version of the accent with enough contrast for the small label on the
    // tinted card: bright on dark, deepened on light.
    final accentText = HSLColor.fromColor(accent)
        .withLightness(dark ? 0.72 : 0.40)
        .withSaturation(0.85)
        .toColor();

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
                accent.withValues(alpha: dark ? 0.40 : 0.20),
                Color.alphaBlend(
                    accent.withValues(alpha: dark ? 0.10 : 0.04),
                    AppTheme.surface),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: accent.withValues(alpha: dark ? 0.45 : 0.30)),
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
                      color: accentText,
                    ),
                  ),
                  const Spacer(),
                  _Pulse(
                      child: Icon(Icons.auto_awesome,
                          size: 16, color: accentText)),
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
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        Text('Your ${w.topCategory} era',
                            style: TextStyle(
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
                  Text('Tap to see your month',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: accentText),
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
        decoration: BoxDecoration(
            color: AppTheme.textSecondary, shape: BoxShape.circle),
      );

  Widget _miniStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],
      );
}

/// Full-screen, swipeable recap. Each page is a vivid full-bleed slide whose
/// content animates in as it becomes active, Spotify-Wrapped style.
class MonthlyUnwrappedScreen extends StatefulWidget {
  final MonthlyWrapped wrapped;
  const MonthlyUnwrappedScreen({super.key, required this.wrapped});

  @override
  State<MonthlyUnwrappedScreen> createState() => _MonthlyUnwrappedScreenState();
}

class _MonthlyUnwrappedScreenState extends State<MonthlyUnwrappedScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _started = false;

  MonthlyWrapped get w => widget.wrapped;

  @override
  void initState() {
    super.initState();
    // Flip after the first frame so slide 0 animates in on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _active(int i) => _started && _page == i;

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
    final slides = <Widget Function(bool)>[
      _intro,
      _total,
      _topCategory,
      if (w.biggest != null) (a) => _biggest(w.biggest!, a),
      _recap,
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (var i = 0; i < slides.length; i++) slides[i](_active(i)),
            ],
          ),
          // Top bar: animated progress segments + close.
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
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: AnimatedFractionallySizedBox(
                              duration: const Duration(milliseconds: 300),
                              widthFactor: i < _page
                                  ? 1.0
                                  : (i == _page ? 1.0 : 0.0),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
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
          if (_page < slides.length - 1)
            const Positioned(
              right: 20,
              bottom: 28,
              child: _Pulse(
                child: Row(
                  children: [
                    Text('Swipe',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Slides

  Widget _slide({
    required List<Color> colors,
    String? glyph,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (glyph != null)
            Positioned(
              top: 60,
              right: -40,
              child: Text(glyph,
                  style: TextStyle(
                      fontSize: 240,
                      color: Colors.white.withValues(alpha: 0.10))),
            ),
          // Scrim so white text stays legible over the brightest part.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.45, 1.0],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 80, 28, 72),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
          color: Colors.white70));

  Widget _intro(bool active) {
    return _slide(
      colors: _Grad.intro,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const _Pulse(big: true, child: Text('✨', style: TextStyle(fontSize: 60))),
          const SizedBox(height: 16),
          _Reveal(
            active: active,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMMM').format(w.month),
                    style: const TextStyle(
                        fontSize: 46,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const Text('unwrapped',
                    style: TextStyle(
                        fontSize: 46,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 16),
                const Text("Here's how your month went.",
                    style: TextStyle(fontSize: 15, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _total(bool active) {
    final sym = AppSettings.currencySymbol;
    return _slide(
      colors: _Grad.total,
      glyph: '💸',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Reveal(active: active, child: _label('YOU SPENT')),
          const SizedBox(height: 12),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _CountUp(
                active: active,
                cents: w.totalCents,
                prefix: '$sym ',
                style: const TextStyle(
                    fontSize: 66,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 240),
            child: Text(
                'across ${w.count} transaction${w.count == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _topCategory(bool active) {
    final persona = personaFor(w.topCategory);
    final sym = AppSettings.currencySymbol;
    return _slide(
      colors: _Grad.top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Reveal(active: active, child: _label('YOUR TOP CATEGORY')),
          const SizedBox(height: 20),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 100),
            child: _Pulse(
                big: true,
                child:
                    Text(persona.emoji, style: const TextStyle(fontSize: 76))),
          ),
          const SizedBox(height: 12),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 200),
            child: Text(w.topCategory,
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const SizedBox(height: 8),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 300),
            child: Text(
                '${w.topCategoryPct.toStringAsFixed(0)}% of your spending · '
                '$sym ${_compact(w.topCategoryCents)}',
                style: const TextStyle(fontSize: 15, color: Colors.white70)),
          ),
          const SizedBox(height: 24),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 420),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text("You're a ${persona.title}",
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _biggest(ExpenseModel e, bool active) {
    final sym = AppSettings.currencySymbol;
    return _slide(
      colors: _Grad.biggest,
      glyph: '🤑',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Reveal(active: active, child: _label('BIGGEST SPLURGE')),
          const SizedBox(height: 16),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 120),
            child: Text(e.title,
                style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const SizedBox(height: 10),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 220),
            child: _CountUp(
              active: active,
              cents: e.totalAmount,
              prefix: '$sym ',
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 320),
            child: Text(
                'in ${e.category} · ${DateFormat('MMM d').format(e.createdAt)}',
                style: const TextStyle(fontSize: 15, color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _recap(bool active) {
    final sym = AppSettings.currencySymbol;
    final top3 = w.categories.take(3).toList();
    final rows = <Widget>[
      _recapRow(
          'Total spent', '$sym ${Money.format(w.totalCents, decimals: 0)}'),
      _recapRow('Transactions', '${w.count}'),
      for (var i = 0; i < top3.length; i++)
        _recapRow(i == 0 ? 'Top category' : '#${i + 1} category',
            '${top3[i].key}  (${(top3[i].value / w.totalCents * 100).toStringAsFixed(0)}%)'),
    ];

    return _slide(
      colors: _Grad.recap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Reveal(active: active, child: _label("THAT'S A WRAP")),
          const SizedBox(height: 20),
          _Reveal(
            active: active,
            delay: const Duration(milliseconds: 100),
            child: Text('${DateFormat('MMMM').format(w.month)} in numbers',
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < rows.length; i++)
            _Reveal(
              active: active,
              delay: Duration(milliseconds: 220 + i * 90),
              child: rows[i],
            ),
          const SizedBox(height: 28),
          _Reveal(
            active: active,
            delay: Duration(milliseconds: 240 + rows.length * 90),
            child: SizedBox(
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

/// Fades and lifts its child into place. Replays whenever [active] flips true,
/// optionally after [delay], so each slide animates as it becomes visible.
class _Reveal extends StatefulWidget {
  final bool active;
  final Duration delay;
  final Widget child;
  const _Reveal({
    required this.active,
    this.delay = Duration.zero,
    required this.child,
  });

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.active) _play();
  }

  @override
  void didUpdateWidget(_Reveal old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _play();
    } else if (!widget.active && old.active) {
      _c.value = 0;
    }
  }

  Future<void> _play() async {
    if (widget.delay != Duration.zero) {
      await Future.delayed(widget.delay);
      if (!mounted) return;
    }
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
            offset: Offset(0, (1 - _a.value) * 20), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Counts a money value up from zero to [cents] (whenever [active] is true).
class _CountUp extends StatelessWidget {
  final bool active;
  final int cents;
  final String prefix;
  final TextStyle style;
  const _CountUp({
    required this.active,
    required this.cents,
    required this.prefix,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? cents.toDouble() : 0),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) =>
          Text('$prefix${Money.format(v.round(), decimals: 0)}', style: style),
    );
  }
}

/// Gentle, continuous scale pulse for accent glyphs (sparkles, emoji, hints).
class _Pulse extends StatefulWidget {
  final Widget child;
  final bool big;
  const _Pulse({required this.child, this.big = false});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hi = widget.big ? 1.12 : 1.18;
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: hi)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
