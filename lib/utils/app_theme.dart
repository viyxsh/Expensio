import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/category_store.dart';

class AppTheme {
  /// Active brightness. The app root sets this before building [theme] so the
  /// colour getters below resolve to the matching palette everywhere they're
  /// referenced (the app uses static colour refs rather than Theme.of(context)).
  static Brightness brightness = Brightness.dark;
  static bool get isDark => brightness == Brightness.dark;

  static Color _pick(Color dark, Color light) => isDark ? dark : light;

  // Brightness-dependent palette.
  static Color get bg =>
      _pick(const Color(0xFF0A0A0A), const Color(0xFFF6F6F8));
  static Color get surface =>
      _pick(const Color(0xFF141414), const Color(0xFFFFFFFF));
  static Color get surfaceHigh =>
      _pick(const Color(0xFF1E1E1E), const Color(0xFFFFFFFF));
  static Color get surfaceMid =>
      _pick(const Color(0xFF252525), const Color(0xFFECECF0));
  static Color get primary =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF0A0A0A));
  static Color get primaryDark =>
      _pick(const Color(0xFFE0E0E0), const Color(0xFF2A2A2A));

  /// Foreground that sits on top of [primary] (e.g. button labels).
  static Color get onPrimary =>
      _pick(const Color(0xFF0A0A0A), const Color(0xFFFFFFFF));

  static Color get textPrimary =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF111114));
  static Color get textSecondary =>
      _pick(const Color(0xFF8A8A8A), const Color(0xFF6B6B72));
  static Color get divider =>
      _pick(const Color(0xFF2A2A2A), const Color(0xFFE4E4EA));

  // Brightness-independent accents / status.
  static const Color errorColor    = Color(0xFFFF5252);
  static const Color successColor  = Color(0xFF69F0AE);
  static const Color warningColor  = Color(0xFFFFD740);

  // Accent colours — vivid, saturated shades so the emojis pop.
  static const Map<String, Color> categoryColors = {
    'General':       Color(0xFF546E7A),
    'Groceries':     Color(0xFFFDD835),
    'Food & Drink':  Color(0xFFFF7043),
    'Electronics':   Color(0xFF7E57C2),
    'Clothing':      Color(0xFF1E3A5F),
    'Transport':     Color(0xFF29B6F6),
    'Health':        Color(0xFF26A69A),
    'Entertainment': Color(0xFF5C6BC0),
    'Utilities':     Color(0xFF00BCD4),
  };

  // One emoji per category, shown on the picker tiles.
  static const Map<String, String> categoryEmojis = {
    'General':       '📦',
    'Groceries':     '🛒',
    'Food & Drink':  '🍽️',
    'Electronics':   '💻',
    'Clothing':      '👕',
    'Transport':     '🚕',
    'Health':        '💊',
    'Entertainment': '🎬',
    'Utilities':     '💡',
  };

  static Color categoryColor(String category) {
    final override = CategoryStore.colorOverride(category);
    if (override != null) return Color(override);
    final fixed = categoryColors[category];
    if (fixed != null) return fixed;
    final custom = CategoryStore.byName(category);
    if (custom != null) return Color(custom.colorValue);
    return const Color(0xFF7C6F64);
  }

  static String categoryEmoji(String category) {
    final fixed = categoryEmojis[category];
    if (fixed != null) return fixed;
    return CategoryStore.byName(category)?.emoji ?? '📦';
  }

  /// Screen-background tint for the currently selected category: the normal
  /// background leaning toward the category colour.
  static Color categoryTintedBg(String category) =>
      Color.lerp(bg, categoryColor(category), 0.25)!;

  // cardBg alias
  static Color get cardBg => surface;

  static ThemeData get theme {
    final overlay = isDark ? Brightness.light : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: overlay,
      statusBarBrightness: brightness,
      systemNavigationBarColor: surface,
      systemNavigationBarIconBrightness: overlay,
    ));

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: primary,
        onSecondary: onPrimary,
        surface: surface,
        onSurface: textPrimary,
        error: errorColor,
        onError: Colors.white,
        outline: divider,
      ),
    );

    final appBarOverlay =
        isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      primaryTextTheme: GoogleFonts.poppinsTextTheme(base.primaryTextTheme),

      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: appBarOverlay,
        titleTextStyle: GoogleFonts.poppins(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: divider, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMid,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.poppins(color: textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.poppins(color: textSecondary, fontSize: 14),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceMid,
        selectedColor: primary.withValues(alpha: 0.15),
        disabledColor: surfaceMid,
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: textPrimary),
        secondaryLabelStyle:
        GoogleFonts.poppins(fontSize: 13, color: onPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: divider),
        ),
        checkmarkColor: onPrimary,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
              ? onPrimary
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
              (s) =>
          s.contains(WidgetState.selected) ? primary : surfaceHigh,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: divider, thickness: 1, space: 1,
      ),

      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: GoogleFonts.poppins(
            fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
        subtitleTextStyle:
        GoogleFonts.poppins(fontSize: 12, color: textSecondary),
        iconColor: textSecondary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle:
        GoogleFonts.poppins(color: textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? primary : textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primary, size: 22);
          }
          return IconThemeData(color: textSecondary, size: 22);
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: GoogleFonts.poppins(
            fontSize: 17, fontWeight: FontWeight.w700, color: textPrimary),
        contentTextStyle:
        GoogleFonts.poppins(fontSize: 14, color: textSecondary),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: divider),
        ),
        textStyle:
        GoogleFonts.poppins(fontSize: 13, color: textPrimary),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(surfaceHigh),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: divider),
            ),
          ),
        ),
      ),

      datePickerTheme: DatePickerThemeData(
        backgroundColor: surfaceHigh,
        headerBackgroundColor: surface,
        headerForegroundColor: textPrimary,
        dayForegroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? onPrimary : textPrimary),
        dayBackgroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? primary : Colors.transparent),
        todayForegroundColor: WidgetStateProperty.all(primary),
        todayBorder: BorderSide(color: primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        dayStyle: GoogleFonts.poppins(fontSize: 13),
        yearStyle: GoogleFonts.poppins(fontSize: 13),
        weekdayStyle:
        GoogleFonts.poppins(fontSize: 11, color: textSecondary),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: surfaceHigh,
        dialBackgroundColor: surfaceMid,
        dialHandColor: primary,
        dialTextColor: onPrimary,
        hourMinuteColor: surfaceMid,
        hourMinuteTextColor: textPrimary,
        dayPeriodColor: surfaceMid,
        dayPeriodTextColor: textPrimary,
        entryModeIconColor: textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        hourMinuteShape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// Shared UI components, all dark-aware

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppTheme.textSecondary,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  const InfoCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
  });

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
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryBadge extends StatelessWidget {
  final String category;
  const CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        category,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Emoji-tile category picker, styled like the Gemini/Monefy family: a 3x3
/// grid of coloured rounded squares with the emoji sitting on a translucent
/// plate (so it never blends into the tile), label underneath, a ring around
/// the selected tile, and a trailing "+" tile for custom categories.
class CategoryGrid extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const CategoryGrid({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<CategoryGrid> {
  @override
  Widget build(BuildContext context) {
    final categories = [
      ...AppTheme.categoryColors.keys,
      ...CategoryStore.all.map((c) => c.name),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      childAspectRatio: 0.76,
      mainAxisSpacing: 14,
      crossAxisSpacing: 12,
      children: [
        for (final c in categories)
          _CategoryTile(
            category: c,
            emoji: AppTheme.categoryEmoji(c),
            color: AppTheme.categoryColor(c),
            selected: c == widget.selected,
            onTap: () => widget.onChanged(c),
            onLongPress: () => _changeColor(c),
          ),
        _CategoryTile(
          category: 'New',
          emoji: '＋',
          color: AppTheme.surfaceMid,
          selected: false,
          onTap: _addCustom,
          isAddTile: true,
        ),
      ],
    );
  }

  Future<void> _addCustom() async {
    final created = await showDialog<CustomCategory>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (created != null) setState(() {});
  }

  /// Long-press any tile to pick its colour (built-in or custom).
  Future<void> _changeColor(String category) async {
    final color = await showDialog<int>(
      context: context,
      builder: (_) => _ColorPickerDialog(
        title: category,
        initial: AppTheme.categoryColor(category).value,
      ),
    );
    if (color == null) return;
    await CategoryStore.setColor(category, color);
    setState(() {});
  }
}

/// Colour sheet for choosing a category colour: quick swatches, a hue wheel,
/// saturation/brightness sliders, and a hex code field.
class _ColorPickerDialog extends StatefulWidget {
  final String title;
  final int initial;

  const _ColorPickerDialog({required this.title, required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late double _hue; // 0-1
  late double _sat; // 0-1
  late double _val; // 0-1
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(Color(widget.initial));
    _hue = (hsv.hue % 360) / 360;
    _sat = hsv.saturation;
    _val = hsv.value;
    _hexCtrl = TextEditingController(text: _hex);
  }

  Color get _color =>
      HSVColor.fromAHSV(1, _hue * 360, _sat, _val).toColor();

  String get _hex =>
      '#${_color.value.toRadixString(16).substring(2, 8).toUpperCase()}';

  void _applyColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _hue = (hsv.hue % 360) / 360;
      _sat = hsv.saturation;
      _val = hsv.value;
      _hexCtrl.text = _hex;
    });
  }

  void _onHexChanged(String text) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text.trim());
    if (m == null) return;
    _applyColor(Color(int.parse('FF${m.group(1)}', radix: 16)));
  }

  void _onWheelTap(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final outer = size.shortestSide / 2;
    if (dist < outer * 0.55 || dist > outer) return;
    var hue = (atan2(dy, dx) + pi / 2) / (2 * pi);
    if (hue < 0) hue += 1;
    setState(() {
      _hue = hue;
      _hexCtrl.text = _hex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Colour for "${widget.title}"',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTapDown: (d) =>
                    _onWheelTap(d.localPosition, const Size(168, 168)),
                onPanUpdate: (d) =>
                    _onWheelTap(d.localPosition, const Size(168, 168)),
                child: CustomPaint(
                  painter: _HueWheelPainter(hue: _hue),
                  size: const Size(168, 168),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _slider(
              label: 'Saturation',
              value: _sat,
              onChanged: (v) => setState(() {
                _sat = v;
                _hexCtrl.text = _hex;
              }),
            ),
            _slider(
              label: 'Brightness',
              value: _val,
              onChanged: (v) => setState(() {
                _val = v;
                _hexCtrl.text = _hex;
              }),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    onChanged: _onHexChanged,
                    onSubmitted: _onHexChanged,
                    style: TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: '#RRGGBB',
                      hintStyle: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final value in CategoryStore.palette)
                    GestureDetector(
                      onTap: () => _applyColor(Color(value)),
                      child: Container(
                        width: 30,
                        height: 30,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: value == _color.value
                                ? AppTheme.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _color.value),
          child: const Text('Select',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final trackColor =
        HSVColor.fromAHSV(1, _hue * 360, _sat, _val).toColor();
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              activeColor: trackColor,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Donut hue wheel: angle = hue, drawn as a sweep gradient with a punched
/// centre and a knob marking the selection.
class _HueWheelPainter extends CustomPainter {
  final double hue; // 0-1

  _HueWheelPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.62;

    final rect = Rect.fromCircle(center: center, radius: outer);
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, outer, paint);
    canvas.drawCircle(center, inner, Paint()..color = AppTheme.cardBg);

    final angle = hue * 2 * pi - pi / 2;
    final mid = (outer + inner) / 2;
    final knobPos =
        center + Offset(cos(angle) * mid, sin(angle) * mid);
    canvas.drawCircle(knobPos, 11, Paint()..color = Colors.white);
    canvas.drawCircle(
        knobPos,
        8.5,
        Paint()
          ..color = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor());
  }

  @override
  bool shouldRepaint(_HueWheelPainter old) => old.hue != hue;
}

/// Sheet for creating a category: pick a name and an emoji.
class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _nameCtrl = TextEditingController();
  String _emoji = '⭐';
  int? _color; // null → auto-assign from the palette
  String? _error;

  static const List<String> _emojiChoices = [
    '⭐', '🍔', '🍕', '☕', '🍺', '🍿', '🛒', '🚕', '⛽',
    '🏠', '💡', '💧', '📱', '💻', '🎮', '🎬', '🎵', '🎨',
    '👕', '👗', '💊', '🏥', '💪', '✈️', '🏖️', '🎁', '📚',
    '💰', '🏦', '🐶', '🎓', '⚽', '🔧', '💅', '🧾', '📦',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('New category',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              maxLength: 20,
              autofocus: true,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Category name',
                hintStyle: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                counterText: '',
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            Text('Pick an icon',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 168,
              child: GridView.count(
                crossAxisCount: 6,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final e in _emojiChoices)
                    GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: Container(
                        decoration: BoxDecoration(
                          color: e == _emoji
                              ? AppTheme.primary.withOpacity(0.25)
                              : AppTheme.surfaceMid,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: e == _emoji
                                ? AppTheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                            child: Text(e,
                                style: const TextStyle(fontSize: 20))),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Pick a colour',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final value in CategoryStore.palette)
                    GestureDetector(
                      onTap: () => setState(() =>
                          _color = (_color == value ? null : value)),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == value
                                ? AppTheme.textPrimary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
        ),
        TextButton(
          onPressed: () async {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) {
              setState(() => _error = 'Enter a name');
              return;
            }
            final exists = AppTheme.categoryColors.keys.any(
                    (c) => c.toLowerCase() == name.toLowerCase()) ||
                CategoryStore.byName(name) != null;
            if (exists) {
              setState(() => _error = 'Already exists');
              return;
            }
            await CategoryStore.add(name, _emoji, colorValue: _color);
            if (context.mounted) {
              Navigator.pop(context, CategoryStore.byName(name));
            }
          },
          child: const Text('Create',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String category;
  final String emoji;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isAddTile;

  const _CategoryTile({
    required this.category,
    required this.emoji,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.isAddTile = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color:
                      selected ? AppTheme.textPrimary : Colors.transparent,
                  width: 4,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: isAddTile
                    ? Icon(Icons.add,
                        size: 24, color: AppTheme.textPrimary)
                    : Text(emoji, style: const TextStyle(fontSize: 32)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color:
                  selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class TagPill extends StatelessWidget {
  final String label;
  final Color? color;
  const TagPill({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// Dark-styled date + time picker row widget.
/// Returns a tappable row that opens native pickers and calls [onChanged].
class DateTimePicker extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const DateTimePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    // Date
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (ctx, child) => Theme(
        data: AppTheme.theme,
        child: child!,
      ),
    );
    if (date == null || !context.mounted) return;

    // Time
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
      builder: (ctx, child) => Theme(
        data: AppTheme.theme,
        child: child!,
      ),
    );
    if (time == null) return;

    onChanged(DateTime(
        date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(value);
    final dateStr = isToday
        ? 'Today'
        : '${value.day} ${_month(value.month)} ${value.year}';
    final timeStr =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () => _pick(context),
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$dateStr  $timeStr',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
  }

  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}