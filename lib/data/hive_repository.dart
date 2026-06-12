import 'package:hive/hive.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../services/hive_service.dart';
import 'balances.dart';
import 'repository.dart';

/// Local-only repository backed by the existing Hive boxes. Reactive reads are
/// built from `box.watch()`: emit once immediately, then again on every change.
class HiveRepository implements ExpensioRepository {
  Box<UserModel> get _users => Hive.box<UserModel>('users');
  Box<GroupModel> get _groups => Hive.box<GroupModel>('groups');
  Box<ExpenseModel> get _expenses => Hive.box<ExpenseModel>('expenses');
  Box<SettlementModel> get _settlements => Hive.box<SettlementModel>('settlements');

  Stream<List<T>> _watch<T>(Box<T> box, List<T> Function() read) async* {
    yield read();
    await for (final _ in box.watch()) {
      yield read();
    }
  }

  @override
  Stream<List<UserModel>> watchUsers() =>
      _watch(_users, () => _users.values.toList());

  @override
  Stream<List<GroupModel>> watchGroups() =>
      _watch(_groups, () => _groups.values.toList());

  @override
  Stream<List<ExpenseModel>> watchAllExpenses() => _watch(
        _expenses,
        () => _expenses.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  @override
  Stream<List<ExpenseModel>> watchExpensesByGroup(String groupId) => _watch(
        _expenses,
        () => HiveService.getExpensesByGroup(groupId),
      );

  @override
  Stream<List<SettlementModel>> watchAllSettlements() =>
      _watch(_settlements, () => _settlements.values.toList());

  @override
  Stream<List<SettlementModel>> watchSettlementsByGroup(String groupId) =>
      _watch(_settlements, () => HiveService.getSettlementsByGroup(groupId));

  @override
  Future<List<UserModel>> getAllUsers() async => HiveService.getAllUsers();

  @override
  Future<UserModel?> getUser(String id) async => HiveService.getUserById(id);

  @override
  Future<GroupModel?> getGroup(String id) async => HiveService.getGroupById(id);

  @override
  Future<List<ExpenseModel>> getExpensesByGroup(String groupId) async =>
      HiveService.getExpensesByGroup(groupId);

  @override
  Future<void> saveUser(UserModel user) => HiveService.saveUser(user);

  @override
  Future<void> deleteUser(String id) => HiveService.deleteUser(id);

  @override
  Future<void> saveGroup(GroupModel group) => HiveService.saveGroup(group);

  @override
  Future<void> deleteGroup(String id) => HiveService.deleteGroup(id);

  @override
  Future<void> saveExpense(ExpenseModel expense) =>
      HiveService.saveExpense(expense);

  @override
  Future<void> deleteExpense(String id) => HiveService.deleteExpense(id);

  @override
  Future<void> saveSettlement(SettlementModel settlement) =>
      HiveService.saveSettlement(settlement);

  @override
  Future<void> deleteSettlement(String id) =>
      HiveService.deleteSettlement(id);

  @override
  Future<Map<String, int>> computeBalances(String groupId) async =>
      computeBalancesFrom(
        HiveService.getExpensesByGroup(groupId),
        HiveService.getSettlementsByGroup(groupId),
      );

  @override
  Future<void> clearAll() async {
    await _expenses.clear();
    await _groups.clear();
    await _users.clear();
    await _settlements.clear();
  }

  // Invites require the cloud backend.
  static Never _noCloud() => throw UnsupportedError(
        'Invites need an account — sign in to share or join a group.',
      );

  @override
  Future<String> createInvite(String groupId) async => _noCloud();

  @override
  Future<GroupInvite?> getInvitePreview(String code) async => _noCloud();

  @override
  Future<void> joinGroup(String code, {String? claimPlaceholderId}) async =>
      _noCloud();
}
