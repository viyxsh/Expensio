/// Data types for "Ask Expensio" — the natural-language layer over the app.
///
/// One Gemini-backed tool-calling flow per message produces an [AskReply]:
/// either an [AskExpenseAction] (validated in the app, then a confirm card
/// writes via the normal repository path) or a renderable [AskComponent]
/// from a small catalog.
library;

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

String _str(dynamic v) => (v ?? '').toString();

/// The model sometimes writes markdown (**bold**, *italic*, `code`, ##
/// headers) even when asked not to. The app renders plain text only, so
/// strip the markers and keep the inner words.
String stripMarkdown(String raw) {
  var t = raw.trim();
  t = t.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
  t = t.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!);
  t = t.replaceAllMapped(
      RegExp(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])'), (m) => m.group(1)!);
  t = t.replaceAllMapped(
      RegExp(r'(?<!\w)_([^_\n]+)_(?!\w)'), (m) => m.group(1)!);
  t = t.replaceAll('`', '');
  t = t.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  return t.trim();
}

/// A single per-person amount from a custom-split instruction.
class AskCustomAmount {
  final String name;
  final double amount;

  const AskCustomAmount({required this.name, required this.amount});

  factory AskCustomAmount.fromJson(Map<String, dynamic> j) => AskCustomAmount(
        name: _str(j['name']),
        amount: _num(j['amount']),
      );
}

/// An expense-creation intent extracted from natural language. Names are
/// unresolved at this point — the app matches them against real members and
/// shows a confirm card before anything is written.
class AskExpenseAction {
  final String title;
  final double amount; // major units, in the app's reporting currency
  final String category;
  final String payerName; // 'me' or a person name
  final List<String> participants; // names; 'me' allowed; payer included
  final String split; // 'equal' | 'custom'
  final List<AskCustomAmount> customAmounts;
  final DateTime? date; // null → the app defaults to now
  final String groupName; // '' when the user didn't name a group
  final String note;

  const AskExpenseAction({
    required this.title,
    required this.amount,
    required this.category,
    required this.payerName,
    required this.participants,
    required this.split,
    this.customAmounts = const [],
    this.date,
    this.groupName = '',
    this.note = '',
  });

  factory AskExpenseAction.fromJson(Map<String, dynamic> j) {
    final dateRaw = _str(j['date']).trim();
    return AskExpenseAction(
      title: _str(j['title']).trim(),
      amount: _num(j['amount']),
      category: _str(j['category']).trim(),
      payerName: _str(j['payer']).trim(),
      participants: (j['participants'] as List<dynamic>? ?? const [])
          .map(_str)
          .where((s) => s.trim().isNotEmpty)
          .map((s) => s.trim())
          .toList(),
      split: _str(j['split']).trim().toLowerCase() == 'custom'
          ? 'custom'
          : 'equal',
      customAmounts: (j['custom_amounts'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AskCustomAmount.fromJson)
          .toList(),
      date: dateRaw.isEmpty ? null : DateTime.tryParse(dateRaw),
      groupName: _str(j['group_name']).trim(),
      note: _str(j['note']).trim(),
    );
  }
}

/// The catalog of components the query flow can render.
enum AskComponentType { statTile, barChart, donut, transactionList, settleUpCard, text }

AskComponentType _componentType(String s) {
  switch (s.trim().toLowerCase()) {
    case 'bar_chart':
      return AskComponentType.barChart;
    case 'donut':
      return AskComponentType.donut;
    case 'transaction_list':
      return AskComponentType.transactionList;
    case 'settle_up_card':
      return AskComponentType.settleUpCard;
    case 'stat_tile':
      return AskComponentType.statTile;
    default:
      return AskComponentType.text;
  }
}

String _typeName(AskComponentType t) => switch (t) {
      AskComponentType.barChart => 'bar_chart',
      AskComponentType.donut => 'donut',
      AskComponentType.transactionList => 'transaction_list',
      AskComponentType.settleUpCard => 'settle_up_card',
      AskComponentType.statTile => 'stat_tile',
      AskComponentType.text => 'text',
    };

/// What Ask produced for one user message: either a confirmable expense
/// action or a list of rendered components (a multi-part question yields
/// several, shown stacked in one bubble).
class AskReply {
  final AskExpenseAction? action;
  final List<AskComponent> components;

