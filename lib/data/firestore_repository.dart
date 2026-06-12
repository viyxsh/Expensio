// NOTE: imports resolve only after `flutter pub get` with the Firebase deps.
// This is Phase-1 scaffolding — verify against the Firestore emulator before
// relying on it (see SETUP.md). Some multi-user details (personal-expense
// ownership, contact invites) are finalised in Phase 2.
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/bill_item_model.dart';
import '../models/settlement_model.dart';
import 'balances.dart';
import 'repository.dart';

/// Cloud-backed repository. Firestore's offline persistence (enabled in
/// [FirebaseBootstrap]) provides the local cache, so reads work offline and
/// sync when back online. [uid] is the signed-in user; reads are scoped to the
/// groups/items visible to them via membership.
class FirestoreRepository implements ExpensioRepository {
  FirestoreRepository({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');
  CollectionReference<Map<String, dynamic>> get _expenses =>
      _db.collection('expenses');
  CollectionReference<Map<String, dynamic>> get _settlements =>
      _db.collection('settlements');
  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('invites');

  // Serialization

  UserModel _userFromData(String id, Map<String, dynamic>? d) =>
      UserModel(id: id, name: d?['name'] as String? ?? '');

  Map<String, dynamic> _groupToMap(GroupModel g) => {
        'name': g.name,
        'memberIds': g.memberIds,
        'createdAt': Timestamp.fromDate(g.createdAt),
        'description': g.description,
      };

  GroupModel _groupFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return GroupModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      memberIds: List<String>.from(d['memberIds'] as List? ?? const []),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      description: d['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> _itemToMap(BillItem i) => {
        'name': i.name,
        'price': i.price,
        'category': i.category,
        'quantity': i.quantity,
        'assignedUserIds': i.assignedUserIds,
      };

  BillItem _itemFromMap(Map<String, dynamic> m) => BillItem(
        name: m['name'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        category: m['category'] as String? ?? 'General',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        assignedUserIds:
            List<String>.from(m['assignedUserIds'] as List? ?? const []),
      );

  /// Who may see this expense. Used by [watchAllExpenses] (`arrayContains uid`).
  List<String> _visibleTo(ExpenseModel e) => e.isPersonal
      ? [uid]
      : {...e.participantIds, e.payerId}.toList();

  Map<String, dynamic> _expenseToMap(ExpenseModel e) => {
        'title': e.title,
        'totalAmount': e.totalAmount,
        'payerId': e.payerId,
        'participantIds': e.participantIds,
        'groupId': e.groupId,
        'createdAt': Timestamp.fromDate(e.createdAt),
        'items': e.items.map(_itemToMap).toList(),
        'category': e.category,
        'isPersonal': e.isPersonal,
        'splitMap': e.splitMap,
        'visibleTo': _visibleTo(e),
      };

  ExpenseModel _expenseFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ExpenseModel(
      id: doc.id,
      title: d['title'] as String? ?? '',
      totalAmount: (d['totalAmount'] as num?)?.toInt() ?? 0,
      payerId: d['payerId'] as String? ?? '',
      participantIds:
          List<String>.from(d['participantIds'] as List? ?? const []),
      groupId: d['groupId'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      items: (d['items'] as List? ?? const [])
          .map((m) => _itemFromMap(Map<String, dynamic>.from(m as Map)))
          .toList(),
      category: d['category'] as String? ?? 'General',
      isPersonal: d['isPersonal'] as bool? ?? false,
      splitMap: (d['splitMap'] as Map? ?? const {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt())),
    );
  }

  Map<String, dynamic> _settlementToMap(SettlementModel s) => {
        'groupId': s.groupId,
        'fromId': s.fromId,
        'toId': s.toId,
        'amountCents': s.amountCents,
        'createdAt': Timestamp.fromDate(s.createdAt),
        'status': s.status,
        'markedById': s.markedById,
      };

  SettlementModel _settlementFromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SettlementModel(
      id: doc.id,
      groupId: d['groupId'] as String? ?? '',
      fromId: d['fromId'] as String? ?? '',
      toId: d['toId'] as String? ?? '',
      amountCents: (d['amountCents'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      status:
          d['status'] as String? ?? SettlementModel.statusConfirmed,
      markedById: d['markedById'] as String?,
    );
  }

  // Reactive reads

  @override
  Stream<List<UserModel>> watchUsers() => _users.snapshots().map((s) =>
      s.docs.map((d) => _userFromData(d.id, d.data())).toList());

  @override
  Stream<List<GroupModel>> watchGroups() => _groups
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(_groupFromDoc).toList());

  @override
  Stream<List<ExpenseModel>> watchAllExpenses() => _expenses
      .where('visibleTo', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(_expenseFromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<List<ExpenseModel>> watchExpensesByGroup(String groupId) => _expenses
      .where('groupId', isEqualTo: groupId)
      .snapshots()
      .map((s) => s.docs.map(_expenseFromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<List<SettlementModel>> watchAllSettlements() => _settlements
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(_settlementFromDoc).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Stream<List<SettlementModel>> watchSettlementsByGroup(String groupId) =>
      _settlements
          .where('groupId', isEqualTo: groupId)
          .snapshots()
          .map((s) => s.docs.map(_settlementFromDoc).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  // One-shot reads

  @override
  Future<List<UserModel>> getAllUsers() async {
    final s = await _users.get();
    return s.docs.map((d) => _userFromData(d.id, d.data())).toList();
  }

  @override
  Future<UserModel?> getUser(String id) async {
    final d = await _users.doc(id).get();
    if (!d.exists) return null;
    return _userFromData(d.id, d.data());
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    final d = await _groups.doc(id).get();
    return d.exists ? _groupFromDoc(d) : null;
  }

  @override
  Future<List<ExpenseModel>> getExpensesByGroup(String groupId) async {
    final s = await _expenses.where('groupId', isEqualTo: groupId).get();
    return s.docs.map(_expenseFromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // Writes

  @override
  Future<void> saveUser(UserModel user) =>
      _users.doc(user.id).set({'name': user.name});

  @override
  Future<void> deleteUser(String id) => _users.doc(id).delete();

  @override
  Future<void> saveGroup(GroupModel group) =>
      _groups.doc(group.id).set(_groupToMap(group));

  @override
  Future<void> deleteGroup(String id) async {
    // Cascade: delete the group plus its expenses and settlements in a batch.
    final batch = _db.batch();
    batch.delete(_groups.doc(id));
    final exp = await _expenses.where('groupId', isEqualTo: id).get();
    for (final d in exp.docs) {
      batch.delete(d.reference);
    }
    final set = await _settlements.where('groupId', isEqualTo: id).get();
    for (final d in set.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  @override
  Future<void> saveExpense(ExpenseModel expense) async {
    final map = _expenseToMap(expense);
    // For a group expense, every group member should be able to see it — not
    // just the people split on this one bill. Denormalize the group's members
    // onto `visibleTo` so the rules permit the write and it syncs to everyone
    // in the group (always including the writer as a fallback). Personal
    // expenses keep their owner-only visibility from [_expenseToMap].
    if (!expense.isPersonal && expense.groupId.isNotEmpty) {
      final group = await _groups.doc(expense.groupId).get();
      final members =
          List<String>.from(group.data()?['memberIds'] as List? ?? const []);
      map['visibleTo'] = {
        ...members,
        ...expense.participantIds,
        expense.payerId,
        uid,
      }.toList();
    }
    await _expenses.doc(expense.id).set(map);
  }

  @override
  Future<void> deleteExpense(String id) => _expenses.doc(id).delete();

  @override
  Future<void> saveSettlement(SettlementModel settlement) async {
    // Denormalize the group's members onto the settlement so it can be queried
    // for the whole user (watchAllSettlements) and gated by the rules.
    final group = await _groups.doc(settlement.groupId).get();
    final members =
        List<String>.from(group.data()?['memberIds'] as List? ?? const []);
    await _settlements.doc(settlement.id).set({
      ..._settlementToMap(settlement),
      'memberIds': members,
    });
  }

  @override
  Future<void> deleteSettlement(String id) => _settlements.doc(id).delete();

  @override
  Future<Map<String, int>> computeBalances(String groupId) async {
    final expenses = await getExpensesByGroup(groupId);
    final s = await _settlements.where('groupId', isEqualTo: groupId).get();
    final settlements = s.docs.map(_settlementFromDoc).toList();
    return computeBalancesFrom(expenses, settlements);
  }

  // Invites

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // no I/O/0/1/L
  static const _inviteTtl = Duration(days: 7);

  String _newCode() {
    final r = Random.secure();
    return List.generate(
        8, (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)]).join();
  }

  // Placeholder (dummy) members have uuid ids (with dashes); real accounts are
  // Firebase uids (no dashes). Used to decide who a joiner may claim.
  bool _isPlaceholder(String id) => id.contains('-');

  @override
  Future<String> createInvite(String groupId) async {
    final group = await _groups.doc(groupId).get();
    if (!group.exists) {
      throw const InviteException('That group no longer exists.');
    }
    final data = group.data()!;
    final groupName = data['name'] as String? ?? 'Group';
    final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);

    // Snapshot the claimable placeholder members onto the invite so a joiner
    // (who can't read the group yet) can pick which one they are.
    final roster = <Map<String, dynamic>>[];
    for (final id in memberIds) {
      if (!_isPlaceholder(id)) continue;
      final u = await _users.doc(id).get();
      roster.add({'id': id, 'name': u.data()?['name'] as String? ?? 'Member'});
    }

    final code = _newCode();
    await _invites.doc(code).set({
      'groupId': groupId,
      'groupName': groupName,
      'roster': roster,
      'createdBy': uid,
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(_inviteTtl)),
    });
    return code;
  }

  @override
  Future<GroupInvite?> getInvitePreview(String code) async {
    final doc = await _invites.doc(code.trim().toUpperCase()).get();
    if (!doc.exists) return null;
    final d = doc.data()!;
    final expiresAt = (d['expiresAt'] as Timestamp?)?.toDate();
    final roster = (d['roster'] as List? ?? const [])
        .map((m) => InviteMember(
              id: (m as Map)['id'] as String? ?? '',
              name: m['name'] as String? ?? 'Member',
            ))
        .where((m) => m.id.isNotEmpty)
        .toList();
    return GroupInvite(
      code: doc.id,
      groupId: d['groupId'] as String? ?? '',
      groupName: d['groupName'] as String? ?? 'Group',
      expired: expiresAt == null || expiresAt.isBefore(DateTime.now()),
      claimable: roster,
    );
  }

  /// Replace every reference to [from] with [to] inside one expense.
  ExpenseModel _remapExpense(ExpenseModel e, String from, String to) {
    String id(String x) => x == from ? to : x;
    final split = <String, int>{};
    e.splitMap.forEach((k, v) {
      final nk = id(k);
      split[nk] = (split[nk] ?? 0) + v;
    });
    return ExpenseModel(
      id: e.id,
      title: e.title,
      totalAmount: e.totalAmount,
      payerId: id(e.payerId),
      participantIds: e.participantIds.map(id).toSet().toList(),
      groupId: e.groupId,
      createdAt: e.createdAt,
      items: e.items
          .map((i) => BillItem(
                name: i.name,
                price: i.price,
                category: i.category,
                quantity: i.quantity,
                assignedUserIds: i.assignedUserIds.map(id).toSet().toList(),
              ))
          .toList(),
      category: e.category,
      isPersonal: e.isPersonal,
      splitMap: split,
    );
  }

  @override
  Future<void> joinGroup(String code, {String? claimPlaceholderId}) async {
    final normalized = code.trim().toUpperCase();
    final invite = await getInvitePreview(normalized);
    if (invite == null) {
      throw const InviteException('Invalid invite code.');
    }
    if (invite.expired) {
      throw const InviteException('This invite has expired.');
    }
    final groupId = invite.groupId;
    final claim = claimPlaceholderId;

    // 1) Add ONLY ourselves to the group. `joinCode` authorises this for a
    //    non-member in the rules (a combined add+remove would fail that check,
    //    so claiming a placeholder happens as a separate member edit below).
    await _groups.doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([uid]),
      'joinCode': normalized,
    });

    // 2) As a member now, fix up the group's history: ensure we can see every
    //    expense/settlement, and — if claiming — rewrite the placeholder to us.
    final exp = await _expenses.where('groupId', isEqualTo: groupId).get();
    final sets = await _settlements.where('groupId', isEqualTo: groupId).get();
    final batch = _db.batch();

    for (final d in exp.docs) {
      if (claim == null) {
        batch.update(d.reference, {'visibleTo': FieldValue.arrayUnion([uid])});
        continue;
      }
      final remapped = _remapExpense(_expenseFromDoc(d), claim, uid);
      final visibleTo = List<String>.from(d.data()['visibleTo'] as List? ?? const [])
        ..remove(claim);
      if (!visibleTo.contains(uid)) visibleTo.add(uid);
      batch.update(d.reference, {
        'payerId': remapped.payerId,
        'participantIds': remapped.participantIds,
        'splitMap': remapped.splitMap,
        'items': remapped.items.map(_itemToMap).toList(),
        'visibleTo': visibleTo,
      });
    }

    for (final d in sets.docs) {
      if (claim == null) {
        batch.update(d.reference, {'memberIds': FieldValue.arrayUnion([uid])});
        continue;
      }
      final data = d.data();
      final members = List<String>.from(data['memberIds'] as List? ?? const [])
        ..remove(claim);
      if (!members.contains(uid)) members.add(uid);
      batch.update(d.reference, {
        'fromId': data['fromId'] == claim ? uid : data['fromId'],
        'toId': data['toId'] == claim ? uid : data['toId'],
        'memberIds': members,
      });
    }

    if (claim != null) {
      // Drop the now-claimed placeholder from the group and delete its profile.
      batch.update(_groups.doc(groupId), {
        'memberIds': FieldValue.arrayRemove([claim]),
      });
      batch.delete(_users.doc(claim));
    }

    await batch.commit();
  }

  @override
  Future<void> clearAll() async {
    // Only clears the signed-in user's own visible data (see security rules).
    Future<void> wipe(QuerySnapshot<Map<String, dynamic>> snap) async {
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    await wipe(await _groups.where('memberIds', arrayContains: uid).get());
    await wipe(await _expenses.where('visibleTo', arrayContains: uid).get());
    await wipe(await _settlements.where('memberIds', arrayContains: uid).get());
  }
}
