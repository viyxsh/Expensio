import 'dart:math';

/// Represents a single settlement transaction. [amount] is in minor units (cents).
class Settlement {
  final String fromId;
  final String fromName;
  final String toId;
  final String toName;
  final int amount;

  const Settlement({
    required this.fromId,
    required this.fromName,
    required this.toId,
    required this.toName,
    required this.amount,
  });

  @override
  String toString() => '$fromName pays $toName $amount';
}

class SettlementService {
  /// Groups larger than this skip the (exponential) optimal search and use the
  /// greedy result directly. Backtracking is worst-case factorial, so the bound
  /// is kept conservative to avoid janking the UI thread.
  static const int _optimalMaxMembers = 8;

  /// Hard cap on backtracking node visits. If exceeded, we bail out and keep the
  /// best complete solution found so far (falling back to greedy when none beats it).
  static const int _maxBacktrackSteps = 200000;

  /// Main entry point. Computes minimal transactions from net balances (cents).
  ///
  /// Step 1: Compute net balance per user (done externally via HiveService).
  /// Step 2: Run greedy algorithm O(n log n) for any group size.
  /// Step 3: For small groups, run capped optimal backtracking to minimize count.
  static List<Settlement> computeSettlements(
    Map<String, int> balances,
    Map<String, String> userNames, // userId to name
  ) {
    // Remove zero balances.
    final cleanBalances = Map<String, int>.fromEntries(
      balances.entries.where((e) => e.value != 0),
    );

    if (cleanBalances.isEmpty) return [];

    final greedy = _greedySettle(cleanBalances, userNames);

    // For small groups, try to find an optimal (fewer transactions) solution.
    if (cleanBalances.length <= _optimalMaxMembers) {
      final optimal = _optimalSettle(cleanBalances, userNames, greedy);
      if (optimal.length < greedy.length) return optimal;
    }

    return greedy;
  }

  // Greedy Algorithm
  // Match largest debtor with largest creditor repeatedly in O(n log n).

  static List<Settlement> _greedySettle(
    Map<String, int> balances,
    Map<String, String> userNames,
  ) {
    final List<Settlement> settlements = [];

    // Separate into creditors (+) and debtors (-).
    final creditors = balances.entries
        .where((e) => e.value > 0)
        .map((e) => _BalanceEntry(e.key, e.value))
        .toList();
    final debtors = balances.entries
        .where((e) => e.value < 0)
        .map((e) => _BalanceEntry(e.key, e.value.abs()))
        .toList();

    // Sort descending by amount.
    creditors.sort((a, b) => b.amount.compareTo(a.amount));
    debtors.sort((a, b) => b.amount.compareTo(a.amount));

    int ci = 0, di = 0;
    while (ci < creditors.length && di < debtors.length) {
      final creditor = creditors[ci];
      final debtor = debtors[di];

      final amount = min(creditor.amount, debtor.amount);

      if (amount > 0) {
        settlements.add(Settlement(
          fromId: debtor.userId,
          fromName: userNames[debtor.userId] ?? debtor.userId,
          toId: creditor.userId,
          toName: userNames[creditor.userId] ?? creditor.userId,
          amount: amount,
        ));
      }

      creditor.amount -= amount;
      debtor.amount -= amount;

      if (creditor.amount <= 0) ci++;
      if (debtor.amount <= 0) di++;
    }

    return settlements;
  }

  // Optimal Algorithm (Backtracking)
  // Finds minimum number of transactions for small groups, capped for safety.

  static List<Settlement> _optimalSettle(
    Map<String, int> balances,
    Map<String, String> userNames,
    List<Settlement> greedyFallback,
  ) {
    final List<_BalanceEntry> entries = balances.entries
        .map((e) => _BalanceEntry(e.key, e.value))
        .toList();

    final List<List<Settlement>> result = [[]];
    // Seed the upper bound with greedy so we only keep strictly better solutions.
    final bestCount = [greedyFallback.length];
    final steps = [0];

    _backtrack(entries, userNames, 0, [], result, bestCount, steps);

    return result[0].isEmpty ? greedyFallback : result[0];
  }

  static void _backtrack(
    List<_BalanceEntry> entries,
    Map<String, String> userNames,
    int startIdx,
    List<Settlement> currentSettlements,
    List<List<Settlement>> best,
    List<int> bestCount,
    List<int> steps,
  ) {
    if (steps[0]++ > _maxBacktrackSteps) return; // Bail; keep best found so far.

    // Skip entries that are already settled.
    while (startIdx < entries.length && entries[startIdx].amount == 0) {
      startIdx++;
    }

    if (startIdx == entries.length) {
      if (currentSettlements.length < bestCount[0]) {
        bestCount[0] = currentSettlements.length;
        best[0] = List.from(currentSettlements);
      }
      return;
    }

    // Prune: current path already worse than best known.
    if (currentSettlements.length >= bestCount[0]) return;

    final entry = entries[startIdx];

    for (int j = startIdx + 1; j < entries.length; j++) {
      final other = entries[j];
      // One must owe and other must be owed.
      if (entry.amount * other.amount >= 0) continue;

      final payer = entry.amount < 0 ? entry : other;
      final payee = entry.amount > 0 ? entry : other;

      final transferAmount = min(payer.amount.abs(), payee.amount.abs());
      if (transferAmount <= 0) continue;

      final settlement = Settlement(
        fromId: payer.userId,
        fromName: userNames[payer.userId] ?? payer.userId,
        toId: payee.userId,
        toName: userNames[payee.userId] ?? payee.userId,
        amount: transferAmount,
      );

      // Apply.
      payer.amount += transferAmount;
      payee.amount -= transferAmount;
      currentSettlements.add(settlement);

      _backtrack(entries, userNames, startIdx + 1, currentSettlements, best,
          bestCount, steps);

      // Undo.
      currentSettlements.removeLast();
      payer.amount -= transferAmount;
      payee.amount += transferAmount;
    }
  }
}

class _BalanceEntry {
  final String userId;
  int amount;
  _BalanceEntry(this.userId, this.amount);
}
