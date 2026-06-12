import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/bill_item_model.dart';
import '../models/settlement_model.dart';
import '../data/balances.dart';

class HiveService {
  static const String _usersBox = 'users';
  static const String _groupsBox = 'groups';
  static const String _expensesBox = 'expenses';
  static const String _settlementsBox = 'settlements';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(BillItemAdapter());
    Hive.registerAdapter(ExpenseModelAdapter());
    Hive.registerAdapter(GroupModelAdapter());
    Hive.registerAdapter(SettlementModelAdapter());

    // Open boxes
    await Hive.openBox<UserModel>(_usersBox);
    await Hive.openBox<GroupModel>(_groupsBox);
    await Hive.openBox<ExpenseModel>(_expensesBox);
    await Hive.openBox<SettlementModel>(_settlementsBox);
    await Hive.openBox('settings');
  }

  // Users 

  static Box<UserModel> get _users => Hive.box<UserModel>(_usersBox);

  static Future<void> saveUser(UserModel user) async {
    try {
      await _users.put(user.id, user);
    } catch (e, st) {
      debugPrint('[Hive] saveUser error: $e\n$st');
      rethrow;
    }
  }

  static List<UserModel> getAllUsers() => _users.values.toList();

  static UserModel? getUserById(String id) => _users.get(id);

  static Future<void> deleteUser(String id) async {
    await _users.delete(id);
  }

  // Groups 

  static Box<GroupModel> get _groups => Hive.box<GroupModel>(_groupsBox);

  static Future<void> saveGroup(GroupModel group) async {
    try {
      await _groups.put(group.id, group);
    } catch (e, st) {
      debugPrint('[Hive] saveGroup error: $e\n$st');
      rethrow;
    }
  }

  static List<GroupModel> getAllGroups() => _groups.values.toList();

  static GroupModel? getGroupById(String id) => _groups.get(id);

  static Future<void> deleteGroup(String id) async {
    await _groups.delete(id);
    // Also remove related expenses
    final toDelete = _expenses.values
        .where((e) => e.groupId == id)
        .map((e) => e.id)
        .toList();
    for (final eid in toDelete) {
      await _expenses.delete(eid);
    }
    // And any recorded settlements
    final settlementsToDelete = _settlements.values
        .where((s) => s.groupId == id)
        .map((s) => s.id)
        .toList();
    for (final sid in settlementsToDelete) {
      await _settlements.delete(sid);
    }
  }

  // Expenses 

  static Box<ExpenseModel> get _expenses => Hive.box<ExpenseModel>(_expensesBox);

  static Future<void> saveExpense(ExpenseModel expense) async {
    await _expenses.put(expense.id, expense);
  }

  static List<ExpenseModel> getAllExpenses() => _expenses.values.toList();

  static List<ExpenseModel> getExpensesByGroup(String groupId) =>
      _expenses.values.where((e) => e.groupId == groupId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static Future<void> deleteExpense(String id) async {
    await _expenses.delete(id);
  }
  static Future<void> updateExpense(ExpenseModel expense) async {
    await _expenses.put(expense.id, expense);
  }

  // Settlements (recorded real-world payments)

  static Box<SettlementModel> get _settlements =>
      Hive.box<SettlementModel>(_settlementsBox);

  static Future<void> saveSettlement(SettlementModel settlement) async {
    await _settlements.put(settlement.id, settlement);
  }

  static List<SettlementModel> getSettlementsByGroup(String groupId) =>
      _settlements.values.where((s) => s.groupId == groupId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static Future<void> deleteSettlement(String id) async {
    await _settlements.delete(id);
  }

  // Balances

  /// Returns net balance per userId for a group, in minor units (cents).
  /// Delegates to the shared pure [computeBalances] so every repository and the
  /// tests share one implementation.
  static Map<String, int> computeBalances(String groupId) =>
      computeBalancesFrom(
        getExpensesByGroup(groupId),
        getSettlementsByGroup(groupId),
      );
}