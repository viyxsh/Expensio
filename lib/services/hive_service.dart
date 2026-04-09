import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/bill_item_model.dart';

class HiveService {
  static const String _usersBox = 'users';
  static const String _groupsBox = 'groups';
  static const String _expensesBox = 'expenses';

  static Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(UserModelAdapter());
    Hive.registerAdapter(BillItemAdapter());
    Hive.registerAdapter(ExpenseModelAdapter());
    Hive.registerAdapter(GroupModelAdapter());

    // Open boxes
    await Hive.openBox<UserModel>(_usersBox);
    await Hive.openBox<GroupModel>(_groupsBox);
    await Hive.openBox<ExpenseModel>(_expensesBox);
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

  // Balances 

  /// Returns net balance per userId for a group.
  /// +ve = they are owed money, -ve = they owe money.
  static Map<String, double> computeBalances(String groupId) {
    final expenses = getExpensesByGroup(groupId);
    final Map<String, double> balances = {};

    for (final expense in expenses) {
      if (expense.isPersonal) continue;

      final payerId = expense.payerId;

      if (expense.splitMap.isNotEmpty) {
        // Use explicit split map
        for (final entry in expense.splitMap.entries) {
          final userId = entry.key;
          final owes = entry.value;
          if (userId == payerId) continue;
          balances[payerId] = (balances[payerId] ?? 0) + owes;
          balances[userId] = (balances[userId] ?? 0) - owes;
        }
      } else {
        // Equal split among participants
        final participants = expense.participantIds;
        if (participants.isEmpty) continue;
        final share = expense.totalAmount / participants.length;
        for (final uid in participants) {
          if (uid == payerId) continue;
          balances[payerId] = (balances[payerId] ?? 0) + share;
          balances[uid] = (balances[uid] ?? 0) - share;
        }
      }
    }

    return balances;
  }
}