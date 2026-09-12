import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/ask_models.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/app_settings.dart';
import '../services/ask_chat_store.dart';
import '../services/ask_service.dart';
import '../services/category_store.dart';
import '../services/ask_tools.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

/// "Ask Expensio" — a natural-language layer over the app.
///
/// Two Gemini-backed flows, both validated locally before anything is written:
///  - Action flow: "paid 1,240 for dinner with Rahul and Priya, split equally"
///    → a confirm card → the normal repository write.
///  - Query flow: the model calls data tools (backed by the repository) and
///    answers with one renderable component from a small catalog.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

enum _Kind { user, component, action, error }

/// One entry in the conversation. Action-card state (group choice, status)
/// is mutable and lives here; the rest is immutable content.
class _Msg {
  final _Kind kind;
  final String text;
  final List<AskComponent> components;
  final AskExpenseAction? action;

  /// Action-card state: null = not chosen, '' = personal, otherwise group id.
  String? selectedGroupId;

  /// 0 pending, 1 added, 2 dismissed.
  int status = 0;

  _Msg.user(this.text)
      : kind = _Kind.user,
        components = const [],
        action = null;
  _Msg.components(this.components)
      : kind = _Kind.component,
        text = '',
        action = null;
  _Msg.action(this.action)
      : kind = _Kind.action,
        text = '',
        components = const [];
  _Msg.error(this.text)
      : kind = _Kind.error,
        components = const [],
        action = null;
}

/// A fully-validated action, ready to confirm. Rebuilt from current app state
/// every time the card renders, so warnings stay accurate as data changes.
class _Resolution {
  final String title;
  final int totalCents;
  final String category;
  final DateTime date;
  final bool personal;
  final String payerId;

  /// Parsed names that matched no existing member; they'll be added as new
  /// placeholder members on confirm.
  final List<String> pendingNames;

  final List<String> errors;
  final List<String> infos;

  _Resolution({
    required this.title,
    required this.totalCents,
    required this.category,
    required this.date,
    required this.personal,
    required this.payerId,
    required this.pendingNames,
    required this.errors,
    required this.infos,
  });

  bool get canConfirm => personal || (errors.isEmpty && totalCents > 0);
}

