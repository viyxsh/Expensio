import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/group_model.dart';
import '../models/settlement_model.dart';
import '../services/services.dart';
import '../services/settlement_service.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';

class SettlementScreen extends StatefulWidget {
  final GroupModel group;
  const SettlementScreen({super.key, required this.group});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  final _uuid = const Uuid();

  GroupModel get group => widget.group;

  @override
  void initState() {
    super.initState();
    Services.state.addListener(_onState);
  }

  @override
  void dispose() {
    Services.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  // A placeholder (dummy) member has no real account to confirm a payment.
  bool _isPlaceholder(String id) =>
      Services.state.getUserById(id)?.isPlaceholder ?? false;

  /// Display name for any id, including someone removed from the group who is
  /// still referenced by past expenses. Never surface a raw uuid.
  String _nameFor(String id) {
    final n = Services.state.getUserById(id)?.name.trim() ?? '';
    return n.isEmpty ? 'Former member' : n;
  }

  /// A real account other than me must confirm; placeholders / my own slot are
  /// recorded straight away.
  bool _needsConfirmation(String toId) =>
      !_isPlaceholder(toId) && toId != Services.currentUserId;

  /// Who may confirm a pending payment: the payee, or whoever manages a
  /// placeholder payee.
  bool _canConfirm(SettlementModel s) =>
      s.toId == Services.currentUserId || _isPlaceholder(s.toId);

  Future<void> _recordPayment(Settlement s) async {
    final pending = _needsConfirmation(s.toId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text(
            'Record ${s.fromName} → ${s.toName} of ${Money.withSymbol(s.amount)}?'
            '${pending ? '\n\n${s.toName} will be asked to confirm they received it.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Mark Paid')),
        ],
      ),
    );
    if (ok != true) return;

    await Services.state.saveSettlement(SettlementModel(
      id: _uuid.v4(),
      groupId: group.id,
      fromId: s.fromId,
      toId: s.toId,
      amountCents: s.amount,
      createdAt: DateTime.now(),
      status: pending
          ? SettlementModel.statusPending
          : SettlementModel.statusConfirmed,
      markedById: Services.currentUserId,
    ));
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(pending
              ? 'Marked as paid — awaiting confirmation'
              : 'Payment recorded')));
    }
  }

  Future<void> _confirmSettlement(SettlementModel s) async {
    s.status = SettlementModel.statusConfirmed;
    await Services.state.saveSettlement(s);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed')));
    }
  }

  Future<void> _removeSettlement(SettlementModel s, String label,
      {required String title, required String body, required String action}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await Services.state.deleteSettlement(s.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final balances = Services.state.computeBalances(group.id);
    // Resolve names for everyone with a balance, including members removed
    // from the group who still appear in past expenses, so a settlement never
    // shows a raw id.
    final userNames = {for (final id in balances.keys) id: _nameFor(id)};
    final settlements =
    SettlementService.computeSettlements(balances, userNames);
    final allRecorded = Services.state.getSettlementsByGroup(group.id);
    final pending = allRecorded.where((s) => s.isPending).toList();
    final confirmed = allRecorded.where((s) => s.isConfirmed).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settle Up')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryBanner(balances, settlements),
          const SizedBox(height: 20),

          const SectionHeader(title: 'Net Balances'),
          const SizedBox(height: 8),
          _buildBalancesCard(balances),
          const SizedBox(height: 20),

          Row(
            children: [
              const SectionHeader(title: 'Payments Needed'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMid,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${settlements.length} payment${settlements.length != 1 ? 's' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (settlements.isEmpty)
            _buildAllSettledCard()
          else
            ...settlements.map((s) {
              // Only the person being paid (or whoever manages a placeholder
              // payee) can record a payment — not every group member.
              final canMark =
                  s.toId == Services.currentUserId || _isPlaceholder(s.toId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SettlementCard(
                  settlement: s,
                  onMarkPaid: canMark ? () => _recordPayment(s) : null,
                ),
              );
            }),

          if (pending.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Awaiting Confirmation'),
            const SizedBox(height: 8),
            ...pending.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PendingCard(
                    settlement: s,
                    fromName: _nameFor(s.fromId),
                    toName: _nameFor(s.toId),
                    canConfirm: _canConfirm(s),
                    canCancel: s.markedById == Services.currentUserId,
                    onConfirm: () => _confirmSettlement(s),
                    onDispute: () => _removeSettlement(
                      s,
                      '${_nameFor(s.fromId)} → ${_nameFor(s.toId)}',
                      title: 'Dispute Payment',
                      body:
                          'Remove this pending payment? Use this if you didn\'t receive it.',
                      action: 'Dispute',
                    ),
                    onCancel: () => _removeSettlement(
                      s,
                      '${_nameFor(s.fromId)} → ${_nameFor(s.toId)}',
                      title: 'Cancel Payment',
                      body: 'Withdraw this pending payment?',
                      action: 'Withdraw',
                    ),
                  ),
                )),
          ],

          if (confirmed.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Recorded Payments'),
            const SizedBox(height: 8),
            _buildRecordedCard(confirmed),
          ],

          const SizedBox(height: 20),
          _buildAlgorithmNote(settlements.length),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRecordedCard(List<SettlementModel> recorded) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: recorded.asMap().entries.map((e) {
          final i = e.key;
          final s = e.value;
          final fromName = _nameFor(s.fromId);
          final toName = _nameFor(s.toId);
          final label = '$fromName → $toName';
          return Column(
            children: [
              if (i > 0)
                Divider(height: 1, indent: 16, color: AppTheme.divider),
              ListTile(
                leading: const Icon(Icons.check_circle,
                    color: AppTheme.successColor, size: 20),
                title: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
                subtitle: Text(Money.withSymbol(s.amountCents),
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                trailing: IconButton(
                  icon: Icon(Icons.undo,
                      size: 18, color: AppTheme.textSecondary),
                  onPressed: () => _removeSettlement(
                    s,
                    label,
                    title: 'Undo Payment',
                    body: 'Remove the recorded payment "$label"?',
                    action: 'Remove',
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryBanner(
      Map<String, int> balances, List<Settlement> settlements) {
    final totalOwed = balances.values
        .where((v) => v > 0)
        .fold<int>(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Text('Outstanding Balance',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            Money.withSymbol(totalOwed),
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BannerStat(label: 'Members', value: '${balances.length}'),
              Container(width: 1, height: 28, color: AppTheme.divider),
              _BannerStat(
                  label: 'Min Payments',
                  value: '${settlements.length}'),
              Container(width: 1, height: 28, color: AppTheme.divider),
              _BannerStat(
                  label: 'Status',
                  value: settlements.isEmpty ? 'Settled' : 'Pending'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalancesCard(Map<String, int> balances) {
    final sorted = balances.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: sorted.asMap().entries.map((e) {
          final i = e.key;
          final userId = e.value.key;
          final balance = e.value.value;
          final name = _nameFor(userId);
          final isPos = balance > 0;
          final isZero = balance == 0;

          return Column(
            children: [
              if (i > 0)
                Divider(height: 1, indent: 56, color: AppTheme.divider),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: isZero
                      ? AppTheme.surfaceMid
                      : isPos
                      ? AppTheme.successColor.withOpacity(0.12)
                      : AppTheme.errorColor.withOpacity(0.12),
                  child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isZero
                              ? AppTheme.textSecondary
                              : isPos
                              ? AppTheme.successColor
                              : AppTheme.errorColor)),
                ),
                title: Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
                subtitle: Text(
                    isPos
                        ? 'Should receive'
                        : isZero
                        ? 'All settled'
                        : 'Should pay',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                trailing: isZero
                    ? const Icon(Icons.check_circle,
                    color: AppTheme.successColor, size: 20)
                    : Text(
                  '${isPos ? '+' : '-'}${Money.withSymbol(balance.abs())}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isPos
                        ? AppTheme.successColor
                        : AppTheme.errorColor,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAllSettledCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.successColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.successColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppTheme.successColor, size: 48),
          const SizedBox(height: 12),
          const Text('All Settled',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.successColor)),
          const SizedBox(height: 6),
          Text('Everyone is even. No payments needed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildAlgorithmNote(int count) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_outlined,
              color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? 'Everyone is even — no payments needed.'
                  : 'Simplified to $count payment${count != 1 ? 's' : ''} — the fewest needed to settle up.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  const _BannerStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700)),
      Text(label,
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 10)),
    ]);
  }
}

class _SettlementCard extends StatelessWidget {
  final Settlement settlement;
  final VoidCallback? onMarkPaid;
  const _SettlementCard({required this.settlement, this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
      Row(
        children: [
          // From
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.errorColor.withOpacity(0.12),
                  child: Text(settlement.fromName[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Text(settlement.fromName,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                    textAlign: TextAlign.center),
                Text('pays',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),

          // Amount + arrow
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(
                  Money.withSymbol(settlement.amount),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                        child: Container(
                            height: 1,
                            color: AppTheme.divider)),
                    Icon(Icons.arrow_forward,
                        color: AppTheme.textSecondary, size: 18),
                  ],
                ),
              ],
            ),
          ),

          // To
          Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor:
                  AppTheme.successColor.withOpacity(0.12),
                  child: Text(settlement.toName[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Text(settlement.toName,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                    textAlign: TextAlign.center),
                Text('receives',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
      if (onMarkPaid != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onMarkPaid,
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Mark as Paid'),
          ),
        ),
      ] else ...[
        const SizedBox(height: 10),
        Text('Only ${settlement.toName} can mark this received',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final SettlementModel settlement;
  final String fromName;
  final String toName;
  final bool canConfirm;
  final bool canCancel;
  final VoidCallback onConfirm;
  final VoidCallback onDispute;
  final VoidCallback onCancel;

  const _PendingCard({
    required this.settlement,
    required this.fromName,
    required this.toName,
    required this.canConfirm,
    required this.canCancel,
    required this.onConfirm,
    required this.onDispute,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFE0A52F);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top, color: amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$fromName → $toName',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
              ),
              Text(
                Money.withSymbol(settlement.amountCents),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            canConfirm
                ? 'Did you receive this payment?'
                : 'Awaiting $toName\'s confirmation',
            style: const TextStyle(fontSize: 12, color: amber),
          ),
          const SizedBox(height: 12),
          if (canConfirm)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDispute,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.errorColor),
                    child: const Text('Dispute'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm'),
                  ),
                ),
              ],
            )
          else if (canCancel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary),
                child: const Text('Withdraw'),
              ),
            ),
        ],
      ),
    );
  }
}

