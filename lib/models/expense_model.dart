import 'package:hive/hive.dart';
import 'bill_item_model.dart';

part 'expense_model.g.dart';

@HiveType(typeId: 2)
class ExpenseModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  double totalAmount;

  @HiveField(3)
  String payerId;

  @HiveField(4)
  List<String> participantIds;

  @HiveField(5)
  String groupId;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  List<BillItem> items;

  @HiveField(8)
  String category;

  @HiveField(9)
  bool isPersonal;

  // Split map: userId -> amount they owe
  @HiveField(10)
  Map<String, double> splitMap;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.totalAmount,
    required this.payerId,
    required this.participantIds,
    required this.groupId,
    required this.createdAt,
    List<BillItem>? items,
    this.category = 'General',
    this.isPersonal = false,
    Map<String, double>? splitMap,
  })  : items = items ?? [],
        splitMap = splitMap ?? {};
}