class _AskScreenState extends State<AskScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _uuid = const Uuid();
  bool _busy = false;
  final List<_Msg> _msgs = [];

  /// Active chat session (null = fresh unsaved chat, like Gemini's new chat).
  String? _chatId;

  static const _suggestions = [
    'How much did I spend this month?',
    'Food spend: this month vs last',
    'Who owes me money?',
    'Add 320 for petrol',
    'Paid 1240 for dinner with Rahul and Priya, split equally',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _msgs.add(_Msg.user(text));
      _busy = true;
      _inputCtrl.clear();
    });
    _scrollBottom();

    // Start (or continue) the persisted chat session.
    if (_chatId == null) {
      final id = _uuid.v4();
      _chatId = id;
      await AskChatStore.createChat(id, text);
      if (mounted) setState(() {});
    } else {
      await _persist();
    }

    try {
      final reply = await AskService.answer(
        text,
        executor: AskTools.execute,
      );
      if (!mounted) return;
      if (reply.action != null) {
        setState(() => _msgs.add(_Msg.action(reply.action!)));
      } else {
        setState(() => _msgs.add(_Msg.components(reply.components)));
        await _persist();
      }
    } catch (e) {
      if (mounted) setState(() => _msgs.add(_Msg.error(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollBottom();
    }
  }

  // ------------------------------------------------------- chat sessions

  /// Rewrites the persisted message list from the current conversation
  /// (user texts + component payloads only).
  Future<void> _persist() async {
    final id = _chatId;
    if (id == null) return;
    final entries = <Map<String, dynamic>>[];
    for (final m in _msgs) {
      if (m.kind == _Kind.user) {
        entries.add({'kind': 'user', 'text': m.text});
      } else if (m.kind == _Kind.component) {
        entries.add({
          'kind': 'components',
          'components': [for (final c in m.components) c.toJson()],
        });
      }
    }
    await AskChatStore.saveMessages(id, entries);
  }

  /// Gemini-style "new chat": blank canvas; the previous chat stays saved.
  void _newChat() {
    if (_busy) return;
    setState(() {
      _chatId = null;
      _msgs.clear();
    });
    _closeDrawerIfOpen();
  }

  Future<void> _openChat(String id) async {
    if (_busy || _chatId == id) {
      _closeDrawerIfOpen();
      return;
    }
    final restored = _msgsFromJson(AskChatStore.messagesOf(id));
    setState(() {
      _chatId = id;
      _msgs
        ..clear()
        ..addAll(restored);
    });
    _closeDrawerIfOpen();
    _scrollBottom();
    await AskChatStore.touch(id);
  }

  Future<void> _deleteChat(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: Text('Delete this chat?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        content: Text('This conversation will be permanently removed.',
            style: TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AskChatStore.deleteChat(id);
    if (!mounted) return;
    setState(() {
      if (_chatId == id) {
        _chatId = null;
        _msgs.clear();
      }
    });
  }

  void _closeDrawerIfOpen() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
  }

  /// Rebuilds chat messages from their persisted JSON form. Action cards and
  /// errors are transient by design and simply won't appear.
  List<_Msg> _msgsFromJson(List<Map<String, dynamic>> entries) {
    final out = <_Msg>[];
    for (final e in entries) {
      final kind = (e['kind'] ?? '').toString();
      if (kind == 'user') {
        final t = (e['text'] ?? '').toString();
        if (t.isNotEmpty) out.add(_Msg.user(t));
      } else if (kind == 'components') {
        final comps = (e['components'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AskComponent.fromJson)
            .toList();
        if (comps.isNotEmpty) out.add(_Msg.components(comps));
      }
    }
    return out;
  }

  String _relTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat('d MMM').format(t);
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('missing_api_key')) {
      return 'Add your Gemini API key to .env (GEMINI_API_KEY) to use Ask '
          'Expensio.';
    }
    if (s.contains('quota_exceeded')) {
      return 'Ask is at its usage limit right now. Please try again later.';
    }
    if (s.contains('auth_error')) {
      return 'Gemini rejected the API key. Check GEMINI_API_KEY in .env.';
    }
    if (s.contains('model_not_found')) {
      return 'Gemini model unavailable — check your API key has access to it.';
    }
    if (s.contains('bad_request')) {
      return 'Gemini could not process that. Try rephrasing.';
    }
    if (s.contains('too_many_tool_rounds')) {
      return 'That question needs too many lookups. Try narrowing it down.';
    }
    if (s.contains('empty_response') || s.contains('parse_error')) {
      return 'Gemini returned something unexpected. Try again.';
    }
    return 'Something went wrong talking to Gemini. Check your connection '
        'and try again.';
  }

  // ------------------------------------------------------ action resolution

  /// Match a person mention ('me' allowed) to a user id within [pool].
  String? _matchPerson(String raw, List<UserModel> pool) {
    final selfId = Services.currentUserId;
    final selfName =
        Services.state.getUserById(selfId)?.name ?? 'You';
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    if (q == 'me' || q == selfName.toLowerCase()) return selfId;
    for (final u in pool) {
      if (u.name.trim().toLowerCase() == q) return u.id;
    }
    return null;
  }

  bool _isSelf(String raw) {
    final selfName =
        Services.state.getUserById(Services.currentUserId)?.name ?? 'You';
    final q = raw.trim().toLowerCase();
    return q.isEmpty || q == 'me' || q == selfName.toLowerCase();
  }

  /// True when the action involves nobody but the user (payer is them and no
  /// other participants) — the default case for a personal expense.
  bool _onlySelf(AskExpenseAction a) {
    if (!_isSelf(a.payerName)) return false;
    for (final p in a.participants) {
      if (p.trim().isNotEmpty && !_isSelf(p)) return false;
    }
    return true;
  }

  /// The group this action should land in: the user's explicit chip choice
  /// wins; otherwise a unique group-name hint match; otherwise null (needs a
  /// choice) — or '' (personal) when only the user is involved.
  String? _effectiveGroupId(AskExpenseAction a, _Msg msg) {
    if (msg.selectedGroupId != null) return msg.selectedGroupId;
    final candidates = _groupCandidates(a);
    if (a.groupName.isNotEmpty && candidates.length == 1) {
      return candidates.first.id;
    }
    if (_onlySelf(a)) return '';
    return null;
  }

  List<GroupModel> _groupCandidates(AskExpenseAction a) {
    final groups = Services.state.getAllGroups();
    final hint = a.groupName.trim();
    if (hint.isEmpty) return groups;
    return groups
        .where((g) => g.name.toLowerCase().contains(hint.toLowerCase()))
        .toList();
  }

  /// Resolve an action against current app state. Never throws — problems
  /// come back as errors (blocking confirm) or infos (shown as notes).
  _Resolution _resolveAction(AskExpenseAction a, _Msg msg) {
    final state = Services.state;
    final errors = <String>[];
    final infos = <String>[];
    final pendingNames = <String>[];

    final totalCents = Money.fromMajor(a.amount);
    if (totalCents <= 0) errors.add('Amount must be greater than zero');

    var category = a.category.isEmpty ? 'General' : a.category;
    if (!AppTheme.categoryColors.containsKey(category) &&
        CategoryStore.byName(category) == null) {
      infos.add(
          '"${a.category}" is not an app category — using General instead');
      category = 'General';
    }

    final now = DateTime.now();
    final date = a.date ?? DateTime(now.year, now.month, now.day, 12);

    final groupId = _effectiveGroupId(a, msg);
    final personal = groupId != null && groupId.isEmpty;

    if (groupId == null) {
      errors.add(
          'Choose a group for this shared expense, or pick Personal');
    }

    final group =
        (groupId == null || groupId.isEmpty) ? null : state.getGroupById(groupId);
    if (groupId != null && groupId.isNotEmpty && group == null) {
      errors.add('That group no longer exists');
    }

    final pool =
        group != null ? state.membersOf(group) : state.getAllUsers();

    if (!personal && groupId != null && !_onlySelf(a)) {
      // Shared expense — resolve every mentioned person.
      final mentioned = List<String>.from(a.participants);
      final payerRaw = a.payerName.isEmpty ? 'me' : a.payerName;
      if (!mentioned
          .any((p) => p.trim().toLowerCase() == payerRaw.trim().toLowerCase())) {
        mentioned.insert(0, payerRaw);
      }
      for (final p in mentioned) {
        if (_matchPerson(p, pool) == null && !pendingNames.contains(p.trim())) {
          pendingNames.add(p.trim());
        }
      }

      // Custom splits: validate amounts now so the user sees problems.
      if (a.split == 'custom' && a.customAmounts.isNotEmpty) {
        final knownSum = a.customAmounts
            .where((ca) => _matchPerson(ca.name, pool) != null)
            .fold(0, (s, ca) => s + Money.fromMajor(ca.amount));
        final payerIsNamed = a.customAmounts
            .any((ca) => _matchPerson(ca.name, pool) == _matchPerson(payerRaw, pool) &&
                _matchPerson(payerRaw, pool) != null);
        if (!payerIsNamed && knownSum > totalCents) {
          errors.add('Custom amounts add up to more than the total');
        }
      }
    }

    final payerId = personal
        ? 'personal'
        : _matchPerson(a.payerName.isEmpty ? 'me' : a.payerName, pool) ??
            Services.currentUserId;

    return _Resolution(
      title: a.title.isEmpty ? 'Expense' : a.title,
      totalCents: totalCents,
      category: category,
      date: date,
      personal: personal,
      payerId: payerId,
      pendingNames: pendingNames,
      errors: errors,
      infos: infos,
    );
  }

  /// Write the confirmed expense through the normal repository path,
  /// creating placeholder members for names nobody matched.
  Future<void> _confirmAction(_Msg msg) async {
    final a = msg.action!;
    final r = _resolveAction(a, msg);
    if (!r.canConfirm) return;

    try {
      if (r.personal) {
        await Services.state.saveExpense(ExpenseModel(
          id: _uuid.v4(),
          title: r.title,
          totalAmount: r.totalCents,
          payerId: 'personal',
          participantIds: const [],
          groupId: 'personal',
          createdAt: r.date,
          category: r.category,
          isPersonal: true,
          currencyCode: AppSettings.currencyCode,
        ));
      } else {
        final groupId = _effectiveGroupId(a, msg)!;
        final group = Services.state.getGroupById(groupId)!;

        // Create placeholder members for unknown names, then re-resolve
        // everyone against members + new placeholders.
        final newIds = <String, String>{};
        final memberIds = List<String>.from(group.memberIds);
        for (final name in r.pendingNames) {
          final user = UserModel(
              id: _uuid.v4(), name: name, isPlaceholder: true);
          await Services.state.saveUser(user);
          newIds[name.toLowerCase()] = user.id;
          if (!memberIds.contains(user.id)) memberIds.add(user.id);
        }

        String resolve(String raw) {
          final id = _matchPerson(raw, Services.state.getAllUsers());
          if (id != null) return id;
          final pendingId = newIds[raw.trim().toLowerCase()];
          if (pendingId != null) return pendingId;
          return Services.currentUserId;
        }

        final payerRaw = a.payerName.isEmpty ? 'me' : a.payerName;
        final payerId = resolve(payerRaw);

        final participantIds = <String>[];
        void addParticipant(String raw) {
          final id = resolve(raw);
          if (!participantIds.contains(id)) participantIds.add(id);
        }

        for (final p in a.participants) {
          addParticipant(p);
        }
        addParticipant(payerRaw);

        // Split over the final id set, snapped to the exact total so
        // balances always reconcile (same rule as the manual add screen).
        Map<String, int> splitMap;
        if (a.split == 'custom' && a.customAmounts.isNotEmpty) {
          splitMap = {};
          for (final ca in a.customAmounts) {
            final id = resolve(ca.name);
            splitMap[id] = (splitMap[id] ?? 0) + Money.fromMajor(ca.amount);
          }
          if (!splitMap.containsKey(payerId)) {
            final rest = splitMap.values.fold<int>(0, (s, v) => s + v);
            splitMap[payerId] = r.totalCents - rest;
          }
          final sum = splitMap.values.fold<int>(0, (s, v) => s + v);
          final drift = r.totalCents - sum;
          if (drift != 0 && splitMap.isNotEmpty) {
            final first = splitMap.keys.first;
            splitMap[first] = splitMap[first]! + drift;
          }
        } else {
          final shares =
              Money.splitEqual(r.totalCents, participantIds.length);
          splitMap = {
            for (var i = 0; i < participantIds.length; i++)
              participantIds[i]: shares[i],
          };
        }

        if (memberIds.length != group.memberIds.length) {
          await Services.state.saveGroup(GroupModel(
            id: group.id,
            name: group.name,
            memberIds: memberIds,
            createdAt: group.createdAt,
            description: group.description,
          ));
        }

        await Services.state.saveExpense(ExpenseModel(
          id: _uuid.v4(),
          title: r.title,
          totalAmount: r.totalCents,
          payerId: payerId,
          participantIds: participantIds,
          groupId: group.id,
          createdAt: r.date,
          category: r.category,
          isPersonal: false,
          splitMap: splitMap,
          createdBy: Services.currentUserId,
          currencyCode: AppSettings.currencyCode,
        ));
      }

      if (!mounted) return;
      setState(() => msg.status = 1);
      _scrollBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_Msg.error(_friendly(e))));
      _scrollBottom();
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      drawer: _chatDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _msgs.isEmpty && !_busy
                  ? _emptyState()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _msgs.length + (_busy ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _msgs.length) return _thinking();
                        return _buildMsg(_msgs[i]);
                      },
                    ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          // Drawer handle (chat history), like the Gemini app.
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, color: AppTheme.textSecondary),
              tooltip: 'Chat history',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Icon(Icons.auto_awesome, size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ask Expensio',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                Text('Ask about your money, or just type an expense',
                    style: TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined,
                color: AppTheme.textSecondary),
            tooltip: 'New chat',
            onPressed: _newChat,
          ),
        ],
      ),
    );
  }

  /// Gemini-style history panel: new chat on top, recent chats below.
  Widget _chatDrawer() {
    final chats = AskChatStore.listChats();
    return Drawer(
      backgroundColor: AppTheme.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: AppTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: Icon(Icons.add, size: 20, color: AppTheme.primary),
                  label: Text('New chat',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  onPressed: _newChat,
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 4),
              child: Text('RECENT',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary)),
            ),
            Expanded(
              child: chats.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No saved chats yet',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                    )
                  : ListView.builder(
                      itemCount: chats.length,
                      itemBuilder: (ctx, i) {
                        final chat = chats[i];
                        final id = (chat['id'] ?? '').toString();
                        final title = (chat['title'] ?? 'Untitled').toString();
                        final time =
                            _relTime((chat['updatedAt'] ?? '').toString());
                        final selected = id == _chatId;
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 16, right: 4),
                          leading: Icon(
                            Icons.chat_bubble_outline,
                            size: 18,
                            color: selected
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                          title: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary)),
                          subtitle: time.isEmpty
                              ? null
                              : Text(time,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary)),
                          selected: selected,
                          selectedTileColor:
                              AppTheme.primary.withOpacity(0.08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          onTap: () => _openChat(id),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 19, color: AppTheme.textSecondary),
                            tooltip: 'Delete chat',
                            onPressed: () => _deleteChat(id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_outlined,
                  size: 30, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            Text('What do you want to know?',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text('Or type an expense and I\'ll fill in the details',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final s in _suggestions)
                  ActionChip(
                    label: Text(s,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                    side: BorderSide(color: AppTheme.divider),
                    onPressed: () => _send(s),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _thinking() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Thinking…',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildMsg(_Msg msg) {
    switch (msg.kind) {
      case _Kind.user:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(top: 10, left: 48),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(4),
                bottomLeft: Radius.circular(16),
              ),
            ),
            child: Text(msg.text,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: AppTheme.onPrimary)),
          ),
        );
      case _Kind.component:
        return _assistantCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < msg.components.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _componentBody(msg.components[i]),
              ],
            ],
          ),
        );
      case _Kind.error:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(top: 10, right: 48),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border:
                  Border.all(color: AppTheme.errorColor.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: AppTheme.errorColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(msg.text,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppTheme.textPrimary)),
                ),
              ],
            ),
          ),
        );
      case _Kind.action:
        return _assistantCard(child: _actionCard(msg));
    }
  }

  Widget _assistantCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: AppTheme.divider),
      ),
      child: child,
    );
  }

  Widget _inputBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bg,
        border: Border(top: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style:
                  TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Ask anything, or type an expense…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                filled: true,
                fillColor: AppTheme.surfaceMid,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_inputCtrl.text),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_upward,
                  size: 20, color: AppTheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ action card

  Widget _actionCard(_Msg msg) {
    final a = msg.action!;
    final r = _resolveAction(a, msg);
    final added = msg.status == 1;
    final dismissed = msg.status == 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text('NEW EXPENSE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        Text(r.title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 2),
        Text(Money.withSymbol(r.totalCents),
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CategoryBadge(category: r.category),
            TagPill(label: DateFormat('d MMM, h:mm a').format(r.date)),
            TagPill(label: a.split == 'custom' ? 'Custom split' : 'Equal split'),
          ],
        ),
        const SizedBox(height: 12),
        if (!r.personal) ...[
          _metaRow('Paid by', _payerLabel(a, msg)),
          const SizedBox(height: 6),
          _metaRow('Group', _groupLabel(a, msg)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: _personChips(a, msg)),
          const SizedBox(height: 12),
        ],
        for (final info in r.infos)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 13, color: AppTheme.warningColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(info,
                      style: TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ),
        for (final err in r.errors)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 13, color: AppTheme.errorColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(err,
                      style: TextStyle(
                          fontSize: 11.5, color: AppTheme.errorColor)),
                ),
              ],
            ),
          ),
        if (!r.personal && _effectiveGroupId(a, msg) == null) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _groupChoice(msg, '', 'Personal'),
              for (final g in _groupCandidates(a))
                _groupChoice(msg, g.id, g.name),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (added)
          Row(
            children: [
              Icon(Icons.check_circle,
                  size: 16, color: AppTheme.successColor),
              const SizedBox(width: 6),
              Text('Added to your expenses',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.successColor)),
            ],
          )
        else if (dismissed)
          Text('Dismissed',
              style:
                  TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => msg.status = 2),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: r.canConfirm ? () => _confirmAction(msg) : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Add expense'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _groupChoice(_Msg msg, String id, String label) {
    return ActionChip(
      label: Text(label),
      side: BorderSide(color: AppTheme.divider),
      onPressed: () => setState(() => msg.selectedGroupId = id),
    );
  }

  String _groupLabel(AskExpenseAction a, _Msg msg) {
    final id = _effectiveGroupId(a, msg);
    if (id == null) return 'Pick below';
    if (id.isEmpty) return 'Personal';
    return Services.state.getGroupById(id)?.name ?? 'Unknown';
  }

  String _payerLabel(AskExpenseAction a, _Msg msg) {
    if (_isSelf(a.payerName)) {
      return Services.state
              .getUserById(Services.currentUserId)
              ?.name ??
          'You';
    }
    final groupId = _effectiveGroupId(a, msg);
    final group = (groupId == null || groupId.isEmpty)
        ? null
        : Services.state.getGroupById(groupId);
    final pool =
        group != null ? Services.state.membersOf(group) : Services.state.getAllUsers();
    final id = _matchPerson(a.payerName, pool);
    if (id != null) return Services.state.getUserById(id)?.name ?? a.payerName;
    return '${a.payerName} (new member)';
  }

  List<Widget> _personChips(AskExpenseAction a, _Msg msg) {
    final groupId = _effectiveGroupId(a, msg);
    final group = (groupId == null || groupId.isEmpty)
        ? null
        : Services.state.getGroupById(groupId);
    final pool =
        group != null ? Services.state.membersOf(group) : Services.state.getAllUsers();

    final known = <String>[];
    final pending = <String>[];

    void add(String raw) {
      final id = _matchPerson(raw, pool);
      if (id != null) {
        final name = Services.state.getUserById(id)?.name ?? raw;
        if (!known.contains(name)) known.add(name);
      } else if (raw.trim().isNotEmpty && !pending.contains(raw.trim())) {
        pending.add(raw.trim());
      }
    }

    for (final p in a.participants) {
      add(p);
    }
    final payerRaw = a.payerName.isEmpty ? 'me' : a.payerName;
    if (!a.participants
        .any((p) => p.trim().toLowerCase() == payerRaw.trim().toLowerCase())) {
      add(payerRaw);
    }

    return [
      for (final n in known)
        TagPill(
            label: n,
            color:
                _matchPerson(n, pool) == Services.currentUserId
                    ? AppTheme.primary
                    : null),
      for (final n in pending)
        TagPill(label: '$n · new member', color: AppTheme.successColor),
    ];
  }

  Widget _metaRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
        ),
      ],
    );
  }

  // --------------------------------------------------- component rendering

  Widget _componentBody(AskComponent c) {
    switch (c.type) {
      case AskComponentType.statTile:
        return _statTile(c);
      case AskComponentType.barChart:
        return _barChart(c);
      case AskComponentType.donut:
        return _donut(c);
      case AskComponentType.transactionList:
        return _transactionList(c);
      case AskComponentType.settleUpCard:
        return _settleUp(c);
      case AskComponentType.text:
        return SelectableText(
          stripMarkdown(c.body.isEmpty ? c.caption : c.body),
          style: TextStyle(
              fontSize: 13.5, height: 1.45, color: AppTheme.textPrimary),
        );
    }
  }

  Widget _caption(String caption) {
    final clean = stripMarkdown(caption);
    if (clean.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(clean,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
    );
  }

  Widget _statTile(AskComponent c) {
    Widget tile(AskStat s, {bool fullWidth = false}) {
      return Container(
        width: fullWidth ? double.infinity : 148,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMid,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.label,
                style:
                    TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(s.value,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
            ),
            if (s.sublabel.isNotEmpty)
              Text(s.sublabel,
                  style: TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(c.caption),
        if (c.stats.length == 1)
          tile(c.stats.first, fullWidth: true)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final s in c.stats) tile(s)],
          ),
      ],
    );
  }

  Widget _barChart(AskComponent c) {
    final bars = c.bars;
    if (bars.isEmpty) return _caption(c.caption);
    final maxVal = bars.map((b) => b.value).reduce((a, b) => a > b ? a : b);
    final width =
        bars.length > 8 ? 8.0 : bars.length > 5 ? 12.0 : 18.0;
    final backY = maxVal <= 0 ? 1.0 : maxVal * 1.25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(c.caption),
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              maxY: backY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVal <= 0 ? 1 : maxVal / 3,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: AppTheme.divider,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= bars.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _short(bars[i].label),
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    reservedSize: 26,
                  ),
                ),
              ),
              barGroups: bars.asMap().entries.map((e) {
                final hasData = e.value.value > 0;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value,
                      color: hasData ? AppTheme.primary : AppTheme.divider,
                      width: width,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                      backDrawRodData: BackgroundBarChartRodData(
                        show: true,
                        toY: backY,
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
                    final label = groupIndex >= 0 && groupIndex < bars.length
                        ? bars[groupIndex].label
                        : '';
                    return BarTooltipItem(
                      '$label  ${AppSettings.currencySymbol} ${rod.toY.toStringAsFixed(0)}',
                      TextStyle(
                        color: AppTheme.onPrimary,
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
    );
  }

  Widget _donut(AskComponent c) {
    final slices = c.slices;
    if (slices.isEmpty) return _caption(c.caption);
    final total = slices.map((s) => s.value).fold(0.0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(c.caption),
        Row(
          children: [
            SizedBox(
              height: 120,
              width: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 32,
                      sections: slices.asMap().entries.map((e) {
                        return PieChartSectionData(
                          color: _sliceColor(e.key, e.value.label),
                          value: e.value.value <= 0 ? 0.001 : e.value.value,
                          radius: 26,
                          title: '',
                        );
                      }).toList(),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${AppSettings.currencySymbol} ${_compact(total)}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('total',
                          style: TextStyle(
                              fontSize: 9, color: AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in slices.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color:
                                  _sliceColor(slices.indexOf(s), s.label),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(s.label,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(
                            '${AppSettings.currencySymbol} ${_compact(s.value)}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _transactionList(AskComponent c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(c.caption),
        if (c.transactions.isEmpty)
          Text('No matching transactions',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary))
        else
          for (final t in c.transactions)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom:
                      BorderSide(color: AppTheme.divider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  _avatar(t.title),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (t.sublabel.isNotEmpty || t.date.isNotEmpty)
                          Text(
                            [
                              if (t.date.isNotEmpty) t.date,
                              if (t.sublabel.isNotEmpty) t.sublabel,
                            ].join('  ·  '),
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(t.amount,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                ],
              ),
            ),
      ],
    );
  }

  Widget _settleUp(AskComponent c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(c.caption),
        if (c.transfers.isEmpty)
          Text('Everyone is settled up',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary))
        else ...[
          for (final t in c.transfers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(t.from),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(t.from,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward,
                              size: 13, color: AppTheme.textSecondary),
                        ),
                        Flexible(
                          child: Text(t.to,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  Text(t.amount,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('The fewest transfers needed to clear all debts',
                style: TextStyle(
                    fontSize: 10.5, color: AppTheme.textSecondary)),
          ),
        ],
      ],
    );
  }

  // --------------------------------------------------------------- helpers

  static const _fallbackChartColors = [
    Color(0xFFE97856),
    Color(0xFF3FAE72),
    Color(0xFF6C63A8),
    Color(0xFF3B8EA5),
    Color(0xFFD89B3D),
    Color(0xFFC75C7A),
    Color(0xFF4FA89A),
    Color(0xFF5969A8),
  ];

  Color _sliceColor(int index, String label) {
    if (AppTheme.categoryColors.containsKey(label) ||
        CategoryStore.byName(label) != null) {
      return AppTheme.categoryColor(label);
    }
    return _fallbackChartColors[index % _fallbackChartColors.length];
  }

  Widget _avatar(String name) {
    final letter =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceMid,
        shape: BoxShape.circle,
      ),
      child: Text(letter,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary)),
    );
  }

  String _short(String s) => s.length > 8 ? '${s.substring(0, 7)}…' : s;

  String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}
