import 'package:hive/hive.dart';

part 'group_model.g.dart';

@HiveType(typeId: 3)
class GroupModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> memberIds;

  @HiveField(3)
  DateTime createdAt;

  @HiveField(4)
  String description;

  GroupModel({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.createdAt,
    this.description = '',
  });
}