import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../utils/money.dart';

/// Pure balance computation, shared by every repository implementation (and
/// easy to unit-test). All amounts are in minor units (cents).
///
/// Returns net balance per userId: +ve = they are owed money, -ve = they owe.
/// Group expenses split exactly (remainder distributed); recorded settlements
/// move both parties toward zero so real-world payments clear debts.
Map<String, int> computeBalancesFrom(
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  final Map<String, int> balances = {};

  for (final expense in expenses) {
    if (expense.isPersonal) continue;

    final payerId = expense.payerId;

    if (expense.splitMap.isNotEmpty) {
      // Explicit split map (already in cents).
      for (final entry in expense.splitMap.entries) {
        final userId = entry.key;
        final owes = entry.value;
        if (userId == payerId) continue;
        balances[payerId] = (balances[payerId] ?? 0) + owes;
        balances[userId] = (balances[userId] ?? 0) - owes;
      }
    } else {
      // Equal split, distributing remainder cents exactly.
      final participants = expense.participantIds;
      if (participants.isEmpty) continue;
      final shares = Money.splitEqual(expense.totalAmount, participants.length);
      for (int i = 0; i < participants.length; i++) {
        final uid = participants[i];
        if (uid == payerId) continue;
        final share = shares[i];
        balances[payerId] = (balances[payerId] ?? 0) + share;
        balances[uid] = (balances[uid] ?? 0) - share;
      }
    }
  }

  for (final s in settlements) {
    balances[s.fromId] = (balances[s.fromId] ?? 0) + s.amountCents;
    balances[s.toId] = (balances[s.toId] ?? 0) - s.amountCents;
  }

  return balances;
}

/// The portion of [e] that [uid] owes (their consumption), in cents. Uses the
/// explicit split map when present, otherwise an exact equal split. Returns 0
/// when the user isn't a participant.
int userShareOf(ExpenseModel e, String uid) {
  if (e.splitMap.isNotEmpty) return e.splitMap[uid] ?? 0;
  final idx = e.participantIds.indexOf(uid);
  if (idx < 0) return 0;
  return Money.splitEqual(e.totalAmount, e.participantIds.length)[idx];
}

/// The amount of [e] attributable to [uid] from their own ledger's point of
/// view, in cents: the full total when they fronted it (personal, or they're
/// the group payer), otherwise just their share. This is what the Transactions
/// page and its stats show, so tile amounts and totals stay consistent.
int userAmountOf(ExpenseModel e, String uid) {
  if (e.isPersonal || e.payerId == uid) return e.totalAmount;
  return userShareOf(e, uid);
}
