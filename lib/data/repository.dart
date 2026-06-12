import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// Provider-agnostic data access for the whole app. The UI depends only on this
/// interface; [HiveRepository] backs local-only mode and [FirestoreRepository]
/// backs signed-in multi-device mode. Reads are streams (reactive, works for
/// both Hive's box.watch() and Firestore snapshots); writes are futures.
///
/// All money is in minor units (cents). Deleting a group cascades to its
/// expenses and settlements.
abstract class ExpensioRepository {
  // Reactive reads
  Stream<List<UserModel>> watchUsers();
  Stream<List<GroupModel>> watchGroups();
  Stream<List<ExpenseModel>> watchAllExpenses();
  Stream<List<ExpenseModel>> watchExpensesByGroup(String groupId);
  Stream<List<SettlementModel>> watchAllSettlements();
  Stream<List<SettlementModel>> watchSettlementsByGroup(String groupId);

  // One-shot reads
  Future<List<UserModel>> getAllUsers();
  Future<UserModel?> getUser(String id);
  Future<GroupModel?> getGroup(String id);
  Future<List<ExpenseModel>> getExpensesByGroup(String groupId);

  // Writes
  Future<void> saveUser(UserModel user);
  Future<void> deleteUser(String id);
  Future<void> saveGroup(GroupModel group);
  Future<void> deleteGroup(String id); // cascades
  Future<void> saveExpense(ExpenseModel expense);
  Future<void> deleteExpense(String id);
  Future<void> saveSettlement(SettlementModel settlement);
  Future<void> deleteSettlement(String id);

  /// Net balance per userId for a group, in cents (applies recorded settlements).
  Future<Map<String, int>> computeBalances(String groupId);

  /// Wipe all data this repository owns (used by "Clear All Data").
  Future<void> clearAll();
}
