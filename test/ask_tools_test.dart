import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:expensio/data/hive_repository.dart';
import 'package:expensio/models/bill_item_model.dart';
import 'package:expensio/models/expense_model.dart';
import 'package:expensio/models/group_model.dart';
import 'package:expensio/models/settlement_model.dart';
import 'package:expensio/models/user_model.dart';
import 'package:expensio/services/ask_tools.dart';
import 'package:expensio/services/auth_service.dart';
import 'package:expensio/services/services.dart';
import 'package:expensio/state/app_state.dart';

/// Boots a real Hive-backed AppState in a temp dir so the tool surface can be
/// exercised end-to-end without Firebase.
Future<void> _boot() async {
  final dir = await Directory.systemTemp.createTemp('expensio_ask_test');
  Hive.init(dir.path);
  Hive.registerAdapter(UserModelAdapter());
  Hive.registerAdapter(BillItemAdapter());
  Hive.registerAdapter(ExpenseModelAdapter());
  Hive.registerAdapter(GroupModelAdapter());
  Hive.registerAdapter(SettlementModelAdapter());
  await Hive.openBox<UserModel>('users');
  await Hive.openBox<GroupModel>('groups');
  await Hive.openBox<ExpenseModel>('expenses');
  await Hive.openBox<SettlementModel>('settlements');
  await Hive.openBox('settings');

  Services.auth = LocalAuthService();
  Services.repository = HiveRepository();
  Services.state = AppState(Services.repository);
  await Services.state.init();
  await Services.state.ensureSelfProfile(Services.currentUserId, name: 'You');
}

ExpenseModel _expense({
  required String id,
  required String title,
  required int cents,
  required String payerId,
  required List<String> participants,
  String category = 'Food & Drink',
  DateTime? at,
  bool personal = false,
}) {
  return ExpenseModel(
    id: id,
    title: title,
    totalAmount: cents,
    payerId: payerId,
    participantIds: personal ? [] : participants,
    groupId: personal ? 'personal' : 'g1',
    createdAt: at ?? DateTime(2026, 9, 10, 12),
    category: category,
    isPersonal: personal,
    splitMap: personal
        ? {}
        : {
            for (var i = 0; i < participants.length; i++)
              participants[i]: cents ~/ participants.length,
          },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String selfId;
  late String rahulId;

  setUpAll(() async {
    await _boot();
    selfId = Services.currentUserId;
    rahulId = 'rahul';
    await Services.state.saveUser(UserModel(id: rahulId, name: 'Rahul'));
    await Services.state.saveGroup(GroupModel(
      id: 'g1',
      name: 'Goa Trip',
      memberIds: [selfId, rahulId],
      createdAt: DateTime(2026, 9, 1),
    ));
    await Services.state.saveExpense(_expense(
      id: 'e1',
      title: 'Dinner',
      cents: 124000,
      payerId: selfId,
      participants: [selfId, rahulId],
      at: DateTime(2026, 9, 10, 12),
    ));
    await Services.state.saveExpense(_expense(
      id: 'e2',
      title: 'Cab',
      cents: 50000,
      payerId: rahulId,
      participants: [selfId, rahulId],
      category: 'Transport',
      at: DateTime(2026, 8, 10, 12),
    ));
    await Services.state.saveExpense(_expense(
      id: 'e3',
      title: 'Coffee',
      cents: 30000,
      payerId: 'personal',
      participants: const [],
      at: DateTime(2026, 9, 11, 12),
      personal: true,
    ));
  });

  group('AskTools.list_transactions', () {
    test('returns all expenses newest first with resolved names', () async {
      final out = await AskTools.execute('list_transactions', {}) as List;
      expect(out.length, 3);
      expect(out.first['title'], 'Coffee'); // newest first
      final dinner = out.firstWhere((e) => e['title'] == 'Dinner');
      expect(dinner['payer'], 'You');
      expect(dinner['group'], 'Goa Trip');
      expect(dinner['amount'], 1240.0); // converted to major units
    });

    test('filters by category loosely', () async {
      final out =
          await AskTools.execute('list_transactions', {'category': 'food'})
              as List;
      expect(out.map((e) => e['title']), ['Coffee', 'Dinner']);
    });

    test('filters by date range', () async {
      final out = await AskTools.execute('list_transactions', {
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
      }) as List;
      expect(out.map((e) => e['title']), containsAll(['Dinner', 'Coffee']));
      expect(out.map((e) => e['title']), isNot(contains('Cab')));
    });

    test('filters personal by group_name "personal"', () async {
      final out =
          await AskTools.execute('list_transactions', {'group_name': 'personal'})
              as List;
      expect(out.map((e) => e['title']), ['Coffee']);
    });

    test('respects limit', () async {
      final out =
          await AskTools.execute('list_transactions', {'limit': 1}) as List;
      expect(out.length, 1);
    });
  });

  group('AskTools.get_spending_summary', () {
    test('aggregates totals and categories', () async {
      final out = await AskTools.execute('get_spending_summary', {})
          as Map<String, dynamic>;
      // 1240 + 500 + 300 = 2040
      expect(out['total'], 2040.0);
      expect(out['count'], 3);
      final byCat = out['by_category'] as Map<String, dynamic>;
      expect(byCat['Food & Drink'], 1540.0); // Dinner + Coffee
      expect(byCat['Transport'], 500.0);
    });

    test('scopes to a date range', () async {
      final out = await AskTools.execute('get_spending_summary', {
        'start_date': '2026-09-01',
        'end_date': '2026-09-30',
      }) as Map<String, dynamic>;
      expect(out['total'], 1540.0);
      expect(out['count'], 2);
    });
  });

  group('AskTools.get_group_balances', () {
    test('computes net balances with converted amounts', () async {
      final out =
          await AskTools.execute('get_group_balances', {'group_name': 'goa'})
              as List;
      // Dinner: You paid, Rahul owes 620. Cab: Rahul paid, You owe 250.
      // Net: You +370, Rahul -370.
      final you = out.firstWhere((e) => e['member'] == 'You');
      final rahul = out.firstWhere((e) => e['member'] == 'Rahul');
      expect(you['net'], 370.0);
      expect(rahul['net'], -370.0);
      expect(you['position'], 'is owed money');
      expect(rahul['position'], 'owes money');
    });
  });

  group('AskTools.get_pending_settlements', () {
    test('reduces debts to the minimal transfers', () async {
      final out = await AskTools.execute('get_pending_settlements', {}) as List;
      expect(out.length, 1);
      expect(out.first['from'], 'Rahul');
      expect(out.first['to'], 'You');
      expect(out.first['amount'], 370.0);
    });
  });

  group('AskTools', () {
    test('unknown tool returns an error object', () async {
      final out = await AskTools.execute('nope', {}) as Map<String, dynamic>;
      expect(out['error'], 'unknown_tool');
    });
  });
}
