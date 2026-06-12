import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/balances.dart';
import '../data/repository.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// In-memory, reactive view of the active [ExpensioRepository]. Subscribes to
/// the repository streams once and exposes synchronous getters so screens can
/// keep their existing build code (just swap `HiveService.x` → `appState.x` and
/// `ValueListenableBuilder` → `ListenableBuilder(listenable: appState)`).
///
/// Works identically for Hive (local) and Firestore (cloud) since it only
/// depends on the repository interface. Writes pass through to the repository;
/// the resulting stream events update the cache and notify listeners.
class AppState extends ChangeNotifier {
  AppState(this._repo);

  ExpensioRepository _repo;

  List<UserModel> _users = [];
  List<GroupModel> _groups = [];
  List<ExpenseModel> _expenses = []; // sorted newest-first
  List<SettlementModel> _settlements = [];

  final List<StreamSubscription> _subs = [];

  /// Subscribe and wait for the first value of every stream so the first frame
  /// has data.
  Future<void> init() => bindTo(_repo);

  /// Point the cache at a (possibly new) repository and re-subscribe. Called on
  /// startup and whenever the signed-in user changes (a different uid means a
  /// different cloud repository), so the UI swaps to the new account's data
  /// without rebuilding the widget tree. Waits for the first value of every
  /// stream before returning.
  Future<void> bindTo(ExpensioRepository repo) async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _repo = repo;
    // Clear immediately so stale data from the previous account doesn't flash.
    _users = [];
    _groups = [];
    _expenses = [];
    _settlements = [];
    notifyListeners();
    await Future.wait([
      _bind(_repo.watchUsers(), (v) => _users = v),
      _bind(_repo.watchGroups(), (v) => _groups = v),
      _bind(_repo.watchAllExpenses(), (v) => _expenses = v),
      _bind(_repo.watchAllSettlements(), (v) => _settlements = v),
    ]);
  }

  /// Ensure a profile exists for the signed-in user, keyed by their auth uid,
  /// so they're a real selectable member of what they create. Updates the
  /// stored name when a linked account provides a better one.
  Future<void> ensureSelfProfile(String uid, {String? name}) async {
    final existing = getUserById(uid);
    final desired = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (existing?.name ?? 'You');
    if (existing == null || existing.name != desired) {
      await _repo.saveUser(UserModel(id: uid, name: desired));
    }
  }

  Future<void> _bind<T>(Stream<T> stream, void Function(T) assign) {
    final first = Completer<void>();
    _subs.add(stream.listen((value) {
      assign(value);
      if (!first.isCompleted) first.complete();
      notifyListeners();
    }, onError: (Object e, StackTrace st) {
      debugPrint('[AppState] stream error: $e\n$st');
      if (!first.isCompleted) first.complete();
    }));
    return first.future;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // Synchronous reads (from cache)

  List<UserModel> get users => _users;
  List<GroupModel> get groups => _groups;
  List<ExpenseModel> get allExpenses => _expenses;

  // Aliases matching the old HiveService API so screens migrate cleanly.
  List<UserModel> getAllUsers() => _users;
  List<GroupModel> getAllGroups() => _groups;
  List<ExpenseModel> getAllExpenses() => _expenses; // newest-first

  UserModel? getUserById(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  GroupModel? getGroupById(String id) {
    for (final g in _groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<UserModel> membersOf(GroupModel group) => group.memberIds
      .map(getUserById)
      .whereType<UserModel>()
      .toList();

  List<ExpenseModel> getExpensesByGroup(String groupId) =>
      _expenses.where((e) => e.groupId == groupId).toList();

  List<SettlementModel> getSettlementsByGroup(String groupId) =>
      (_settlements.where((s) => s.groupId == groupId).toList())
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Net balance per userId for a group, in cents (applies recorded settlements).
  Map<String, int> computeBalances(String groupId) => computeBalancesFrom(
        getExpensesByGroup(groupId),
        getSettlementsByGroup(groupId),
      );

  // Writes (pass through to the repository)

  Future<void> saveUser(UserModel user) => _repo.saveUser(user);
  Future<void> deleteUser(String id) => _repo.deleteUser(id);
  Future<void> saveGroup(GroupModel group) => _repo.saveGroup(group);
  Future<void> deleteGroup(String id) => _repo.deleteGroup(id);
  Future<void> saveExpense(ExpenseModel expense) => _repo.saveExpense(expense);
  Future<void> deleteExpense(String id) => _repo.deleteExpense(id);
  Future<void> saveSettlement(SettlementModel s) => _repo.saveSettlement(s);
  Future<void> deleteSettlement(String id) => _repo.deleteSettlement(id);
  Future<void> clearAll() => _repo.clearAll();
}
