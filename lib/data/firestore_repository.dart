// NOTE: imports resolve only after `flutter pub get` with the Firebase deps.
// This is Phase-1 scaffolding — verify against the Firestore emulator before
// relying on it (see SETUP.md). Some multi-user details (personal-expense
// ownership, contact invites) are finalised in Phase 2.
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

  // Serialization

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
    );
  }

  // Reactive reads

  @override
  Stream<List<UserModel>> watchUsers() => _users.snapshots().map((s) => s.docs
      .map((d) => UserModel(id: d.id, name: d.data()['name'] as String? ?? ''))
      .toList());

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
    return s.docs
        .map((d) => UserModel(id: d.id, name: d.data()['name'] as String? ?? ''))
        .toList();
  }

  @override
  Future<UserModel?> getUser(String id) async {
    final d = await _users.doc(id).get();
    if (!d.exists) return null;
    return UserModel(id: d.id, name: d.data()!['name'] as String? ?? '');
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
