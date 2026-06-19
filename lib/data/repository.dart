import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';

/// A user-facing failure while creating or redeeming an invite.
class InviteException implements Exception {
  final String message;
  const InviteException(this.message);
  @override
  String toString() => message;
}

/// A placeholder (dummy) member a joiner can claim as themselves.
class InviteMember {
  final String id;
  final String name;
  const InviteMember({required this.id, required this.name});
}

/// A look-up of an invite by its code, used to preview a group before joining.
/// [claimable] lists the group's placeholder members the joiner may take over;
/// it's denormalized onto the invite because a non-member can't read the group.
class GroupInvite {
  final String code;
  final String groupId;
  final String groupName;
  final bool expired;
  final List<InviteMember> claimable;
  const GroupInvite({
    required this.code,
    required this.groupId,
    required this.groupName,
    required this.expired,
    this.claimable = const [],
  });
}

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

  // Invites (multi-device: bring a second real person into a group). Only the
  // cloud repository supports these; the local one throws [UnsupportedError].

  /// Mint a shareable invite for [groupId] and return its code.
  Future<String> createInvite(String groupId);

  /// Look up an invite by [code] to preview the group before joining; null if
  /// no such code.
  Future<GroupInvite?> getInvitePreview(String code);

  /// Join the group referenced by [code]: add the current user to it and
  /// backfill their access to existing expenses/settlements. When
  /// [claimPlaceholderId] is given, the current user takes over that
  /// placeholder member, inheriting its expenses/balances, and the
  /// placeholder is removed. Throws on an invalid or expired code.
  Future<void> joinGroup(String code, {String? claimPlaceholderId});
}
