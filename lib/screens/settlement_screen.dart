import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/hive_service.dart';
import '../services/settlement_service.dart';
import '../utils/app_theme.dart';

class SettlementScreen extends StatelessWidget {
  final GroupModel group;
  const SettlementScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final members = group.memberIds
        .map(HiveService.getUserById)
        .whereType<UserModel>()
        .toList();
    final balances = HiveService.computeBalances(group.id);
    final userNames = {for (final m in members) m.id: m.name};
    final settlements =
    SettlementService.computeSettlements(balances, userNames);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settle Up'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummaryBanner(balances, settlements),
          const SizedBox(height: 20),

          const SectionHeader(title: 'Net Balances'),
          const SizedBox(height: 8),
          _buildBalancesCard(balances, userNames),
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
                  style: const TextStyle(
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
            ...settlements.asMap().entries.map(
                  (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SettlementCard(settlement: e.value),
              ),
            ),

          const SizedBox(height: 20),
          _buildAlgorithmNote(settlements.length),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(
      Map<String, double> balances, List<Settlement> settlements) {
    final totalOwed = balances.values
        .where((v) => v > 0)
        .fold<double>(0, (s, v) => s + v);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          const Text('Outstanding Balance',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            'Rs ${totalOwed.toStringAsFixed(2)}',
            style: const TextStyle(
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
                  label: 'Settled',
                  value: settlements.isEmpty ? 'Yes' : 'No'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalancesCard(
      Map<String, double> balances, Map<String, String> userNames) {
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
          final name = userNames[userId] ?? userId;
          final isPos = balance > 0;
          final isZero = balance.abs() < 0.01;

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
                    style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary)),
                subtitle: Text(
                    isPos
                        ? 'Should receive'
                        : isZero
                        ? 'All settled'
                        : 'Should pay',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                trailing: isZero
                    ? const Icon(Icons.check_circle,
                    color: AppTheme.successColor, size: 20)
                    : Text(
                  '${isPos ? '+' : '-'}Rs ${balance.abs().toStringAsFixed(2)}',
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
      child: const Column(
        children: [
          Icon(Icons.check_circle_outline,
              color: AppTheme.successColor, size: 48),
          SizedBox(height: 12),
          Text('All Settled',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.successColor)),
          SizedBox(height: 6),
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
          const Icon(Icons.psychology_outlined,
              color: AppTheme.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 0
                  ? 'No transactions needed — everyone is even.'
                  : 'Algorithm minimized payments to $count transaction${count != 1 ? 's' : ''} using greedy + optimal backtracking.',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settlement Algorithm'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Expensio minimizes transactions using a two-phase approach:',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              SizedBox(height: 12),
              _InfoStep(n: '1', title: 'Net Balances',
                  desc: 'Calculate total owed/owing per person.'),
              _InfoStep(n: '2', title: 'Greedy (O n log n)',
                  desc: 'Match largest debtor with largest creditor repeatedly.'),
              _InfoStep(n: '3', title: 'Optimal (≤10 members)',
                  desc: 'Backtracking finds the absolute minimum transactions.'),
              _InfoStep(n: '4', title: 'Best wins',
                  desc: 'Returns whichever approach gives fewer payments.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it')),
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
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700)),
      Text(label,
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10)),
    ]);
  }
}

class _SettlementCard extends StatelessWidget {
  final Settlement settlement;
  const _SettlementCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                    textAlign: TextAlign.center),
                const Text('pays',
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
                  'Rs ${settlement.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
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
                    const Icon(Icons.arrow_forward,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                    textAlign: TextAlign.center),
                const Text('receives',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStep extends StatelessWidget {
  final String n;
  final String title;
  final String desc;
  const _InfoStep(
      {required this.n, required this.title, required this.desc});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surfaceMid,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(n,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textPrimary)),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}