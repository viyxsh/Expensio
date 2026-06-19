import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// True for a "ghost"/dummy member added by name only (no real account).
  /// A joiner can claim one of these as themselves; settlements to one are
  /// recorded straight away (there's no real account to confirm). Real
  /// accounts (keyed by Firebase uid) are always false.
  @HiveField(2, defaultValue: false)
  bool isPlaceholder;

  UserModel({required this.id, required this.name, this.isPlaceholder = false});

  @override
  String toString() => name;
}