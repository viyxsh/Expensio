import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:expensio/services/category_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('expensio_cats_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await CategoryStore.init();
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('settings');
    await tempDir.delete(recursive: true);
  });

  group('CategoryStore', () {
    test('add creates a custom category with an auto palette colour',
        () async {
      await CategoryStore.add('Salon', '💅');
      final c = CategoryStore.byName('salon');
      expect(c, isNotNull);
      expect(c!.emoji, '💅');
      expect(CategoryStore.palette.contains(c.colorValue), isTrue);
    });

    test('add honours a chosen colour and rejects duplicates', () async {
      await CategoryStore.add('Salon', '💅', colorValue: 0xFF123456);
      await CategoryStore.add('salon', '📦'); // duplicate, ignored
      expect(CategoryStore.all, hasLength(1));
      expect(CategoryStore.byName('Salon')!.colorValue, 0xFF123456);
    });

    test('setColor updates custom categories in place', () async {
      await CategoryStore.add('Salon', '💅');
      await CategoryStore.setColor('salon', 0xFF112233);
      expect(CategoryStore.byName('Salon')!.colorValue, 0xFF112233);
    });

    test('setColor on a built-in persists an override across restarts',
        () async {
      expect(CategoryStore.colorOverride('Groceries'), isNull);
      await CategoryStore.setColor('Groceries', 0xFF123456);
      expect(CategoryStore.colorOverride('Groceries'), 0xFF123456);

      // Simulates an app restart: re-init re-reads from Hive.
      await CategoryStore.init();
      expect(CategoryStore.colorOverride('Groceries'), 0xFF123456);
      expect(CategoryStore.byName('Salon'), isNull);
    });
  });
}
