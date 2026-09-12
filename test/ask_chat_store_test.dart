import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:expensio/models/ask_models.dart';
import 'package:expensio/services/ask_chat_store.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('expensio_askchat_test');
    Hive.init(tempDir.path);
    await AskChatStore.init();
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('ask_chats');
    await tempDir.delete(recursive: true);
  });

  group('AskChatStore', () {
    test('createChat derives a title from the first message', () async {
      await AskChatStore.createChat('c1', 'How much did I spend this year?');
      final chats = AskChatStore.listChats();
      expect(chats, hasLength(1));
      expect(chats.first['title'], 'How much did I spend this');
    });

    test('long first messages are trimmed to a short title', () async {
      await AskChatStore.createChat('c2',
          'Can you list out all the categories where I spent the most money?');
      expect(AskChatStore.listChats().first['title'].length, lessThan(45));
    });

    test('saveMessages round-trips user texts and components', () async {
      await AskChatStore.createChat('c3', 'hello');
      final comp = const AskComponent(
        type: AskComponentType.donut,
        caption: 'By category',
        slices: [AskSlice(label: 'Food', value: 120)],
      );
      await AskChatStore.saveMessages('c3', [
        {'kind': 'user', 'text': 'spend by category?'},
        {'kind': 'components', 'components': [comp.toJson()]},
      ]);

      final restored = AskChatStore.messagesOf('c3');
      expect(restored, hasLength(2));
      expect(restored[0]['kind'], 'user');
      expect(restored[0]['text'], 'spend by category?');
      final back = AskComponent.fromJson(
          (restored[1]['components'] as List).first as Map<String, dynamic>);
      expect(back.type, AskComponentType.donut);
      expect(back.caption, 'By category');
      expect(back.slices.single.label, 'Food');
      expect(back.slices.single.value, 120);
    });

    test('chats are listed newest-first and deleted by id', () async {
      await AskChatStore.createChat('old', 'first chat');
      await Future.delayed(const Duration(milliseconds: 20));
      await AskChatStore.createChat('new', 'second chat');
      await AskChatStore.saveMessages('old', [
        {'kind': 'user', 'text': 'again'},
      ]);

      final chats = AskChatStore.listChats();
      expect(chats.first['id'], 'old'); // touched more recently

      await AskChatStore.deleteChat('old');
      expect(AskChatStore.listChats().single['id'], 'new');
      expect(AskChatStore.messagesOf('old'), isEmpty);
    });

    test('saveMessages on a deleted chat is a no-op', () async {
      await AskChatStore.createChat('gone', 'temp');
      await AskChatStore.deleteChat('gone');
      await AskChatStore.saveMessages('gone', [
        {'kind': 'user', 'text': 'x'},
      ]);
      expect(AskChatStore.messagesOf('gone'), isEmpty);
    });
  });
}
