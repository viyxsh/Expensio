import 'package:flutter_test/flutter_test.dart';
import 'package:expensio/models/ask_models.dart';

void main() {
  group('AskExpenseAction.fromJson', () {
    test('parses a full action payload', () {
      final a = AskExpenseAction.fromJson({
        'title': 'Dinner',
        'amount': 1240,
        'category': 'Food & Drink',
        'payer': 'me',
        'participants': ['me', 'Rahul', 'Priya'],
        'split': 'equal',
        'date': '2026-09-12',
        'group_name': 'Goa Trip',
        'note': '',
      });
      expect(a.title, 'Dinner');
      expect(a.amount, 1240);
      expect(a.category, 'Food & Drink');
      expect(a.payerName, 'me');
      expect(a.participants, ['me', 'Rahul', 'Priya']);
      expect(a.split, 'equal');
      expect(a.date, DateTime(2026, 9, 12));
      expect(a.groupName, 'Goa Trip');
    });

    test('normalises split and tolerates missing optional fields', () {
      final a = AskExpenseAction.fromJson({
        'title': 'Petrol',
        'amount': 320.5,
        'category': 'Transport',
        'payer': 'me',
        'participants': ['me'],
        'split': 'CUSTOM',
        'custom_amounts': [
          {'name': 'me', 'amount': 320.5},
        ],
      });
      expect(a.split, 'custom');
      expect(a.customAmounts.length, 1);
      expect(a.customAmounts.first.amount, 320.5);
      expect(a.date, isNull);
      expect(a.groupName, '');
    });

    test('custom split flag wins over the default', () {
      final a = AskExpenseAction.fromJson({
        'title': 'X',
        'amount': 100,
        'category': 'General',
        'payer': 'me',
        'participants': [],
        'split': 'custom',
      });
      expect(a.split, 'custom');
      expect(a.customAmounts, isEmpty);
    });
  });

  group('AskComponent.fromJson', () {
    test('maps component type strings to the catalog', () {
      final cases = {
        'stat_tile': AskComponentType.statTile,
        'bar_chart': AskComponentType.barChart,
        'donut': AskComponentType.donut,
        'transaction_list': AskComponentType.transactionList,
        'settle_up_card': AskComponentType.settleUpCard,
        'text': AskComponentType.text,
        'something_else': AskComponentType.text,
      };
      cases.forEach((key, expected) {
        final c = AskComponent.fromJson({'component': key});
        expect(c.type, expected, reason: '$key should map to $expected');
      });
    });

    test('parses a bar chart with numeric values', () {
      final c = AskComponent.fromJson({
        'component': 'bar_chart',
        'caption': 'Food spend',
        'bars': [
          {'label': 'Aug', 'value': 2000},
          {'label': 'Sep', 'value': 1240.5},
        ],
      });
      expect(c.type, AskComponentType.barChart);
      expect(c.caption, 'Food spend');
      expect(c.bars.map((b) => b.value), [2000.0, 1240.5]);
    });

    test('parses a settle-up card with transfers', () {
      final c = AskComponent.fromJson({
        'component': 'settle_up_card',
        'caption': 'Settle up',
        'transfers': [
          {'from': 'Rahul', 'to': 'You', 'amount': 'Rs 620'},
        ],
      });
      expect(c.transfers.length, 1);
      expect(c.transfers.first.from, 'Rahul');
      expect(c.transfers.first.to, 'You');
      expect(c.transfers.first.amount, 'Rs 620');
    });

    test('defaults gracefully on empty json', () {
      final c = AskComponent.fromJson({'component': 'text'});
      expect(c.type, AskComponentType.text);
      expect(c.caption, isEmpty);
      expect(c.body, isEmpty);
      expect(c.stats, isEmpty);
    });
  });

  group('stripMarkdown', () {
    test('removes bold and italic markers', () {
      expect(stripMarkdown('Hi **there**, *friend*'),
          'Hi there, friend');
    });

    test('removes headers, inline code and underscores', () {
      expect(stripMarkdown('## Summary\nSome `code` and __bold__'),
          'Summary\nSome code and bold');
      expect(stripMarkdown('snake_case_word'), 'snake_case_word');
    });

    test('leaves plain text untouched', () {
      const s = 'You spent Rs 1,240 this year across 42 expenses.';
      expect(stripMarkdown(s), s);
    });
  });
}