  const AskReply.action(AskExpenseAction this.action)
      : components = const [];
  const AskReply.components(this.components) : action = null;
}

/// One labelled number in a stat-tile component. [value] is display-ready
/// (the model formats it with the currency symbol).
class AskStat {
  final String label;
  final String value;
  final String sublabel;

  const AskStat({required this.label, required this.value, this.sublabel = ''});

  factory AskStat.fromJson(Map<String, dynamic> j) => AskStat(
        label: _str(j['label']),
        value: _str(j['value']),
        sublabel: _str(j['sublabel']),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (sublabel.isNotEmpty) 'sublabel': sublabel,
      };
}

/// One bar of a bar-chart component. [value] must be numeric for fl_chart.
class AskBar {
  final String label;
  final double value;

  const AskBar({required this.label, required this.value});

  factory AskBar.fromJson(Map<String, dynamic> j) =>
      AskBar(label: _str(j['label']), value: _num(j['value']));

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// One slice of a donut component. [value] must be numeric for fl_chart.
class AskSlice {
  final String label;
  final double value;

  const AskSlice({required this.label, required this.value});

  factory AskSlice.fromJson(Map<String, dynamic> j) =>
      AskSlice(label: _str(j['label']), value: _num(j['value']));

  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

/// One row of a transaction-list component.
class AskTransactionRow {
  final String title;
  final String date;
  final String amount; // display-ready
  final String sublabel; // e.g. category · payer

  const AskTransactionRow({
    required this.title,
    required this.amount,
    this.date = '',
    this.sublabel = '',
  });

  factory AskTransactionRow.fromJson(Map<String, dynamic> j) =>
      AskTransactionRow(
        title: _str(j['title']),
        date: _str(j['date']),
        amount: _str(j['amount']),
        sublabel: _str(j['sublabel']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'amount': amount,
        if (date.isNotEmpty) 'date': date,
        if (sublabel.isNotEmpty) 'sublabel': sublabel,
      };
}

/// One "A pays B" line of a settle-up-card component.
class AskTransfer {
  final String from;
  final String to;
  final String amount; // display-ready

  const AskTransfer({required this.from, required this.to, required this.amount});

  factory AskTransfer.fromJson(Map<String, dynamic> j) => AskTransfer(
        from: _str(j['from']),
        to: _str(j['to']),
        amount: _str(j['amount']),
      );

  Map<String, dynamic> toJson() =>
      {'from': from, 'to': to, 'amount': amount};
}

/// A renderable answer: exactly one component from the catalog plus a caption.
class AskComponent {
  final AskComponentType type;
  final String caption;
  final List<AskStat> stats;
  final List<AskBar> bars;
  final List<AskSlice> slices;
  final List<AskTransactionRow> transactions;
  final List<AskTransfer> transfers;
  final String body;

  const AskComponent({
    required this.type,
    this.caption = '',
    this.stats = const [],
    this.bars = const [],
    this.slices = const [],
    this.transactions = const [],
    this.transfers = const [],
    this.body = '',
  });

  factory AskComponent.fromJson(Map<String, dynamic> j) => AskComponent(
        type: _componentType(_str(j['component'])),
        caption: _str(j['caption']),
        stats: (j['stats'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskStat.fromJson)
            .toList(),
        bars: (j['bars'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskBar.fromJson)
            .toList(),
        slices: (j['slices'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskSlice.fromJson)
            .toList(),
        transactions: (j['transactions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskTransactionRow.fromJson)
            .toList(),
        transfers: (j['transfers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskTransfer.fromJson)
            .toList(),
        body: _str(j['body']),
      );

  Map<String, dynamic> toJson() => {
        'component': _typeName(type),
        if (caption.isNotEmpty) 'caption': caption,
        if (stats.isNotEmpty) 'stats': [for (final s in stats) s.toJson()],
        if (bars.isNotEmpty) 'bars': [for (final b in bars) b.toJson()],
        if (slices.isNotEmpty)
          'slices': [for (final s in slices) s.toJson()],
        if (transactions.isNotEmpty)
          'transactions': [for (final t in transactions) t.toJson()],
        if (transfers.isNotEmpty)
          'transfers': [for (final t in transfers) t.toJson()],
        if (body.isNotEmpty) 'body': body,
      };
}
